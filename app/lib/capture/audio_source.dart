import 'dart:async';

import 'package:flutter/services.dart';

import '../models/audio_frame.dart';

/// Where audio frames come from: the native microphone, or a file in tests.
abstract interface class AudioSource {
  /// 16 kHz mono 20 ms frames until [stop] is called.
  Stream<AudioFrame> get frames;

  /// Interruptions (calls, other apps) as `paused_mic` / `resume` notices.
  Stream<AudioInterruption> get interruptions;

  /// Starts capturing.
  Future<void> start();

  /// Stops capturing.
  Future<void> stop();
}

/// A change in microphone availability (FR-022).
class AudioInterruption {
  /// Creates the notice; [reason] is shown to the user.
  const AudioInterruption({required this.paused, required this.reason});

  /// True when capture stopped, false when it can resume.
  final bool paused;

  /// Why, e.g. `phone call`.
  final String reason;
}

/// Reads frames from the native `AudioCapturePlugin` over an [EventChannel].
class PlatformAudioSource implements AudioSource {
  /// Creates a source on the given channels (overridable for tests).
  PlatformAudioSource({
    this.audioChannel = const EventChannel('itatranscript/audio'),
    this.controlChannel = const MethodChannel('itatranscript/audio_control'),
  });

  /// Channel carrying frames and interruption notices.
  final EventChannel audioChannel;

  /// Channel for start/stop commands.
  final MethodChannel controlChannel;
  final StreamController<AudioFrame> _frames =
      StreamController<AudioFrame>.broadcast();
  final StreamController<AudioInterruption> _interruptions =
      StreamController<AudioInterruption>.broadcast();
  StreamSubscription<Object?>? _sub;

  @override
  Stream<AudioFrame> get frames => _frames.stream;

  @override
  Stream<AudioInterruption> get interruptions => _interruptions.stream;

  @override
  Future<void> start() async {
    _sub = audioChannel.receiveBroadcastStream().listen(
      _onMessage,
      onError: _frames.addError,
    );
    await controlChannel.invokeMethod<void>('start');
  }

  void _onMessage(Object? message) {
    try {
      if (message is Map<Object?, Object?> &&
          message['kind'] == 'interruption') {
        _interruptions.add(
          AudioInterruption(
            paused: message['paused'] == true,
            reason: '${message['reason'] ?? 'unknown'}',
          ),
        );
        return;
      }
      if (message is! Map<Object?, Object?>) {
        throw FormatException(
          'audio message: expected a map, got ${message.runtimeType}',
        );
      }
      final Object? pcm = message['pcm'];
      _frames.add(
        AudioFrame.checked(
          seq: message['seq'],
          tMs: message['t_ms'],
          pcm: pcm is Uint8List ? pcm : null,
        ),
      );
    } on FormatException catch (error) {
      _frames.addError(error);
    }
  }

  @override
  Future<void> stop() async {
    await controlChannel.invokeMethod<void>('stop');
    await _sub?.cancel();
    _sub = null;
  }
}
