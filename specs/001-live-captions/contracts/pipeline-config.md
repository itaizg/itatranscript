# Contract: Pipeline Config (`shared/pipeline.yaml`)

This file is the single home for the deterministic rules both sides use (V, XI). Both sides parse it into `PipelineConfig`. Changing a value is a commit that cites its reason: benchmark evidence or a decision in `decision.md`.

```yaml
version: 1
vad:
  model: models/silero_vad.onnx   # pinned; sha256 recorded below
  model_sha256: "<filled at setup>"
  threshold: 0.5
  min_speech_ms: 250
  min_silence_ms: 300
  pad_ms: 300                     # frames passed before and after speech
latency:                          # research R-3, identical on both sides
  provisional: first_partial_arrival - vad_onset
  final: last_final_arrival - vad_offset
  report_percentiles: [50, 90]
fallback:
  ring_buffer_s: 5
  silence_timeout_ms: 2000        # no events during VAD speech, so treat the engine as lost
battery_warning:
  min_remaining_minutes: 20
  min_percent: 10
speaker_heuristic: null           # only set if decision.md says it's needed (research R-8)
```

The starting values above are the Silero defaults, plus the research decisions. The benchmark may tune them, and the reason for any change is recorded.

## Tests

- Both loaders reject unknown keys and missing values.
- The latency fixture `shared/fixtures/latency-basic.*` gives the same p50/p90 in `bench/tests/test_metrics_latency.py` and `app/test/latency_test.dart`.
