import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/core/clock.dart';
import 'package:itatranscript/engines/engine_adapter.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/engine_profile.dart';
import 'package:itatranscript/models/pipeline_config.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/session/fallback_controller.dart';

import 'fakes.dart';
import 'support.dart';

class Rig {
  Rig({
    this.mode = LanguageMode.auto,
    bool withFallback = true,
    List<String>? fallbackLanguages,
  }) {
    final Map<String, EngineProfile> all = parseEngines(
      readShared('engines.yaml'),
    );
    cloud = all['google-stt-he']!;
    EngineProfile fb = all['apple-ondevice']!;
    if (fallbackLanguages != null) {
      fb = EngineProfile.fromJson(<String, Object?>{
        ...fb.toJson(),
        'languages': fallbackLanguages,
      });
    }
    config = parsePipeline(
      readShared('pipeline.yaml'),
      readSharedBytes('models/silero_vad.onnx'),
    );
    registry = AdapterRegistry(<String, AdapterFactory>{
      'google_streaming': (EngineProfile p, Clock c) => _make(cloudEngines),
      'apple_speech': (EngineProfile p, Clock c) => _make(fallbackEngines),
      'fake': (EngineProfile p, Clock c) => _make(cloudEngines),
    });
    controller = FallbackController(
      registry: registry,
      clock: clock,
      config: config,
      active: cloud,
      fallback: withFallback ? fb : null,
    );
    controller.events.listen(tagged.add);
    controller.status.listen(statuses.add);
  }

  late final EngineProfile cloud;
  late final PipelineConfig config;
  late final AdapterRegistry registry;
  late final FallbackController controller;
  late final LanguageMode mode;
  final FakeClock clock = FakeClock();
  final List<ScriptedEngine> cloudEngines = <ScriptedEngine>[];
  final List<ScriptedEngine> fallbackEngines = <ScriptedEngine>[];
  final List<TaggedEvent> tagged = <TaggedEvent>[];
  final List<EngineStatus> statuses = <EngineStatus>[];
  int _seq = 0;

  EngineAdapter _make(List<ScriptedEngine> into) {
    final ScriptedEngine e = ScriptedEngine();
    into.add(e);
    return e;
  }

  Future<void> open() => controller.open(mode, const <String, String>{});

  Future<void> push(int frames) async {
    for (int i = 0; i < frames; i++) {
      await controller.pushAudio(
        AudioFrame(seq: _seq, tMs: _seq * kFrameMs, pcm: framesPcm),
      );
      _seq++;
    }
  }

  static final framesPcm = readWavPcm('fixtures/silence-5s.wav')
      .sublist(0, kFrameBytes);
}

FinalEvent _final(String id, String text, int endMs, {String lang = 'en'}) =>
    FinalEvent(
      tMs: endMs + 100,
      segmentId: id,
      text: text,
      lang: lang,
      startMs: 0,
      endMs: endMs,
    );

void main() {
  test('health: lost switches to the fallback within 3 s and replays only unfinalized audio', () async {
    final Rig r = Rig();
    await r.open();
    await r.push(100); // 2 s of audio, frames 0..99
    r.cloudEngines.single.emit(_final('s1', 'already final', 1000));
    await pumpEventQueue();
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'socket closed'),
    );
    await pumpEventQueue();

    expect(r.controller.state, EngineStatus.fallback);
    expect(r.statuses, <EngineStatus>[EngineStatus.fallback]);
    expect(r.cloudEngines.single.cancelled, isTrue);
    // Frames before the last final (t < 1000 ms) are not sent again: 50 of the 100 are replayed.
    expect(r.fallbackEngines.single.received, hasLength(50));
    expect(r.fallbackEngines.single.received.first.tMs, 1000);
    expect(r.controller.switches.single.toFallback, isTrue);
    expect(r.controller.switches.single.switchMs, lessThanOrEqualTo(3000));
  });

  test('the already-final text is delivered exactly once, and fallback events are tagged', () async {
    final Rig r = Rig();
    await r.open();
    await r.push(50);
    r.cloudEngines.single.emit(_final('s1', 'one', 500));
    await pumpEventQueue();
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
    );
    await pumpEventQueue();
    r.fallbackEngines.single.emit(_final('s1', 'two', 400));
    await pumpEventQueue();
    final List<TaggedEvent> finals = r.tagged
        .where((TaggedEvent t) => t.event is FinalEvent)
        .toList();
    expect(
      finals.map((TaggedEvent t) => (t.event as FinalEvent).text),
      <String>['one', 'two'],
    );
    expect(finals.map((TaggedEvent t) => t.role), <EngineRole>[
      EngineRole.active,
      EngineRole.fallback,
    ]);
    expect(
      finals[0].namespace,
      isNot(finals[1].namespace),
      reason: 'same segment id, different adapter',
    );
  });

  test('a stream error (socket error) triggers the fallback', () async {
    final Rig r = Rig();
    await r.open();
    await r.push(10);
    r.cloudEngines.single.out.addError(StateError('socket'));
    await pumpEventQueue();
    expect(r.controller.state, EngineStatus.fallback);
  });

  test('an ErrorEvent with code network triggers the fallback; an auth error does not', () async {
    final Rig a = Rig();
    await a.open();
    a.cloudEngines.single.emit(
      const ErrorEvent(tMs: 1, code: 'auth', message: 'k', retryable: false),
    );
    await pumpEventQueue();
    expect(a.controller.state, EngineStatus.active);
    final Rig b = Rig();
    await b.open();
    b.cloudEngines.single.emit(
      const ErrorEvent(tMs: 1, code: 'network', message: 'n', retryable: true),
    );
    await pumpEventQueue();
    expect(b.controller.state, EngineStatus.fallback);
  });

  test('2 s without events during speech triggers the fallback; during silence it does not', () async {
    final Rig quiet = Rig();
    await quiet.open();
    await quiet.controller.setSpeaking(speaking: false);
    await quiet.clock.advance(5000);
    await quiet.push(1);
    expect(quiet.controller.state, EngineStatus.active);

    final Rig talking = Rig();
    await talking.open();
    await talking.controller.setSpeaking(speaking: true);
    await talking.push(10);
    await talking.clock.advance(2000);
    await talking.push(1);
    expect(talking.controller.state, EngineStatus.fallback);
  });

  test('switching back happens at the next VAD pause once the connection returns, with no loss or repeat', () async {
    final Rig r = Rig();
    await r.open();
    await r.controller.setSpeaking(speaking: true);
    await r.push(20);
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
    );
    await pumpEventQueue();
    expect(r.controller.state, EngineStatus.fallback);

    await r.controller.setOnline(online: true); // still speaking: must wait
    expect(r.controller.state, EngineStatus.fallback);
    expect(r.cloudEngines, hasLength(1));

    await r.controller.setSpeaking(speaking: false); // the pause
    expect(r.controller.state, EngineStatus.active);
    expect(
      r.fallbackEngines.single.finished,
      isTrue,
      reason: 'fallback flushed its finals first',
    );
    expect(r.cloudEngines, hasLength(2));
    expect(r.controller.switches.map((SwitchRecord s) => s.toFallback), <bool>[
      true,
      false,
    ]);
    await pumpEventQueue();
    expect(r.statuses, <EngineStatus>[
      EngineStatus.fallback,
      EngineStatus.active,
    ]);
  });

  test(
    'going offline moves a cloud engine to the fallback straight away',
    () async {
      final Rig r = Rig();
      await r.open();
      await r.controller.setOnline(online: false);
      expect(r.controller.state, EngineStatus.fallback);
    },
  );

  test('paused_offline when the fallback does not support the language, and recovery when back online', () async {
    final Rig r = Rig(mode: LanguageMode.he, fallbackLanguages: <String>['en']);
    await r.open();
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
    );
    await pumpEventQueue();
    expect(r.controller.state, EngineStatus.pausedOffline);
    expect(r.fallbackEngines, isEmpty);
    await r.controller.setOnline(online: true);
    expect(r.controller.state, EngineStatus.active);
    expect(r.cloudEngines, hasLength(2));
  });

  test('paused_offline when no fallback engine is configured', () async {
    final Rig r = Rig(withFallback: false);
    await r.open();
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
    );
    await pumpEventQueue();
    expect(r.controller.state, EngineStatus.pausedOffline);
  });

  test(
    'the ring buffer is bounded by ring_buffer_s from pipeline.yaml (RAM only)',
    () async {
      final Rig r = Rig();
      await r.open();
      await r.push(600); // 12 s
      r.cloudEngines.single.emit(
        const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
      );
      await pumpEventQueue();
      expect(
        r.fallbackEngines.single.received.length,
        r.config.ringBufferS * 1000 ~/ kFrameMs,
      );
    },
  );

  test('a device engine failing is a failure, not a fallback', () async {
    final Map<String, EngineProfile> all = parseEngines(
      readShared('engines.yaml'),
    );
    final Rig r = Rig();
    final FallbackController c = FallbackController(
      registry: r.registry,
      clock: r.clock,
      config: r.config,
      active: all['fake']!,
      fallback: all['apple-ondevice'],
    );
    await c.open(LanguageMode.auto, const <String, String>{});
    r.cloudEngines.single.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'x'),
    );
    await pumpEventQueue();
    expect(c.state, EngineStatus.failed);
  });
}
