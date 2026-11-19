import 'dart:async';
import 'dart:typed_data';

import 'package:itatranscript/capture/audio_source.dart';
import 'package:itatranscript/engines/engine_adapter.dart';
import 'package:itatranscript/gate/speech_gate.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/engine_profile.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/session/settings_store.dart';

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class FakeAudioSource implements AudioSource {
  final StreamController<AudioFrame> _frames =
      StreamController<AudioFrame>.broadcast();
  final StreamController<AudioInterruption> _interruptions =
      StreamController<AudioInterruption>.broadcast();
  bool started = false;
  int _seq = 0;

  @override
  Stream<AudioFrame> get frames => _frames.stream;

  @override
  Stream<AudioInterruption> get interruptions => _interruptions.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;

  /// Emits [count] frames of 20 ms each, back to back.
  void emitFrames(int count) {
    for (int i = 0; i < count; i++) {
      _frames.add(
        AudioFrame(
          seq: _seq,
          tMs: _seq * kFrameMs,
          pcm: Uint8List(kFrameBytes),
        ),
      );
      _seq++;
    }
  }

  void interrupt({required bool paused, String reason = 'phone call'}) =>
      _interruptions.add(AudioInterruption(paused: paused, reason: reason));

  void emitError(Object error) => _frames.addError(error);
}

/// A gate model whose answer the test controls.
class SwitchableModel implements VadModel {
  double level = 0.9;

  @override
  double probability(Float32List chunk) => level;
}

/// An engine the test drives by hand.
class ScriptedEngine implements EngineAdapter {
  final StreamController<EngineEvent> out = StreamController<EngineEvent>();
  final List<AudioFrame> received = <AudioFrame>[];
  LanguageMode? openedWith;
  bool finished = false;
  bool cancelled = false;

  @override
  Stream<EngineEvent> get events => out.stream;

  @override
  Future<void> open(
    EngineProfile profile,
    LanguageMode mode,
    Map<String, String> secrets,
  ) async => openedWith = mode;

  @override
  Future<void> pushAudio(AudioFrame frame) async => received.add(frame);

  @override
  Future<void> finish() async {
    finished = true;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  void emit(EngineEvent event) => out.add(event);
}
