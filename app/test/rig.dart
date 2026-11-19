import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/core/clock.dart';
import 'package:itatranscript/engines/engine_adapter.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/gate/speech_gate.dart';
import 'package:itatranscript/models/engine_profile.dart';
import 'package:itatranscript/models/pipeline_config.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/models/settings.dart';
import 'package:itatranscript/session/session_controller.dart';
import 'package:itatranscript/session/settings_store.dart';

import 'fakes.dart';
import 'support.dart';

/// A session wired to fakes: fake audio, a model the test flips between speech and silence,
/// and scripted engines the test drives by hand.
class Rig {
  Rig({
    String engine = 'fake',
    this.extras = const SessionExtras(),
    String? fallback,
  }) {
    profiles = parseEngines(readShared('engines.yaml'));
    config = parsePipeline(
      readShared('pipeline.yaml'),
      readSharedBytes('models/silero_vad.onnx'),
    );
    store = SettingsStore(
      preferences: MemoryKeyValueStore(),
      secrets: MemorySecretStore(),
      defaults: Settings.defaults(
        activeEngineId: engine,
        fallbackEngineId: fallback,
      ),
    );
    registry = AdapterRegistry(<String, AdapterFactory>{
      'fake': (EngineProfile p, Clock c) => _build('fake'),
      'google_streaming': (EngineProfile p, Clock c) =>
          _build('google_streaming'),
      'apple_speech': (EngineProfile p, Clock c) => _build('apple_speech'),
    });
    controller = SessionController(
      audio: audio,
      gateFactory: () => SpeechGate(model, config.vad),
      settings: store,
      profiles: profiles,
      registry: registry,
      clock: clock,
      config: config,
      extras: extras,
    );
    controller.snapshot.addListener(
      () => states.add(controller.snapshot.value.state),
    );
  }

  final SessionExtras extras;
  final FakeClock clock = FakeClock();
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
