import 'dart:async';

import 'package:flutter/services.dart';

/// Talks to the iOS side about how the app was opened (`StartCaptionsIntent`, FR-011).
class LaunchChannel {
  /// Creates the channel wrapper; [channel] is overridable for tests.
  LaunchChannel({this.channel = const MethodChannel('itatranscript/launch')});

  /// The underlying platform channel.
  final MethodChannel channel;

  /// Launch arguments from a cold start, e.g. `{start: true}`; empty when there is no platform side.
  Future<Map<String, String>> arguments() async {
    try {
      final Map<Object?, Object?>? raw = await channel
          .invokeMapMethod<Object?, Object?>('arguments');
      return <String, String>{
        for (final MapEntry<Object?, Object?> e
            in (raw ?? const <Object?, Object?>{}).entries)
          '${e.key}': '${e.value}',
      };
    } on MissingPluginException {
      return const <String, String>{};
    }
  }

  /// Calls [onStart] when the app is already running and a start is requested.
  void listenForStart(void Function() onStart) {
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'startRequested') {
        onStart();
      }
      return null;
    });
  }
}
