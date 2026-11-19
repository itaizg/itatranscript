import 'dart:async';
import 'dart:collection';

import '../core/clock.dart';
import '../engines/engine_adapter.dart';
import '../models/audio_frame.dart';
import '../models/caption_segment.dart';
import '../models/engine_event.dart';
import '../models/engine_profile.dart';
import '../models/pipeline_config.dart';
import '../models/session_snapshot.dart';

/// An engine event with where it came from.
class TaggedEvent {
  /// Creates a tagged event.
  const TaggedEvent(this.event, this.role, this.namespace);

  /// The event.
  final EngineEvent event;

  /// Active or fallback engine.
  final EngineRole role;

  /// Adapter-instance namespace, to keep segment ids apart.
  final String namespace;
}

/// Where captions are coming from (research R-7).
enum EngineStatus {
  /// The selected engine is working.
  active,

  /// Running on the on-device engine after a loss.
  fallback,

  /// Lost, and the fallback cannot cover this language (or there is none).
  pausedOffline,

  /// A device engine failed; nothing to fall back to.
  failed,
}

/// One switch between engines, for the session stats (FR-024).
class SwitchRecord {
  /// Creates a record; [switchMs] is set when switching to the fallback.
  const SwitchRecord({
    required this.atMs,
    required this.toFallback,
    this.switchMs,
  });

  /// Time of the switch since the session started (ms).
  final int atMs;

  /// True when switching to the fallback, false when switching back.
  final bool toFallback;

  /// Detection-to-first-fallback-audio time (ms), for switches to the fallback.
  final int? switchMs;
}

/// Wraps the active engine, and the on-device fallback, behind one adapter-like surface.
///
/// Triggers: `health: lost`, a socket error, or no events for `silenceTimeoutMs` during speech.
/// On a trigger it opens the fallback, replays the RAM-only ring buffer from the last final
/// onward (so nothing is lost or repeated), and drops the lost engine's open provisional text.
/// It switches back at the next VAD pause once the connection is healthy.
class FallbackController {
  /// Creates the controller.
  FallbackController({
    required this.registry,
    required this.clock,
    required this.config,
    required this.active,
    required this.fallback,
  });

  /// Builds adapters.
  final AdapterRegistry registry;

  /// Time source.
  final Clock clock;

  /// Pipeline thresholds (ring buffer length, silence timeout).
  final PipelineConfig config;

  /// The engine the user selected.
  final EngineProfile active;

  /// The on-device fallback, or null for none.
  final EngineProfile? fallback;

  final StreamController<TaggedEvent> _events =
      StreamController<TaggedEvent>.broadcast();
  final StreamController<EngineStatus> _status =
      StreamController<EngineStatus>.broadcast();
  final Queue<AudioFrame> _ring = Queue<AudioFrame>();
  final List<SwitchRecord> _switches = <SwitchRecord>[];

  EngineAdapter? _adapter;
  StreamSubscription<EngineEvent>? _sub;
  EngineProfile? _current;
  EngineStatus _state = EngineStatus.active;
  LanguageMode _mode = LanguageMode.auto;
  Map<String, String> _secrets = const <String, String>{};
  int _generation = 0;
  int _firstFrameMs = -1;
  int _lastFinalEndMs = 0;
  int _lastEventAtMs = 0;
  int _sessionStartMs = 0;
  bool _speaking = false;
  bool _online = true;
  bool _switchBackPending = false;
  bool _busy = false;

  /// Events from whichever engine is current.
  Stream<TaggedEvent> get events => _events.stream;

  /// Status changes.
  Stream<EngineStatus> get status => _status.stream;

  /// The current status.
  EngineStatus get state => _state;

  /// Switches so far, oldest first.
  List<SwitchRecord> get switches => List<SwitchRecord>.unmodifiable(_switches);

  String get _namespace => 'g$_generation';

  /// Opens the active engine.
  Future<void> open(LanguageMode mode, Map<String, String> secrets) async {
    _mode = mode;
    _secrets = secrets;
    _sessionStartMs = clock.nowMs();
    await _openEngine(active);
  }

  Future<void> _openEngine(EngineProfile profile) async {
    final EngineAdapter adapter = registry.create(profile, clock);
    _generation++;
    final String ns = _namespace;
    final EngineRole role = profile == active
        ? EngineRole.active
        : EngineRole.fallback;
    _adapter = adapter;
    _current = profile;
    _firstFrameMs = -1;
    _lastFinalEndMs = 0;
    _lastEventAtMs = clock.nowMs();
    _sub = adapter.events.listen(
      (EngineEvent e) => _onEvent(e, ns, role),
      onError: (Object e) => unawaited(_onLoss('stream error', ns)),
    );
    await adapter.open(profile, _mode, _secrets);
  }

  void _onEvent(EngineEvent event, String ns, EngineRole role) {
    if (ns != _namespace) {
      return;
    }
    _lastEventAtMs = clock.nowMs();
    if (event is FinalEvent) {
      _lastFinalEndMs = event.endMs > _lastFinalEndMs
          ? event.endMs
          : _lastFinalEndMs;
    }
    if (role == EngineRole.active) {
      if (event is HealthEvent && event.state == 'lost') {
        unawaited(_onLoss('health lost', ns));
        return;
      }
      if (event is ErrorEvent && event.code == 'network') {
        unawaited(_onLoss('network error', ns));
        return;
      }
      if (event is ClosedEvent &&
          _state == EngineStatus.active &&
          !_finishing) {
        unawaited(_onLoss('closed unexpectedly', ns));
        return;
      }
    }
    _events.add(TaggedEvent(event, role, ns));
  }

  bool _finishing = false;

  Future<void> _onLoss(String reason, String ns) async {
    if (ns != _namespace || _busy) {
      return;
    }
    _busy = true;
    try {
      final int detectedAt = clock.nowMs();
      final EngineProfile lost = _current!;
      await _closeCurrent();
      if (lost.runsOn != 'cloud') {
        _setState(EngineStatus.failed);
        return;
      }
      final EngineProfile? fb = fallback;
      if (fb == null || !_supports(fb)) {
        _setState(EngineStatus.pausedOffline);
        return;
      }
      await _openEngine(fb);
      _setState(EngineStatus.fallback);
      await _replayRing();
      _switches.add(
        SwitchRecord(
          atMs: detectedAt - _sessionStartMs,
          toFallback: true,
          switchMs: clock.nowMs() - detectedAt,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  bool _supports(EngineProfile profile) {
    final Set<String> needed = _mode == LanguageMode.auto
        ? <String>{'he', 'en'}
        : <String>{_mode.name};
    return profile.languages.toSet().containsAll(needed);
  }

  Future<void> _replayRing() async {
    final EngineAdapter? adapter = _adapter;
    if (adapter == null || _ring.isEmpty) {
      return;
    }
    for (final AudioFrame f in List<AudioFrame>.of(_ring)) {
      // Audio the lost engine already finalized is not sent again, so nothing is repeated.
      if (f.tMs - _replayBaseMs < _replayFrom) {
        continue;
      }
      await adapter.pushAudio(f);
    }
  }

  int _replayFrom = 0;
  int _replayBaseMs = 0;

  Future<void> _closeCurrent() async {
    _replayFrom = _lastFinalEndMs;
    _replayBaseMs = _firstFrameMs < 0 ? 0 : _firstFrameMs;
    await _sub?.cancel();
    _sub = null;
    final EngineAdapter? adapter = _adapter;
    _adapter = null;
    if (adapter != null) {
      await adapter.cancel();
    }
  }

  void _setState(EngineStatus s) {
    _state = s;
    _status.add(s);
  }

  /// Sends a gated frame to the current engine, and keeps it in the RAM-only ring buffer.
  Future<void> pushAudio(AudioFrame frame) async {
    _ring.addLast(frame);
    final int maxFrames = config.ringBufferS * 1000 ~/ kFrameMs;
    while (_ring.length > maxFrames) {
      _ring.removeFirst();
    }
    if (_firstFrameMs < 0) {
      _firstFrameMs = frame.tMs;
    }
    if (_state == EngineStatus.active &&
        _speaking &&
        clock.nowMs() - _lastEventAtMs >= config.silenceTimeoutMs) {
      await _onLoss('no events for ${config.silenceTimeoutMs} ms', _namespace);
    }
    final EngineAdapter? adapter = _adapter;
    if (adapter != null && !_busy) {
      await adapter.pushAudio(frame);
    }
  }

  /// Tells the controller whether the VAD currently sees speech. A pause is the moment to
  /// switch back (and to apply a language change).
  Future<void> setSpeaking({required bool speaking}) async {
    final bool paused = _speaking && !speaking;
    _speaking = speaking;
    if (paused && _switchBackPending && _state == EngineStatus.fallback) {
      await _switchBack();
    }
  }

  /// Connection changes from `connectivity_plus`.
  Future<void> setOnline({required bool online}) async {
    _online = online;
    if (!online) {
      if (_state == EngineStatus.active && active.runsOn == 'cloud') {
        await _onLoss('offline', _namespace);
      }
      return;
    }
    if (_state == EngineStatus.pausedOffline) {
      await _recover();
    } else if (_state == EngineStatus.fallback) {
      if (_speaking) {
        _switchBackPending = true;
      } else {
        await _switchBack();
      }
    }
  }

  Future<void> _recover() async {
    _busy = true;
    try {
      await _openEngine(active);
      _setState(EngineStatus.active);
    } finally {
      _busy = false;
    }
  }

  Future<void> _switchBack() async {
    if (!_online || _busy) {
      return;
    }
    _busy = true;
    _switchBackPending = false;
    try {
      final int started = clock.nowMs();
      _finishing = true;
      await _adapter?.finish();
      await _closeCurrent();
      _finishing = false;
      await _openEngine(active);
      _setState(EngineStatus.active);
      _switches.add(
        SwitchRecord(atMs: started - _sessionStartMs, toFallback: false),
      );
    } finally {
      _busy = false;
      _finishing = false;
    }
  }

  /// Finishes and reopens the current engine with [mode] (research R-14).
  Future<void> reopen(LanguageMode mode) async {
    final EngineProfile? profile = _current;
    if (profile == null) {
      return;
    }
    _finishing = true;
    await _adapter?.finish();
    await _closeCurrent();
    _finishing = false;
    _mode = mode;
    await _openEngine(profile);
  }

  /// Flushes the current engine and closes it.
  Future<void> finish() async {
    _finishing = true;
    await _adapter?.finish();
    await _closeCurrent();
    _finishing = false;
  }

  /// Stops everything now.
  Future<void> cancel() => _closeCurrent();
}
