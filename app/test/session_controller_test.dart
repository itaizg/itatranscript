import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/core/clock.dart';
import 'package:itatranscript/engines/engine_adapter.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/gate/speech_gate.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/engine_profile.dart';
import 'package:itatranscript/models/pipeline_config.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/models/settings.dart';
import 'package:itatranscript/session/session_controller.dart';
import 'package:itatranscript/session/settings_store.dart';

import 'fakes.dart';
import 'support.dart';

class Rig {
  Rig({String engine = 'fake'}) {
    profiles = parseEngines(readShared('engines.yaml'));
    config = parsePipeline(
      readShared('pipeline.yaml'),
      readSharedBytes('models/silero_vad.onnx'),
    );
    store = SettingsStore(
      preferences: MemoryKeyValueStore(),
      secrets: MemorySecretStore(),
      defaults: Settings.defaults(activeEngineId: engine),
    );
    registry = AdapterRegistry(<String, AdapterFactory>{
      'fake': (EngineProfile p, Clock c) => _build('fake'),
      'apple_speech': (EngineProfile p, Clock c) => _build('apple_speech'),
    });
    controller = SessionController(
      audio: audio,
      gateFactory: () => SpeechGate(model, config.vad),
      settings: store,
      profiles: profiles,
      registry: registry,
      clock: FakeClock(),
    );
    controller.snapshot.addListener(
      () => states.add(controller.snapshot.value.state),
    );
  }

  late final Map<String, EngineProfile> profiles;
  late final PipelineConfig config;
  late final SettingsStore store;
  late final AdapterRegistry registry;
  late final SessionController controller;
  final FakeAudioSource audio = FakeAudioSource();
  final SwitchableModel model = SwitchableModel();
  final List<ScriptedEngine> engines = <ScriptedEngine>[];
  final List<String> built = <String>[];
  final List<SessionState> states = <SessionState>[];

  EngineAdapter _build(String key) {
    built.add(key);
    final ScriptedEngine e = ScriptedEngine();
    engines.add(e);
    return e;
  }

  /// 600 ms of "speech": enough for the gate to open and pass frames.
  Future<void> speak() async {
    model.level = 0.9;
    audio.emitFrames(30);
    await pumpEventQueue();
  }

  /// 600 ms of silence: the gate closes the utterance.
  Future<void> hush() async {
    model.level = 0.0;
    audio.emitFrames(30);
    await pumpEventQueue();
  }
}

void main() {
  test('idle → starting → live → ended', () async {
    final Rig r = Rig();
    await r.controller.start();
    expect(r.controller.snapshot.value.state, SessionState.starting);
    expect(r.audio.started, isTrue);
    await r.speak();
    expect(r.controller.snapshot.value.state, SessionState.live);
    expect(r.engines.single.received, isNotEmpty);
    await r.controller.stop();
    expect(r.controller.snapshot.value.state, SessionState.ended);
    expect(r.states, <SessionState>[
      SessionState.starting,
      SessionState.live,
      SessionState.ended,
    ]);
    expect(r.audio.started, isFalse);
  });

  test('engine events become captions in the snapshot', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single
      ..emit(
        const PartialEvent(
          tMs: 1,
          segmentId: 's1',
          text: 'hel',
          lang: 'en',
          startMs: 0,
        ),
      )
      ..emit(
        const FinalEvent(
          tMs: 2,
          segmentId: 's1',
          text: 'hello',
          lang: 'en',
          startMs: 0,
          endMs: 500,
        ),
      );
    await pumpEventQueue();
    final List<CaptionSegment> segs = r.controller.snapshot.value.segments;
    expect(segs.single.text, 'hello');
    expect(segs.single.status, SegmentStatus.finalized);
  });

  test('silence is never sent to the engine', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.hush();
    expect(r.engines.single.received, isEmpty);
    expect(r.controller.snapshot.value.state, SessionState.starting);
  });

  test('a language change applies at the next VAD pause via finish + reopen (R-14)', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.controller.setLanguageMode(LanguageMode.he);
    expect(r.engines, hasLength(1), reason: 'no reopen while speech is open');
    expect(r.engines.first.finished, isFalse);
    await r.hush();
    expect(r.engines.first.finished, isTrue);
    expect(r.engines, hasLength(2));
    expect(r.engines.last.openedWith, LanguageMode.he);
    expect(r.controller.snapshot.value.languageMode, LanguageMode.he);
  });

  test('a language change keeps the segments of the same session', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.first.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's1',
        text: 'one',
        lang: 'en',
        startMs: 0,
        endMs: 5,
      ),
    );
    await pumpEventQueue();
    r.controller.setLanguageMode(LanguageMode.he);
    await r.hush();
    r.engines.last.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's1',
        text: 'שתיים',
        lang: 'he',
        startMs: 0,
        endMs: 5,
      ),
    );
    await pumpEventQueue();
    expect(
      r.controller.snapshot.value.segments.map((CaptionSegment s) => s.text),
      <String>['one', 'שתיים'],
    );
  });

  test('an engine stream error becomes a visible error state, never stale text shown as live', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single
      ..emit(
        const FinalEvent(
          tMs: 1,
          segmentId: 's1',
          text: 'kept',
          lang: 'en',
          startMs: 0,
          endMs: 5,
        ),
      )
      ..emit(
        const PartialEvent(
          tMs: 2,
          segmentId: 's2',
          text: 'stale',
          lang: 'en',
          startMs: 6,
        ),
      );
    await pumpEventQueue();
    r.engines.single.out.addError(StateError('socket closed'));
    await pumpEventQueue();
    final SessionSnapshot s = r.controller.snapshot.value;
    expect(s.state, SessionState.ended);
    expect(s.errorMessage, isNotNull);
    expect(s.segments.map((CaptionSegment x) => x.text), <String>['kept']);
    expect(r.engines.single.cancelled, isTrue);
  });

  test('a non-retryable engine error ends the session visibly', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single.emit(
      const ErrorEvent(
        tMs: 1,
        code: 'auth',
        message: 'bad key',
        retryable: false,
      ),
    );
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.ended);
    expect(
      r.controller.snapshot.value.errorMessage,
      contains('Captions stopped'),
    );
  });

  test('the engine closing while live is an error, not silence', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single.emit(const ClosedEvent(tMs: 9));
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.ended);
  });

  test(
    'a failure to start (privacy gate, missing engine) is a visible error',
    () async {
      final Rig r = Rig(engine: 'does-not-exist');
      await r.controller.start();
      expect(r.controller.snapshot.value.state, SessionState.ended);
      expect(r.controller.snapshot.value.errorMessage, isNotNull);
    },
  );

  test('changing active_engine_id in Settings builds that adapter next session, with no code change', () async {
    final Rig first = Rig();
    await first.controller.start();
    expect(first.built, <String>['fake']);

    final Rig second = Rig();
    await second.store.save(
      (await second.store.load()).copyWith(activeEngineId: 'apple-ondevice'),
    );
    await second.controller.start();
    expect(second.built, <String>['apple_speech']);
  });

  test('snapshots are immutable', () async {
    final Rig r = Rig();
    await r.controller.start();
    expect(
      () => r.controller.snapshot.value.segments.add(
        const CaptionSegment(
          id: 'x',
          status: SegmentStatus.finalized,
          text: '',
          lang: 'en',
          startMs: 0,
          endMs: 0,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(r.controller.snapshot, isA<ValueListenable<SessionSnapshot>>());
  });
}
