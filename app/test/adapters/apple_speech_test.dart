import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/apple_speech_adapter.dart';
import 'package:itatranscript/engines/fake_engine.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/session_snapshot.dart';

import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const EventChannel events = EventChannel('test/apple_events');
  const MethodChannel control = MethodChannel('test/apple');
  final List<MethodCall> calls = <MethodCall>[];

  Future<void> send(Object? message) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(message),
          (ByteData? _) {},
        );
  }

  setUp(() {
    calls.clear();
    final TestDefaultBinaryMessenger m =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(control, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    m.setMockMethodCallHandler(
      MethodChannel(events.name),
      (MethodCall c) async => null,
    );
  });

  AppleSpeechAdapter adapter() =>
      AppleSpeechAdapter(controlChannel: control, eventChannel: events);
  final profile = parseEngines(readShared('engines.yaml'))['apple-ondevice']!;

  test(
    'native events equal the expected JSON in shared/fixtures/native',
    () async {
      final AppleSpeechAdapter a = adapter();
      final List<EngineEvent> got = <EngineEvent>[];
      final Future<void> done = a.events.forEach(got.add);
      await a.open(profile, LanguageMode.en, const <String, String>{});
      expect(calls.single.method, 'open');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['locale'],
        'en-US',
      );
      final String log = readShared(
        'fixtures/native/apple-partial-then-final.events.jsonl',
      );
      for (final String line in const LineSplitter().convert(log)) {
        await send(jsonDecode(line));
      }
      await done;
      expect(got, parseEventLog(log));
      expect(got.whereType<FinalEvent>(), hasLength(1));
    },
  );

  test('he-IL unavailable arrives as error: unsupported_language', () async {
    final AppleSpeechAdapter a = adapter();
    final List<EngineEvent> got = <EngineEvent>[];
    final Future<void> done = a.events.forEach(got.add);
    await a.open(profile, LanguageMode.he, const <String, String>{});
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['locale'],
      'he-IL',
    );
    await send(<String, Object?>{
      'type': 'error',
      't_ms': 1,
      'code': 'unsupported_language',
      'message': 'he-IL is not available on device',
      'retryable': false,
    });
    await send(<String, Object?>{'type': 'closed', 't_ms': 2});
    await done;
    expect((got.first as ErrorEvent).code, 'unsupported_language');
  });

  test(
    'a malformed message becomes error: invalid_message, not a crash',
    () async {
      final AppleSpeechAdapter a = adapter();
      final List<EngineEvent> got = <EngineEvent>[];
      final Future<void> done = a.events.forEach(got.add);
      await a.open(profile, LanguageMode.auto, const <String, String>{});
      await send(<String, Object?>{'type': 'partial', 't_ms': 1});
      await send('garbage');
      await send(<String, Object?>{'type': 'closed', 't_ms': 2});
      await done;
      expect(
        got.whereType<ErrorEvent>().map((ErrorEvent e) => e.code),
        <String>['invalid_message', 'invalid_message'],
      );
    },
  );

  test(
    'audio and control calls reach the native side; cancel ends with closed',
    () async {
      final AppleSpeechAdapter a = adapter();
      final List<EngineEvent> got = <EngineEvent>[];
      final Future<void> done = a.events.forEach(got.add);
      await a.open(profile, LanguageMode.auto, const <String, String>{});
      await a.pushAudio(
        AudioFrame(seq: 0, tMs: 0, pcm: Uint8List(kFrameBytes)),
      );
      await a.finish();
      await a.cancel();
      await done;
      expect(calls.map((MethodCall c) => c.method), <String>[
        'open',
        'push',
        'finish',
        'cancel',
      ]);
      expect(got.last, isA<ClosedEvent>());
    },
  );
}
