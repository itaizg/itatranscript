# Contract: Session Stats (FR-023, Principle XII)

Stats are stored on the device only, one JSON object per line, one line per session. Stats MUST NOT contain caption text, audio or secrets. Latency fields use the shared definitions in `shared/pipeline.yaml` (research R-3), so they can be compared directly with benchmark results.

```json
{
  "v": 1,
  "session_id": "uuid",
  "started_at": "2026-12-01T19:02:11Z",
  "duration_s": 5420,
  "language_mode": "auto",
  "active_engine_id": "google-stt-he",
  "fallback_engine_id": "apple-ondevice",
  "pipeline_sha256": "…",
  "provisional_ms": { "p50": 610, "p90": 940, "n": 812 },
  "final_ms": { "p50": 1200, "p90": 1850, "n": 640 },
  "battery_start_pct": 92,
  "battery_end_pct": 61,
  "battery_warnings": 0,
  "locked_s": 3100,
  "fallback_switches": [{ "at_s": 1203, "to": "fallback", "switch_ms": 1800 }, { "at_s": 1390, "to": "active" }],
  "interruptions": [{ "at_s": 2400, "kind": "mic_in_use", "dur_s": 45 }],
  "errors": [{ "at_s": 10, "code": "network" }],
  "billed_audio_s": 4900,
  "est_cost_usd": 1.96,
  "end_reason": "user_stop"
}
```

- `end_reason` is one of `user_stop | os_killed | error | battery`.
- Entries are kept until the user deletes them, either one entry or all.
- Test (`app/test/session_stats_test.dart`): after a fixture session with known caption text, no string from that text appears anywhere in the written line.
