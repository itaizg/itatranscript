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
import '../models/session_snapshot.dart';
import '../models/settings.dart';
import 'caption_assembler.dart';
import 'settings_store.dart';

/// Builds a fresh [SpeechGate] for each session.
typedef GateFactory = SpeechGate Function();

/// Owns one captioning session: AudioSource → SpeechGate → adapter → assembler.
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
  }) : snapshot = ValueNotifier<SessionSnapshot>(
         SessionSnapshot.idle(LanguageMode.auto),
       );

  static final Logger _log = Logger('session');

  /// The current immutable snapshot; listen to it to redraw.
  final ValueNotifier<SessionSnapshot> snapshot;

  final AudioSource _audio;
  final GateFactory _gateFactory;
  final SettingsStore _settings;
  final Map<String, EngineProfile> _profiles;
  final AdapterRegistry _registry;
  final Clock _clock;

  final CaptionAssembler _assembler = CaptionAssembler();
  SpeechGate? _gate;
  EngineAdapter? _adapter;
  EngineProfile? _profile;
  StreamSubscription<EngineEvent>? _eventSub;
  StreamSubscription<AudioFrame>? _frameSub;
  StreamSubscription<AudioInterruption>? _interruptSub;
  LanguageMode _mode = LanguageMode.auto;
  LanguageMode? _pendingMode;
  int _generation = 0;
  bool _switching = false;

  /// Segments so far; unmodifiable.
  List<CaptionSegment> get segments => _assembler.segments;

  void _emit(SessionState state, {String? error, String? pauseReason}) {
    snapshot.value = SessionSnapshot(
      state: state,
      languageMode: _mode,
      segments: _assembler.segments,
      errorMessage: error,
      pauseReason: pauseReason,
    );
  }

  /// Runs [work]; any failure becomes a visible error state, never stale text shown as live.
  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } on Object catch (error, stack) {
      // the one catch-all at the session boundary
      _log.severe('session failed: ${error.runtimeType}', error, stack);
      await _teardown();
      _assembler.dropProvisional('g$_generation');
      _emit(
        SessionState.ended,
        error: 'Captions stopped: ${error.runtimeType}',
      );
    }
  }

  /// Starts a session with the stored settings.
  Future<void> start() => _guard(() async {
    final Settings s = await _settings.load();
    _mode = s.languageMode;
    _emit(SessionState.starting);
    final EngineProfile profile =
        _profiles[s.activeEngineId] ??
        (throw StateError('unknown engine ${s.activeEngineId}'));
    _profile = profile;
    _gate = _gateFactory();
    await _openAdapter(profile);
    _frameSub = _audio.frames.listen(
      (AudioFrame f) => unawaited(_guard(() => _onFrame(f))),
      onError: (Object e) =>
          unawaited(_guard(() async => throw FormatException('audio: $e'))),
    );
    _interruptSub = _audio.interruptions.listen(_onInterruption);
    await _audio.start();
  });

  Future<void> _openAdapter(EngineProfile profile) async {
    final EngineAdapter adapter = _registry.create(profile, _clock);
    _adapter = adapter;
    _generation++;
    final String ns = 'g$_generation';
    _eventSub = adapter.events.listen(
      (EngineEvent e) => _onEvent(e, ns),
      onError: (Object e) =>
          unawaited(_guard(() async => throw StateError('engine stream: $e'))),
    );
    final String? key = await _settings.apiKey(profile.id);
    await adapter.open(profile, _mode, <String, String>{'api_key': ?key});
  }

  Future<void> _onFrame(AudioFrame frame) async {
    final SpeechGate? gate = _gate;
    final EngineAdapter? adapter = _adapter;
    if (gate == null || adapter == null || _switching) {
      return;
    }
    final bool wasInSpeech = gate.inSpeech;
    for (final AudioFrame f in gate.push(frame)) {
      await adapter.pushAudio(f);
      if (snapshot.value.state == SessionState.starting) {
        _emit(SessionState.live);
      }
    }
    if (wasInSpeech && !gate.inSpeech && _pendingMode != null) {
      await _applyPendingMode();
    }
  }

  void _onEvent(EngineEvent event, String namespace) {
    if (event is ErrorEvent && !event.retryable) {
      unawaited(
        _guard(() async => throw StateError('engine error: ${event.code}')),
      );
      return;
    }
    if (event is ClosedEvent && snapshot.value.state == SessionState.live) {
      unawaited(
        _guard(() async => throw StateError('engine closed unexpectedly')),
      );
      return;
    }
    if (_assembler.apply(event, namespace: namespace)) {
      _emit(snapshot.value.state);
    }
  }

  void _onInterruption(AudioInterruption i) {
    if (snapshot.value.state == SessionState.ended) {
      return;
    }
    _emit(
      i.paused ? SessionState.pausedMic : SessionState.live,
      pauseReason: i.paused ? i.reason : null,
    );
  }

  /// Changes the language mode; it applies at the next VAD pause (research R-14).
  void setLanguageMode(LanguageMode mode) {
    if (snapshot.value.state == SessionState.idle ||
        snapshot.value.state == SessionState.ended) {
      _mode = mode;
      _emit(snapshot.value.state);
      return;
    }
    _pendingMode = mode;
  }

  Future<void> _applyPendingMode() async {
    final LanguageMode? mode = _pendingMode;
    final EngineProfile? profile = _profile;
    final EngineAdapter? old = _adapter;
    if (mode == null || profile == null || old == null) {
      return;
    }
    _switching = true;
    _pendingMode = null;
    await old.finish();
    await _eventSub?.cancel();
    _mode = mode;
    await _openAdapter(profile);
    _switching = false;
    _emit(snapshot.value.state);
  }

  /// Stops the session; the transcript stays until the next start.
  Future<void> stop() => _guard(() async {
    final EngineAdapter? adapter = _adapter;
    await _audio.stop();
    await adapter?.finish();
    await _teardown();
    _emit(SessionState.ended);
  });

  Future<void> _teardown() async {
    await _frameSub?.cancel();
    await _interruptSub?.cancel();
    await _eventSub?.cancel();
    _frameSub = _interruptSub = null;
    _eventSub = null;
    final EngineAdapter? adapter = _adapter;
    _adapter = null;
    if (adapter != null) {
      await adapter.cancel();
    }
    _gate = null;
  }
}
