import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/capture/audio_source.dart';
import 'package:itatranscript/models/audio_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const EventChannel audio = EventChannel('test/audio');
  const MethodChannel control = MethodChannel('test/audio_control');

  Future<void> send(Object? message) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          audio.name,
          const StandardMethodCodec().encodeSuccessEnvelope(message),
          (ByteData? _) {},
        );
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (MethodCall call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(audio.name),
          (MethodCall call) async => null,
        );
  });

  test(
    'a good frame is delivered; a malformed frame becomes a stream error',
    () async {
      final PlatformAudioSource source = PlatformAudioSource(
        audioChannel: audio,
        controlChannel: control,
      );
      final List<AudioFrame> frames = <AudioFrame>[];
      final List<Object> errors = <Object>[];
      source.frames.listen(frames.add, onError: errors.add);
      await source.start();
      await send(<String, Object?>{
        'seq': 0,
        't_ms': 0,
        'pcm': Uint8List(kFrameBytes),
      });
      await send(<String, Object?>{
        'seq': 1,
        't_ms': 20,
        'pcm': Uint8List(100),
      });
      await send(<String, Object?>{
        'seq': -1,
        't_ms': 20,
        'pcm': Uint8List(kFrameBytes),
      });
      await send('not a map');
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(errors, hasLength(3));
      expect(errors.every((Object e) => e is FormatException), isTrue);
      await source.stop();
    },
  );

  test('interruption notices become AudioInterruption events', () async {
    final PlatformAudioSource source = PlatformAudioSource(
      audioChannel: audio,
      controlChannel: control,
    );
    final List<AudioInterruption> seen = <AudioInterruption>[];
    source.interruptions.listen(seen.add);
    await source.start();
    await send(<String, Object?>{
      'kind': 'interruption',
      'paused': true,
      'reason': 'phone call',
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.paused, isTrue);
    expect(seen.single.reason, 'phone call');
    await source.stop();
  });

  test('AudioFrame.checked rejects bad fields', () {
    expect(
      () => AudioFrame.checked(seq: 'x', tMs: 0, pcm: Uint8List(kFrameBytes)),
      throwsFormatException,
    );
    expect(
      () => AudioFrame.checked(seq: 0, tMs: -5, pcm: Uint8List(kFrameBytes)),
      throwsFormatException,
    );
    expect(
      () => AudioFrame.checked(seq: 0, tMs: 0, pcm: null),
      throwsFormatException,
    );
  });
}
