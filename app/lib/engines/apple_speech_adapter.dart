import 'dart:async';

import 'package:flutter/services.dart';

import '../models/audio_frame.dart';
import '../models/engine_event.dart';
import '../models/engine_profile.dart';
import '../models/session_snapshot.dart';
import 'engine_adapter.dart';

/// Apple on-device recognition through the native `AppleSpeechPlugin` (profile `apple-ondevice`).
///
/// Channel messages are validated into [EngineEvent]s; a malformed message becomes an
/// `error: invalid_message` event, never a crash (VIII, XIII).
class AppleSpeechAdapter implements EngineAdapter {
  /// Creates an adapter on the given channels (overridable for tests).
  AppleSpeechAdapter({
    this.controlChannel = const MethodChannel('itatranscript/apple_speech'),
    this.eventChannel = const EventChannel('itatranscript/apple_speech_events'),
  });

  /// Commands to the native plugin.
  final MethodChannel controlChannel;

  /// Schema events from the native plugin.
  final EventChannel eventChannel;

  final StreamController<EngineEvent> _out = StreamController<EngineEvent>();
  StreamSubscription<Object?>? _sub;
  bool _closed = false;

  @override
  Stream<EngineEvent> get events => _out.stream;

  /// `he-IL`, `en-US`; an on-device engine cannot mix, so automatic mode uses English.
  static String localeFor(LanguageMode mode) =>
      mode == LanguageMode.he ? 'he-IL' : 'en-US';

  @override
  Future<void> open(
    EngineProfile profile,
    LanguageMode mode,
    Map<String, String> secrets,
  ) async {
    _sub = eventChannel.receiveBroadcastStream().listen(
      _onMessage,
      onError: _onError,
    );
    await controlChannel.invokeMethod<void>('open', <String, Object?>{
      'locale': localeFor(mode),
    });
  }

  void _onMessage(Object? message) {
    if (_closed) {
      return;
    }
    EngineEvent event;
    try {
      event = EngineEvent.fromJson(message);
    } on FormatException catch (e) {
      event = ErrorEvent(
        tMs: 0,
        code: 'invalid_message',
        message: e.message,
        retryable: false,
      );
    }
    _out.add(event);
    if (event is ClosedEvent) {
      unawaited(_close());
    }
  }

  void _onError(Object error) {
    if (!_closed) {
      _out.add(
        ErrorEvent(
          tMs: 0,
          code: 'internal',
          message: '$error',
          retryable: false,
        ),
      );
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _sub?.cancel();
    await _out.close();
  }

  @override
  Future<void> pushAudio(AudioFrame frame) => controlChannel.invokeMethod<void>(
    'push',
    <String, Object?>{'pcm': frame.pcm},
  );

  @override
  Future<void> finish() => controlChannel.invokeMethod<void>('finish');

  @override
  Future<void> cancel() async {
    if (!_closed) {
      try {
        await controlChannel.invokeMethod<void>('cancel');
      } on PlatformException {
        // The native side may already be gone; closing the stream is what matters.
      }
      _out.add(const ClosedEvent(tMs: 0));
      await _close();
    }
  }
}
