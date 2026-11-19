import 'json_reader.dart';

/// Silero VAD settings.
final class VadConfig with JsonValue {
  /// Creates VAD settings.
  const VadConfig({
    required this.model,
    required this.modelSha256,
    required this.threshold,
    required this.minSpeechMs,
    required this.minSilenceMs,
    required this.padMs,
  });

  factory VadConfig._fromJson(JsonReader r) {
    final VadConfig v = VadConfig(
      model: r.string('model'),
      modelSha256: r.string('model_sha256'),
      threshold: r.number('threshold', min: 0.0001),
      minSpeechMs: r.integer('min_speech_ms', min: 1),
      minSilenceMs: r.integer('min_silence_ms', min: 1),
      padMs: r.integer('pad_ms', min: 0),
    );
    r.done();
    return v;
  }

  /// Model path, relative to `shared/`.
  final String model;

  /// Expected sha256 of the model file.
  final String modelSha256;

  /// Speech probability threshold.
  final double threshold;

  /// Speech shorter than this is ignored (ms).
  final int minSpeechMs;

  /// Silence this long ends an utterance (ms).
  final int minSilenceMs;

  /// Padding kept around speech (ms).
  final int padMs;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'model_sha256': modelSha256,
    'threshold': threshold,
    'min_speech_ms': minSpeechMs,
    'min_silence_ms': minSilenceMs,
    'pad_ms': padMs,
  };
}

/// Contents of `shared/pipeline.yaml`.
final class PipelineConfig with JsonValue {
  /// Creates a config.
  const PipelineConfig({
    required this.version,
    required this.vad,
    required this.reportPercentiles,
    required this.ringBufferS,
    required this.silenceTimeoutMs,
    required this.batteryMinRemainingMinutes,
    required this.batteryMinPercent,
  });

  /// Parses and validates the file's decoded form.
  factory PipelineConfig.fromJson(Object? json) {
    final JsonReader r = JsonReader(json, 'pipeline');
    final JsonReader latency = r.object('latency');
    latency
      ..string('provisional')
      ..string('final');
    final List<int> percentiles = List<int>.unmodifiable(
      latency.list('report_percentiles').cast<int>(),
    );
    latency.done();
    final JsonReader fallback = r.object('fallback');
    final int ring = fallback.integer('ring_buffer_s', min: 1);
    final int silence = fallback.integer('silence_timeout_ms', min: 1);
    fallback.done();
    final JsonReader battery = r.object('battery_warning');
    final int minutes = battery.integer('min_remaining_minutes', min: 1);
    final int percent = battery.integer('min_percent', min: 1);
    battery.done();
    final PipelineConfig c = PipelineConfig(
      version: r.integer('version', min: 1),
      vad: VadConfig._fromJson(r.object('vad')),
      reportPercentiles: percentiles,
      ringBufferS: ring,
      silenceTimeoutMs: silence,
      batteryMinRemainingMinutes: minutes,
      batteryMinPercent: percent,
    );
    r.optString('speaker_heuristic');
    if (r.has('speaker_heuristic')) {
      throw const FormatException(
        'pipeline.speaker_heuristic: not supported yet',
      );
    }
    r.done();
    return c;
  }

  /// File format version.
  final int version;

  /// VAD settings.
  final VadConfig vad;

  /// Percentiles reported for latency.
  final List<int> reportPercentiles;

  /// Seconds of audio kept in RAM for fallback replay.
  final int ringBufferS;

  /// No engine events for this long during speech triggers fallback (ms).
  final int silenceTimeoutMs;

  /// Battery warning when this many minutes remain.
  final int batteryMinRemainingMinutes;

  /// Battery warning at or below this percentage.
  final int batteryMinPercent;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'vad': vad.toJson(),
    'report_percentiles': reportPercentiles,
    'ring_buffer_s': ringBufferS,
    'silence_timeout_ms': silenceTimeoutMs,
    'battery_min_remaining_minutes': batteryMinRemainingMinutes,
    'battery_min_percent': batteryMinPercent,
  };
}
