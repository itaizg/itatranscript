# Data Model: Live Captions

These are the entities from the [spec](spec.md). Every record that crosses a component boundary is an **immutable validated model** (Principle IX):
- **Python**: Pydantic v2 with `ConfigDict(frozen=True)`, using tuples or frozensets for collections.
- **Dart**: an `@immutable` class with `final` fields, a `const` constructor, value equality, `copyWith`, a `fromJson` that checks every field, and unmodifiable collections.

Where each model lives: **App** = iPhone only, **Bench** = Mac harness only, **Shared** = defined once in `shared/` and mirrored by both.

**Terminology**:
- **active engine**: the engine the user selected.
- **fallback engine**: the on-device engine used when the active one is lost.
- `engine_role` is `active | fallback`.

## Typed seams (Principle II)

| Interface | Implementations | Defined in |
|---|---|---|
| `AudioSource` → stream of `AudioFrame` | native iOS capture (app); WAV file feeder (bench) | `app/lib/capture/`, `bench/src/itabench/streaming.py` |
| `SpeechGate` (VAD + noise suppression) → stream of `GatedFrame` + `SpeechSpan` | Silero ONNX (both sides), cleanup variants (bench) | `app/lib/gate/`, `bench/src/itabench/speech_gate.py` |
| `EngineAdapter` | one per engine + `FakeEngine` | [contracts/engine-stream.md](contracts/engine-stream.md) |
| `CaptionAssembler` (events → segments) | one | `app/lib/session/` |
| `SettingsStore`, `StatsStore` | preferences + Keychain; JSONL file | `app/lib/session/` |

## Shared models (schema in `shared/`)

- **EngineEvent** (`partial` | `final` | `speaker_change` | `health` | `usage` | `error` | `closed`): fields and rules in [contracts/engine-stream.md](contracts/engine-stream.md). The JSON Schema is `shared/engine-events.schema.json`.
- **EngineProfile**: schema in [contracts/engine-profiles.md](contracts/engine-profiles.md). Rules:
  - The privacy gate refuses `retains_audio: true`, and refuses `trains_on_audio: true` unless the opt-out is confirmed.
  - `can_be_fallback` requires `runs_on: device`.
- **PipelineConfig**: VAD model, thresholds, padding, latency definitions, battery-warning threshold, optional speaker heuristic. See [contracts/pipeline-config.md](contracts/pipeline-config.md).
- **AudioFrame**: `seq: int`, `t_ms: int`, `pcm: bytes` (640 bytes = 20 ms at 16 kHz mono s16le).
- **SpeechSpan**: `onset_ms`, `offset_ms | null`. Used for latency (research R-3).

## App models

### CaptionSession (owned by the session controller; the UI receives immutable snapshots)

| Field | Type | Rules |
|---|---|---|
| id | UUID | |
| started_at / ended_at | timestamp | `ended_at` is null while running |
| language_mode | `he` \| `en` \| `auto` | A change applies at the next VAD pause (R-14) |
| active_engine_id | → EngineProfile | Must pass the privacy gate |
| fallback_engine_id | → EngineProfile? | Must be `runs_on: device` |
| segments | unmodifiable list of CaptionSegment | Ordered by `start_ms` |
| state | SessionState | See below |

Text is dropped when the session ends unless the user exported it (FR-019). There is no audio field; the 5 s fallback ring buffer is RAM only and isn't part of the model (FR-018).

**SessionState transitions**:

```text
idle ──start──▶ starting ──first gated frame──▶ live
live ──engine lost──▶ fallback ──healthy + VAD pause──▶ live
live|fallback ──mic interrupted──▶ paused_mic ──mic back──▶ live
live|fallback ──no fallback possible──▶ paused_offline ──connection back──▶ live
any ──stop / OS kill / error / battery──▶ ended
```

Freeze and scroll-back are **view state** (`following | frozen | scrolledBack`), not session state. Capture continues while frozen.

### CaptionSegment

| Field | Type | Rules |
|---|---|---|
| id | string | Equals the engine's `segment_id`, namespaced by adapter instance |
| status | `provisional` \| `final` | One way only. A final is never changed |
| text, lang | string; `he\|en\|mixed\|unknown` | `unknown` is shown as `[unrecognized]` |
| start_ms / end_ms | int | Relative to the session start |
| speaker_change_before | bool | FR-006 |
| engine_role | `active` \| `fallback` | Drives the badge |

### Settings (one immutable model, holding the only defaults; VI, IX)

| Field | Default |
|---|---|
| active_engine_id | From `decision.md` |
| fallback_engine_id | From `decision.md` (null if no on-device engine for the language) |
| language_mode | `auto` |
| display_mode | `standard` (`simple` is post-v1) |
| test_mode | `false` |
| monthly_cap_usd | `null` (no cap) |
| text_scale | Large (SC-006) |

API keys aren't part of the model; they're read from the Keychain by `SettingsStore` when an adapter opens.

### SessionStats

Schema in [contracts/session-stats.md](contracts/session-stats.md). It has no text and no audio, and the user can delete it.

## Bench models

- **TestClip**: `id`, `situation` (`cafe`\|`group`\|`meeting`\|`lecture`), `lang` (`he`\|`en`\|`mixed`), `audio_path`, `sha256`, `duration_s`, `consent: true` + `consent_date` (required; a clip without them is rejected), `speakers`, `mic` (`phone`\|`external`\|`table`).
- **Reference**: `words` (`text`, `lang`); `non_speech` intervals (≥ 1 s, for counting made-up words); `turn_changes_ms` (group clips).
- **EvaluationResult**: one per clip × engine × cleanup × VAD on/off, stored at `bench/results/<engine>/<cleanup>/<vad>/<clip>.json` (overwritten on re-run; XV). Fields:
  - `wer`, `cer`, `wer_by_lang`
  - `ttp_p50/p90_ms`, `ttf_p50/p90_ms`
  - `made_up_words`, `speaker_change_recall`, `cost_usd_per_hour`
  - provenance: `clip_sha256`, `engine_version`, `shared_hashes`, `harness_version`, `ran_at`
  - `status` (`ok`\|`failed`), `error`
