import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/android_speech_adapter.dart';
import 'package:itatranscript/engines/fake_engine.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/session_snapshot.dart';

import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const EventChannel events = EventChannel('test/android_events');
  const MethodChannel control = MethodChannel('test/android');

  setUp(() {
    final TestDefaultBinaryMessenger m =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(control, (MethodCall c) async => null);
    m.setMockMethodCallHandler(
      MethodChannel(events.name),
      (MethodCall c) async => null,
    );
  });

  test('Android native events equal the shared fixtures, and a network error is mapped', () async {
    final AndroidSpeechAdapter a = AndroidSpeechAdapter(
      controlChannel: control,
      eventChannel: events,
    );
    final List<EngineEvent> got = <EngineEvent>[];
    final Future<void> done = a.events.forEach(got.add);
    await a.open(
      parseEngines(readShared('engines.yaml'))['android-ondevice']!,
      LanguageMode.he,
      const <String, String>{},
    );
    final String log = readShared(
      'fixtures/native/android-partial-then-final.events.jsonl',
    );
    for (final String line in const LineSplitter().convert(log)) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope(jsonDecode(line)),
            (ByteData? _) {},
          );
    }
    await done;
    expect(got, parseEventLog(log));
  });

  test('it uses its own channels by default', () {
    final AndroidSpeechAdapter a = AndroidSpeechAdapter();
    expect(a.controlChannel.name, 'itatranscript/android_speech');
    expect(a.eventChannel.name, 'itatranscript/android_speech_events');
  });
}
