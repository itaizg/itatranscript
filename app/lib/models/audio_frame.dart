import 'dart:typed_data';

/// Bytes in one 20 ms frame of 16 kHz mono s16le audio.
const int kFrameBytes = 640;

/// Milliseconds of audio in one frame.
const int kFrameMs = 20;

/// One 20 ms frame of 16 kHz mono s16le audio.
class AudioFrame {
  /// Creates a frame; use [AudioFrame.checked] for data from outside the app.
  const AudioFrame({required this.seq, required this.tMs, required this.pcm});

  /// Validates a message from the platform channel.
  factory AudioFrame.checked({
    required Object? seq,
    required Object? tMs,
    required Object? pcm,
  }) {
    if (seq is! int || seq < 0) {
      throw const FormatException(
        'AudioFrame.seq: expected a non-negative integer',
      );
    }
    if (tMs is! int || tMs < 0) {
      throw const FormatException(
        'AudioFrame.tMs: expected a non-negative integer',
      );
    }
    if (pcm is! Uint8List || pcm.length != kFrameBytes) {
      throw FormatException(
        'AudioFrame.pcm: expected $kFrameBytes bytes, got ${pcm.runtimeType}',
      );
    }
    return AudioFrame(seq: seq, tMs: tMs, pcm: pcm);
  }

  /// Frame counter, starting at 0.
  final int seq;

  /// Position of the frame in the audio timeline (ms).
  final int tMs;

  /// 640 bytes of s16le samples.
  final Uint8List pcm;
}

/// A speech interval found by the shared VAD.
class SpeechSpan {
  /// Creates a span; [offsetMs] is null while the utterance is still open.
  const SpeechSpan({required this.onsetMs, this.offsetMs});

  /// Start of speech (ms).
  final int onsetMs;

  /// End of speech (ms), or null while open.
  final int? offsetMs;

  @override
  bool operator ==(Object other) =>
      other is SpeechSpan &&
      other.onsetMs == onsetMs &&
      other.offsetMs == offsetMs;

  @override
  int get hashCode => Object.hash(onsetMs, offsetMs);

  @override
  String toString() => 'SpeechSpan($onsetMs, $offsetMs)';
}
