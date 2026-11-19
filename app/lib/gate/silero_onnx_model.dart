import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'speech_gate.dart';

/// Silero VAD v5 through `onnxruntime`: the same model file as the harness.
class SileroOnnxModel implements VadModel {
  /// Loads the model from [modelBytes].
  SileroOnnxModel(Uint8List modelBytes) {
    OrtEnv.instance.init();
    final OrtSessionOptions options = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(1);
    _session = OrtSession.fromBuffer(modelBytes, options);
  }

  static const int _context = 64;
  late final OrtSession _session;
  Float32List _state = Float32List(2 * 1 * 128);
  Float32List _ctx = Float32List(_context);

  @override
  double probability(Float32List chunk) {
    final Float32List input = Float32List(_context + chunk.length)
      ..setAll(0, _ctx)
      ..setAll(_context, chunk);
    final OrtValueTensor inputTensor = OrtValueTensor.createTensorWithDataList(
      <List<double>>[input],
    );
    final OrtValueTensor stateTensor = OrtValueTensor.createTensorWithDataList(
      _state,
      <int>[2, 1, 128],
    );
    final OrtValueTensor srTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(<int>[16000]),
      <int>[],
    );
    final OrtRunOptions runOptions = OrtRunOptions();
    final List<OrtValue?> outputs = _session.run(runOptions, <String, OrtValue>{
      'input': inputTensor,
      'state': stateTensor,
      'sr': srTensor,
    });
    try {
      final Object? out = outputs[0]?.value;
      final Object? next = outputs[1]?.value;
      _state = Float32List.fromList(_flatten(next));
      _ctx = Float32List.fromList(input.sublist(input.length - _context));
      return _flatten(out).first;
    } finally {
      inputTensor.release();
      stateTensor.release();
      srTensor.release();
      runOptions.release();
      for (final OrtValue? o in outputs) {
        o?.release();
      }
    }
  }

  static List<double> _flatten(Object? value) {
    if (value is num) {
      return <double>[value.toDouble()];
    }
    if (value is List<Object?>) {
      return value.expand<double>((Object? v) => _flatten(v)).toList();
    }
    throw FormatException('unexpected ONNX output ${value.runtimeType}');
  }

  /// Frees the native session.
  void release() => _session.release();
}
