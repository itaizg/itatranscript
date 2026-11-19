import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/session/launch_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/launch');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('arguments from the platform become a string map', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (MethodCall c) async => c.method == 'arguments'
              ? <String, Object?>{'start': 'true'}
              : null,
        );
    expect(await LaunchChannel(channel: channel).arguments(), <String, String>{
      'start': 'true',
    });
  });

  test('with no platform side the arguments are empty', () async {
    expect(
      await LaunchChannel(channel: const MethodChannel('nobody/listens'))
          .arguments(),
      isEmpty,
    );
  });

  test('a startRequested call from the platform runs the callback', () async {
    int starts = 0;
    LaunchChannel(channel: channel).listenForStart(() => starts++);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('startRequested'),
          ),
          (ByteData? _) {},
        );
    expect(starts, 1);
  });
}
