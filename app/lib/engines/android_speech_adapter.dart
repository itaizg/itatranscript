import 'package:flutter/services.dart';

import 'apple_speech_adapter.dart';

/// Android on-device recognition through the native `AndroidSpeechPlugin` (fallback engine on
/// Android, FR-024). It speaks the same schema events as the Apple adapter, on its own channels.
class AndroidSpeechAdapter extends AppleSpeechAdapter {
  /// Creates an adapter on the Android channels (overridable for tests).
  AndroidSpeechAdapter({
    super.controlChannel = const MethodChannel('itatranscript/android_speech'),
    super.eventChannel = const EventChannel(
      'itatranscript/android_speech_events',
    ),
  });
}
