# Contract: Benchmark CLI (`itabench`)

Always run it through `uv` from `bench/`, for example `uv run itabench ...` (Project Constraints). Keys come from `bench/.env` (gitignored, harness-only keys; XIV).

## Inputs (all gitignored)

- `bench/data/clips/<id>.wav` + `<id>.yaml` (TestClip). Clips without consent are rejected, and the clip file is validated (format, sample rate, duration).
- `bench/data/refs/<id>.txt` (hand-corrected text, with lines tagged `he|en`) and `<id>.json` (Reference, produced by `align`).

## Commands

| Command | Does | Output |
|---|---|---|
| `itabench align <clip>` | Builds a Reference draft from the hand-corrected text: words with language tags, non-speech intervals (from the VAD), and turn-change placeholders. Uncertain spots are flagged `needs_check` | `refs/<clip>.json` |
| `itabench run [--engines ...] [--cleanup none,rnnoise,deepfilternet,voiceproc] [--vad on,off] [--clips ...]` | Streams each clip × engine × cleanup × VAD combination at real-time pace. A failed item is logged and counted, and the run continues | `results/<engine>/<cleanup>/<vad>/<clip>.events.jsonl` (overwritten) |
| `itabench score` | Turns current events into EvaluationResults | `results/.../<clip>.json` (overwritten) |
| `itabench report` | Tables by engine × language × situation × cleanup × VAD: WER/CER, provisional/final p50/p90, made-up words, speaker-change recall, $/h, and a provenance appendix | `results/report.md` |
| `itabench check-engine <id>` | **Live** smoke test against the real endpoint: conformance plus 5 s of silence producing no text. Never run by pytest or CI | Exit 0/1 |

## Run rules (XII, XV, Project Constraints)

- At the end, each run logs `processed / succeeded / skipped / failed`, and exits non-zero if any item failed or all were skipped.
- Each result records the clip sha256, engine/model/API version, cleanup, VAD, `shared/` file hashes and the harness version.
- The report shows data only. Engine choice and SC-003 thresholds are Itai's decision in `specs/001-live-captions/decision.md` (XI).
- Hebrew, English and mixed results are always shown separately (FR-016). Each cleanup and VAD variant is shown next to the baseline (FR-017).
- Normalization rules (R-4) are listed at the top of `report.md`.
