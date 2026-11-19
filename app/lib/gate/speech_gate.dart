import 'dart:collection';
import 'dart:typed_data';

import '../models/audio_frame.dart';
import '../models/pipeline_config.dart';

/// Samples per Silero step at 16 kHz (32 ms).
const int kVadChunk = 512;

/// Speech probability for one 512-sample chunk of 16 kHz audio in [-1, 1].
abstract interface class VadModel {
  /// Returns the probability that [chunk] holds speech; the model keeps its own state.
  double probability(Float32List chunk);
}

/// Streaming VAD gate (same state machine as the harness): drops silence, keeps padded speech,
/// and records utterance spans for the shared latency definition.
class SpeechGate {
  /// Creates a gate over [model] with the thresholds in [config].
  SpeechGate(this._model, VadConfig config)
    : _cfg = config,
      _pre = Queue<AudioFrame>(),
      _preMax = config.padMs ~/ kFrameMs < 1 ? 1 : config.padMs ~/ kFrameMs;

  final VadModel _model;
  final VadConfig _cfg;
  final Queue<AudioFrame> _pre;
  final int _preMax;

  final List<SpeechSpan> _spans = <SpeechSpan>[];
  Float32List _samples = Float32List(0);
  int _probsEndMs = 0;
  int _speechRunMs = 0;
  int _silenceRunMs = 0;
  int _runStartMs = 0;
  bool _inSpeech = false;
  int _onsetMs = 0;
  int _lastSpeechEndMs = 0;
  int _tailUntilMs = -1;

  /// Utterances found so far.
  List<SpeechSpan> get spans => List<SpeechSpan>.unmodifiable(_spans);

  /// Whether speech is currently open.
  bool get inSpeech => _inSpeech;

  void _step(double prob) {
    const int chunkMs = kVadChunk * 1000 ~/ 16000;
    final int start = _probsEndMs;
    final int end = start + chunkMs;
    _probsEndMs = end;
    if (prob >= _cfg.threshold) {
      if (_speechRunMs == 0) {
        _runStartMs = start;
      }
      _speechRunMs += chunkMs;
      _silenceRunMs = 0;
      if (!_inSpeech && _speechRunMs >= _cfg.minSpeechMs) {
        _inSpeech = true;
        _onsetMs = _runStartMs;
        _tailUntilMs = -1;
      }
      if (_inSpeech) {
        _lastSpeechEndMs = end;
      }
    } else {
      _speechRunMs = 0;
      _silenceRunMs += chunkMs;
      if (_inSpeech && _silenceRunMs >= _cfg.minSilenceMs) {
        _closeSpan();
      }
    }
  }

  void _closeSpan() {
    _inSpeech = false;
    _spans.add(SpeechSpan(onsetMs: _onsetMs, offsetMs: _lastSpeechEndMs));
    _tailUntilMs = _lastSpeechEndMs + _cfg.padMs;
  }

  /// Feeds one frame and returns the frames to pass on to the engine.
  List<AudioFrame> push(AudioFrame frame) {
    final ByteData bytes = ByteData.sublistView(frame.pcm);
    final int count = frame.pcm.length ~/ 2;
    final Float32List merged = Float32List(_samples.length + count)
      ..setAll(0, _samples);
    for (int i = 0; i < count; i++) {
      merged[_samples.length + i] =
          bytes.getInt16(i * 2, Endian.little) / 32768.0;
    }
    _samples = merged;
    final bool wasInSpeech = _inSpeech;
    int offset = 0;
    while (_samples.length - offset >= kVadChunk) {
      _step(
        _model.probability(
          Float32List.sublistView(_samples, offset, offset + kVadChunk),
        ),
      );
      offset += kVadChunk;
    }
    _samples = Float32List.fromList(_samples.sublist(offset));
    if (_inSpeech) {
      final List<AudioFrame> out = <AudioFrame>[];
      if (!wasInSpeech) {
        out.addAll(_pre);
        _pre.clear();
      }
      return out..add(frame);
    }
    if (frame.tMs < _tailUntilMs) {
      return <AudioFrame>[frame];
    }
    _pre.addLast(frame);
    while (_pre.length > _preMax) {
      _pre.removeFirst();
    }
    return const <AudioFrame>[];
  }

  /// Closes a span left open at the end of the stream.
  void finish() {
    if (_inSpeech) {
      _closeSpan();
    }
  }
}
