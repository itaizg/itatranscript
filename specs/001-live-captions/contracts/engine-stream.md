# Contract: Engine Stream

This is the MISSION engine interface: `audio in → {partial|final text, timestamps, speaker-change}`. Both the harness and the app implement it.

**Single source**: `shared/engine-events.schema.json` (JSON Schema, draft 2020-12). The Python Pydantic models and the Dart value classes are hand-written mirrors. Both test suites validate the shared fixtures (`shared/fixtures/*.events.jsonl`) against the schema *and* through their own models, so the two sides can't drift apart (V, Project Constraints).

## Interface

```text
open(profile, language_mode, secrets) → ready | error event
push_audio(frame: AudioFrame)    # gated 16 kHz mono s16le, 20 ms frames, real-time paced by the caller
finish()                         # flush → remaining finals → closed
cancel()                         # stop now → closed, no further events
events() → async stream of EngineEvent
```

- Python: `typing.Protocol`. Dart: `abstract interface class`.
- Adapters keep no state between sessions and write nothing to disk (XV, FR-018).
- Every vendor message is validated at the adapter boundary and turned into a model. Invalid vendor messages produce an `error` event, not a crash (VIII, XIII).
- A language change is `finish()` + a new `open()` at the next VAD pause (research R-14). There is no extra operation for it.

## Events

| `type` | Fields | Rules |
|---|---|---|
| `partial` | `segment_id, text, lang?, start_ms, end_ms?` | Replaces the earlier partial with the same id |
| `final` | `segment_id, text, lang, start_ms, end_ms, words?[]` | Exactly one per `segment_id`; nothing follows for that id |
| `speaker_change` | `at_ms, speaker_hint?` | Comes before the first event of the new speaker's segment |
| `health` | `state: ok\|degraded\|lost, reason` | `lost` triggers fallback (R-7) |
| `usage` | `audio_seconds_billed` | Feeds cost |
| `error` | `code: auth\|quota\|network\|unsupported_language\|invalid_message\|internal, message, retryable` | |
| `closed` | — | Always the last event |

All events carry `t_ms` (the time the adapter emitted it, from the injected clock). All `*_ms` values are relative to the first frame pushed.

## Contract tests (no network, fake clock; IV)

1. Every fixture event log validates against the schema, in both Python and Dart.
2. The fixture `partial-then-final` produces one final segment with no duplicate, on both sides.
3. `cancel()` mid-stream: no events after `closed`.
4. Each real adapter: recorded vendor messages (`shared/fixtures/vendor/<engine_id>/`, kept once and used by both the harness and the app tests) are mapped to events that match the schema.

Live checks against real endpoints (for example, a 5 s silence producing no text) run **only** through `itabench check-engine`, never under pytest or CI.
