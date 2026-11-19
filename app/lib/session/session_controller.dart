import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../capture/audio_source.dart';
import '../core/clock.dart';
import '../engines/engine_adapter.dart';
import '../gate/speech_gate.dart';
import '../models/audio_frame.dart';
import '../models/caption_segment.dart';
import '../models/engine_event.dart';
import '../models/engine_profile.dart';
import '../models/pipeline_config.dart';
import '../models/session_snapshot.dart';
import '../models/settings.dart';
import 'battery_watch.dart';
import 'caption_assembler.dart';
import 'cost_meter.dart';
import 'fallback_controller.dart';
import 'session_stats.dart';
import 'settings_store.dart';

/// Builds a fresh [SpeechGate] for each session.
typedef GateFactory = SpeechGate Function();

/// Optional collaborators; each one switches on a feature (stats, cost cap, battery, network).
class SessionExtras {
  /// Creates the optional collaborators.
  const SessionExtras({
    this.stats,
    this.costMeter,
    this.battery,
    this.connectivity,
    this.pipelineSha256 = '',
    this.wallClock = DateTime.now,
  });

  /// Where finished sessions' stats are appended.
  final StatsStore? stats;

  /// Monthly spending tracker.
  final CostMeter? costMeter;

  /// Battery source.
  final BatteryReader? battery;

  /// `true` when the network is reachable.
  final Stream<bool>? connectivity;

  /// Hash of `pipeline.yaml`, recorded in the stats.
  final String pipelineSha256;

  /// Wall-clock source for stats and cost months.
  final DateTime Function() wallClock;
}

/// Owns one captioning session: AudioSource → SpeechGate → engine (with fallback) → assembler.
///
/// The UI only sees immutable [SessionSnapshot]s. This class holds the single per-session
/// failure isolation point, [_guard].
class SessionController {
  /// Creates a controller from injected collaborators (VI).
  SessionController({
    required this._audio,
    required this._gateFactory,
    required this._settings,
    required this._profiles,
    required this._registry,
    required this._clock,
    required this._config,
    this.extras = const SessionExtras(),
  }) : snapshot = ValueNotifier<SessionSnapshot>(
         SessionSnapshot.idle(LanguageMode.auto),
       );

  static final Logger _log = Logger('session');

  /// The current immutable snapshot; listen to it to redraw.
  final ValueNotifier<SessionSnapshot> snapshot;

  /// Optional features.
  final SessionExtras extras;

  final AudioSource _audio;
  final GateFactory _gateFactory;
  final SettingsStore _settings;
  final Map<String, EngineProfile> _profiles;
  final AdapterRegistry _registry;
  final Clock _clock;
  final PipelineConfig _config;

  final CaptionAssembler _assembler = CaptionAssembler();
  SpeechGate? _gate;
  FallbackController? _engine;
  EngineProfile? _active;
  StatsRecorder? _recorder;
  BatteryWatch? _batteryWatch;
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  LanguageMode _mode = LanguageMode.auto;
  LanguageMode? _pendingMode;
  int _startedAtMs = 0;
  bool _ended = false;
  bool _batteryLow = false;
  int? _batteryMinutes;
  String _costLevel = 'ok';
  String? _pauseReason;
  String? _error;
  SessionState _state = SessionState.idle;

  /// Segments so far; unmodifiable.
  List<CaptionSegment> get segments => _assembler.segments;

  int get _sinceStartMs => _clock.nowMs() - _startedAtMs;

  void _emit(SessionState state, {String? error, String? pauseReason}) {
    _state = state;
    _error = error ?? _error;
    _pauseReason = pauseReason;
    snapshot.value = SessionSnapshot(
      state: state,
      languageMode: _mode,
      segments: _assembler.segments,
      errorMessage: _error,
      pauseReason: _pauseReason,
      batteryLow: _batteryLow,
      batteryMinutesLeft: _batteryMinutes,
      costLevel: _costLevel,
    );
  }

  /// Runs [work]; any failure becomes a visible error state, never stale text shown as live.
  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } on Object catch (error, stack) {
      // The one catch-all at the session boundary.
      _log.severe('session failed: ${error.runtimeType}', error, stack);
      _assembler.dropAllProvisional();
      await _end(
        EndReason.error,
        error: 'Captions stopped: ${error.runtimeType}',
      );
    }
  }

  /// Starts a session with the stored settings.
  Future<void> start() => _guard(() async {
    final Settings s = await _settings.load();
    _mode = s.languageMode;
    _ended = false;
    _error = null;
    _startedAtMs = _clock.nowMs();
    _emit(SessionState.starting);
    final EngineProfile active =
        _profiles[s.activeEngineId] ??
        (throw StateError('unknown engine ${s.activeEngineId}'));
    _active = active;
    final EngineProfile? fallback = s.fallbackEngineId == null
        ? null
        : _profiles[s.fallbackEngineId];
    final int? batteryStart = await _readBatteryPercent();
    _recorder = StatsRecorder(
      startedAt: extras.wallClock(),
      languageMode: _mode.name,
      activeEngineId: active.id,
      fallbackEngineId: fallback?.id,
      pipelineSha256: extras.pipelineSha256,
      usdPerHour: active.costUsdPerHour,
      batteryStartPct: batteryStart,
    );
    _batteryWatch = BatteryWatch(_config);
    await extras.stats?.markInProgress(
      startedAt: extras.wallClock(),
      lastSeen: extras.wallClock(),
    );
    _gate = _gateFactory();
    final FallbackController engine = FallbackController(
      registry: _registry,
      clock: _clock,
      config: _config,
      active: active,
      fallback: fallback,
    );
    _engine = engine;
    _subs
      ..add(engine.events.listen(_onTagged))
      ..add(
        engine.status.listen(
          (EngineStatus st) => unawaited(_guard(() async => _onStatus(st))),
        ),
      );
    final String? key = await _settings.apiKey(active.id);
    await engine.open(_mode, <String, String>{'api_key': ?key});
    _subs
      ..add(
        _audio.frames.listen(
          (AudioFrame f) => unawaited(_guard(() => _onFrame(f))),
          onError: (Object e) =>
              unawaited(_guard(() async => throw FormatException('audio: $e'))),
        ),
      )
      ..add(_audio.interruptions.listen(_onInterruption));
    final Stream<bool>? net = extras.connectivity;
    if (net != null) {
      _subs.add(
        net.listen(
          (bool online) =>
              unawaited(_guard(() => engine.setOnline(online: online))),
        ),
      );
    }
    await _audio.start();
  });

  Future<int?> _readBatteryPercent() async {
    final BatteryReader? reader = extras.battery;
    return reader == null ? null : (await reader.read()).percent;
  }

  Future<void> _onFrame(AudioFrame frame) async {
    final SpeechGate? gate = _gate;
    final FallbackController? engine = _engine;
    if (gate == null || engine == null || _ended) {
      return;
    }
    final bool wasInSpeech = gate.inSpeech;
    for (final AudioFrame f in gate.push(frame)) {
      await engine.pushAudio(f);
      if (_state == SessionState.starting) {
        _emit(SessionState.live);
      }
    }
    await engine.setSpeaking(speaking: gate.inSpeech);
    if (wasInSpeech && !gate.inSpeech && _pendingMode != null) {
      final LanguageMode mode = _pendingMode!;
      _pendingMode = null;
      _mode = mode;
      await engine.reopen(mode);
      _emit(_state);
    }
  }

  void _onTagged(TaggedEvent tagged) {
    final EngineEvent event = tagged.event;
    _recorder?.onEvent(event, _sinceStartMs);
    if (event is ErrorEvent && !event.retryable) {
      unawaited(
        _guard(() async => throw StateError('engine error: ${event.code}')),
      );
      return;
    }
    if (event is UsageEvent) {
      unawaited(_guard(() => _onUsage(event)));
    }
    if (_assembler.apply(
      event,
      namespace: tagged.namespace,
      role: tagged.role,
    )) {
      _emit(_state);
    }
  }

  Future<void> _onUsage(UsageEvent event) async {
    final CostMeter? meter = extras.costMeter;
    final EngineProfile? profile = _active;
    if (meter == null || profile == null) {
      return;
    }
    final CostLevel level = await meter.add(
      audioSeconds: event.audioSecondsBilled,
      usdPerHour: profile.costUsdPerHour,
      now: extras.wallClock(),
    );
    if (level != CostLevel.ok) {
      _costLevel = level.name;
      _emit(_state);
    }
  }

  Future<void> _onStatus(EngineStatus status) async {
    final FallbackController? engine = _engine;
    switch (status) {
      case EngineStatus.active:
        _emit(SessionState.live);
      case EngineStatus.fallback:
        _assembler.dropAllProvisional();
        _recordSwitch(engine);
        _emit(SessionState.fallback);
      case EngineStatus.pausedOffline:
        _assembler.dropAllProvisional();
        _emit(SessionState.pausedOffline, pauseReason: 'no connection');
      case EngineStatus.failed:
        throw StateError('engine failed');
    }
  }

  int _recordedSwitches = 0;

  void _recordSwitch(FallbackController? engine) {
    final List<SwitchRecord> all = engine?.switches ?? const <SwitchRecord>[];
    for (final SwitchRecord r in all.skip(_recordedSwitches)) {
      _recorder?.onSwitch(
        atMs: r.atMs,
        toFallback: r.toFallback,
        switchMs: r.switchMs,
      );
    }
    _recordedSwitches = all.length;
  }

  void _onInterruption(AudioInterruption i) {
    if (_ended) {
      return;
    }
    if (i.paused) {
      _recorder?.onInterruptionStart(_sinceStartMs);
      _emit(SessionState.pausedMic, pauseReason: i.reason);
    } else {
      _recorder?.onInterruptionEnd(_sinceStartMs);
      final FallbackController? engine = _engine;
      _emit(
        engine?.state == EngineStatus.fallback
            ? SessionState.fallback
            : SessionState.live,
      );
    }
  }

  /// Changes the language mode; it applies at the next VAD pause (research R-14).
  void setLanguageMode(LanguageMode mode) {
    if (_state == SessionState.idle || _state == SessionState.ended) {
      _mode = mode;
      _emit(_state);
      return;
    }
    _pendingMode = mode;
  }

  /// Records that the session is still alive (so an OS kill can be dated); about once a minute.
  Future<void> heartbeat() async {
    final StatsRecorder? recorder = _recorder;
    if (recorder != null && !_ended) {
      await extras.stats?.markInProgress(
        startedAt: recorder.startedAt,
        lastSeen: extras.wallClock(),
      );
    }
  }

  /// Samples the battery; call about once a minute while a session runs.
  Future<void> checkBattery() async {
    await heartbeat();
    final BatteryReader? reader = extras.battery;
    final BatteryWatch? watch = _batteryWatch;
    if (reader == null || watch == null || _ended) {
      return;
    }
    final BatteryWarning? warning = watch.sample(
      await reader.read(),
      _sinceStartMs,
    );
    final bool low = warning != null;
    if (low != _batteryLow || warning?.minutesLeft != _batteryMinutes) {
      if (low && !_batteryLow) {
        _recorder?.batteryWarnings++;
      }
      _batteryLow = low;
      _batteryMinutes = warning?.minutesLeft;
      _emit(_state);
    }
  }

  /// Stops the session; the transcript stays until the next start.
  Future<void> stop() => _guard(() async {
    await _audio.stop();
    await _engine?.finish();
    await _end(EndReason.userStop);
  });

  Future<void> _end(EndReason reason, {String? error}) async {
    if (_ended) {
      return;
    }
    _ended = true;
    _recorder?.setSpans(_gate?.spans ?? const <SpeechSpan>[]);
    _recordSwitch(_engine);
    for (final StreamSubscription<Object?> sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _engine?.cancel();
    _engine = null;
    _gate = null;
    await _writeStats(reason);
    await extras.stats?.clearInProgress();
    _emit(SessionState.ended, error: error);
  }

  Future<void> _writeStats(EndReason reason) async {
    final StatsRecorder? recorder = _recorder;
    final StatsStore? store = extras.stats;
    if (recorder == null || store == null) {
      return;
    }
    recorder.batteryEndPct = await _readBatteryPercent();
    try {
      await store.append(
        recorder.finish(
          sessionMs: _sinceStartMs,
          reason: reason,
          sessionId: StatsRecorder.newId(),
        ),
      );
    } on Object catch (error) {
      // Stats are best-effort; failing to write them must not hide the caption error.
      _log.warning('could not write session stats: ${error.runtimeType}');
    }
    _recorder = null;
  }
}
