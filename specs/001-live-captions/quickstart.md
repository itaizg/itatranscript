# Quickstart: Validate Live Captions End to End

This guide proves each story works, linking to contracts rather than repeating them. Every Python command goes through `uv` (Project Constraints). A deliverable counts as done only after a real run (Quality Gates).

## Prerequisites

- Mac with Xcode, [`uv`](https://docs.astral.sh/uv/), `pre-commit` (run through `uvx`) and pinned Flutter stable. Flutter isn't installed yet.
- iPhone running iOS 26 in developer mode. An Android device or emulator with `adb`, for the Phase 0 Android baseline.
- `bench/.env` with **harness-only** provider keys. The app gets **separate** keys, entered in its settings and stored in the Keychain (XIV).
- Consented clips and references in `bench/data/` ([bench-cli.md](contracts/bench-cli.md)).

## V0 – Gates and contracts (Setup + Foundational)

```bash
uvx pre-commit run --all-files
```

```bash
cd bench && uv sync --locked && uv run pytest
```

**Expected**:
- ruff, ty, dart format and dart analyze are clean.
- pytest passes with no network and no keys, including the shared-fixture contract tests ([engine-stream.md](contracts/engine-stream.md)) and the pipeline-config tests ([pipeline-config.md](contracts/pipeline-config.md)).
- CI on the PR runs the same checks and passes.

## V1 – Benchmark picks engines (Story 2, FR-016/017)

```bash
uv run itabench check-engine google-stt-he
```

```bash
uv run itabench run --cleanup none,rnnoise,deepfilternet,voiceproc --vad on,off
```

```bash
uv run itabench score && uv run itabench report
```

**Expected**:
- `check-engine` passes for each engine you'll use.
- The run ends by logging processed/succeeded/skipped/failed counts. Re-running one combination overwrites its result instead of adding a duplicate.
- `results/report.md` shows Hebrew, English and mixed results separately for every engine (including the Apple and Android baselines) × cleanup × VAD.
- **Then** Itai writes `decision.md` (engines, mic, SC-003 thresholds, Hebrew fallback availability) and copies the thresholds into `spec.md`.

## V2 – Captions in a noisy café (Story 1)

On the iPhone, start a session in a café or with café noise playing.

**Expected**:
- Provisional text in < 1 s and final text in < 2 s; session stats show provisional p90 ≤ 1000 ms and final p90 ≤ 2000 ms, using the same definitions as the benchmark ([session-stats.md](contracts/session-stats.md)).
- Mixed Hebrew/English sentences keep both languages.
- 30 s of clatter produces no text.

## V3 – Meeting controls (Story 3)

Freeze for 20 s while someone talks, then resume.

**Expected**: all 20 s of speech is there. Scrolling back pauses auto-scroll, and "jump to live" works ([caption-screen.md](contracts/caption-screen.md)).

## V4 – Group speaker changes (Story 4)

**Expected**: speaker-change recall is ≥ 80% on the annotated group clips in the report. A live dinner shows dividers at turn changes.

## V5 – Instant start and lock (Story 5, FR-022)

1. From a locked phone, start through the Control Center or Lock Screen control. **Expected**: live captions within 2 taps and 3 s.
2. Lock the phone for 5 min while someone talks, then unlock. **Expected**: all the speech is there, and the view is at the newest line.

## V6 – Offline fallback (FR-024)

Turn on airplane mode for 60 s mid-session, then turn it off.

**Expected**:
- The amber badge appears within 3 s and captions continue.
- They switch back afterwards, with no lost or duplicated lines.
- Stats show both switches.
- For Hebrew, if `decision.md` says there's no on-device Hebrew, the red "paused – no connection" banner shows instead.

## V7 – Privacy, export, stats (FR-018/019/023/025)

1. Download the app container (Xcode → Devices). **Expected**: no audio and no transcript files; only the stats JSONL.
2. Export with test mode off, then on. **Expected**: the file matches [export-format.md](contracts/export-format.md), with stats only in test mode, and the temp file is gone.
3. Check the device logs for the session. **Expected**: no caption text, no keys.

## V8 – Endurance and battery (SC-007, edge case)

Run a 2 h session with at least 45 min locked, starting from a full charge. **Expected**: `battery_end_pct ≥ 40`. If you start low instead, the battery-low banner appears at the `shared/pipeline.yaml` threshold.

## v1 acceptance (SC-010, Quality Gates)

V2–V8 pass on the physical iPhone, with S1/S2/S7 read from real G1/G3 session stats, plus 5 logged real uses. Lessons go to `lessons.md` (XX).
