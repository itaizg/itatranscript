# Implementation Plan: Live Captions for Hard Listening Situations

**Branch**: `feat/phase-0` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-live-captions/spec.md`

## Summary

v1 is an iPhone app that turns nearby Hebrew/English speech into large, glanceable captions in about 1 s (provisional) and 2 s (final). Speaker-change markers, freeze/scroll-back, lock-screen start, and on-device fallback when offline are included. Audio is never stored.

The work happens in two tracks that share one **engine contract** ([contracts/engine-stream.md](contracts/engine-stream.md)):

1. **Benchmark harness** (Phase 0, Python CLI on the Mac). It streams consented recorded clips at real-time speed through 4–6 candidate engines, plus the OS baselines. It scores WER (Hebrew/English/mixed), time to first word, time to final, hallucinations on silence, speaker-change recall and cost per hour. Output: the chosen primary and fallback engines, the mic decision, and locked SC-003 thresholds.
2. **App** (Phase 1, Flutter with native iOS code). Mic → OS voice processing → VAD → selected engine adapter → caption screen. Session stats stay on the device, export uses the share sheet, and offline fallback is automatic.

Engine choice stays data, not code: both tracks read the same engine profiles ([contracts/engine-profiles.md](contracts/engine-profiles.md)).

## Technical Context

**Language/Version**: Python 3.13 (harness, existing `.venv`); Dart 3 / Flutter stable (app); Swift 6 for iOS native code (audio session, Apple speech, widget).

**Primary Dependencies**:
- Harness: `jiwer` (WER), `numpy`/`soundfile` (audio), `websockets`/vendor SDKs (streaming engines), `silero-vad` and RNNoise/DeepFilterNet (cleanup variants), `faster-whisper` + ivrit.ai checkpoints (local candidate), `typer` (CLI).
- App: `AVAudioEngine` with voice processing (native), Apple `SpeechAnalyzer`/`SFSpeechRecognizer` (native, on-device fallback), `web_socket_channel` (cloud engines), `flutter_secure_storage` (API keys in the Keychain), `share_plus` (export), WidgetKit / Lock Screen controls (native).

**Storage**: No audio stored anywhere. Settings live in local preferences and API keys in the Keychain. Session stats are a local JSON-lines file in the app container (FR-023). Transcripts are written only to a temp file for the share sheet and deleted afterwards (FR-019). The harness keeps clips and references under `bench/data/` (gitignored, consented).

**Testing**: `pytest` (harness: metrics, normalization, contract conformance with a fake engine); `flutter test` (caption state machine, fallback switching, export format); XCTest for native plugins; real-device manual checks per [quickstart.md](quickstart.md).

**Target Platform**: iOS 26 on Itai's iPhone (v1). The harness runs on macOS. Android and macOS app builds are post-v1, but the code is kept portable for them (Flutter, native code behind platform channels).

**Project Type**: mobile app plus a CLI benchmark tool.

**Performance Goals**: provisional text ≤ 1 s p90 (SC-001); final ≤ 2 s p90 (SC-002); fallback switch ≤ 3 s (FR-024); caption view at 60 fps through a 2 h session.

**Constraints**: ≤ 60% battery per 2 h including locked time (SC-007); background audio capture must survive lock (FR-022); audio only to providers that don't retain it (FR-020); cost shown per hour, with an optional cap (FR-014/015).

**Scale/Scope**: one user, one device in v1. Sessions last up to ~3 h, which is about 30k words, so the caption list must be virtualized. The benchmark set is 10–15 clips of 1–5 min each.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

There is no `.specify/memory/constitution.md` in this project. In its place, the gates are the binding constraints from `MISSION.md` and the spec:

| Gate | Source | Pre-design | Post-design |
|---|---|---|---|
| G-1 Engine is swappable by config, without a rebuild | FR-013, MISSION | ✅ planned | ✅ the engine contract and profiles are shared by the harness and the app |
| G-2 Engine is chosen from benchmark data | MISSION, Story 2 | ✅ Phase 0 runs before the app | ✅ the harness report is the selection input ([research.md](research.md) R-2) |
| G-3 No audio persisted | FR-018 | ✅ | ✅ the audio pipeline is in-memory only; the data model has no audio entity in the app |
| G-4 Transcripts only on explicit export, no in-app copy | FR-019 | ✅ | ✅ the export contract writes a temp file and deletes it after sharing |
| G-5 Cloud audio only to non-retaining providers | FR-020 | ✅ | ✅ `retains_audio` / `trains_on_audio` fields in the profile; the app refuses to start an engine that fails |
| G-6 Simple UI (3 controls on the caption screen) | FR-009 | ✅ | ✅ UI contract lists exactly start/stop, freeze, language |
| G-7 Cross-platform codebase, native code only where forced | MISSION | ✅ | ✅ native code is limited to the audio session, Apple speech and the widget, behind platform channels |

No violations, so Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-live-captions/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Entities, fields, states
├── quickstart.md        # End-to-end validation guide
├── contracts/
│   ├── engine-stream.md     # Audio-in / caption-events-out contract (harness + app)
│   ├── engine-profiles.md   # Engine config schema (YAML)
│   ├── bench-cli.md         # Harness commands, inputs, report format
│   ├── session-stats.md     # On-device stats record (FR-023)
│   ├── export-format.md     # Exported transcript text (+ test-mode stats)
│   └── caption-screen.md    # UI contract: controls, states, display rules
├── checklists/requirements.md
└── tasks.md             # Created by /speckit-tasks
```

### Source Code (repository root)

```text
config/
└── engines.yaml            # Engine profiles shared by harness and app (no secrets)

bench/                      # Phase 0 harness (Python)
├── pyproject.toml
├── src/itabench/
│   ├── cli.py              # `itabench run | score | report`
│   ├── contract.py         # Engine stream contract (Python side)
│   ├── engines/            # One adapter per engine + fake engine for tests
│   ├── cleanup/            # none | rnnoise | deepfilternet + silero VAD
│   ├── streaming.py        # Real-time paced audio feeder
│   ├── metrics/            # wer.py (HE/EN normalization), latency.py, hallucination.py, speakers.py
│   └── report.py           # Markdown + CSV report
├── tests/
└── data/                   # Clips + references (gitignored)

app/                        # Phase 1 Flutter app
├── lib/
│   ├── engines/            # Dart side of the engine contract + cloud adapters
│   ├── capture/            # Platform-channel wrapper for native audio
│   ├── session/            # Caption session state machine, fallback controller, stats
│   ├── ui/                 # Caption screen, settings
│   └── export/
├── ios/
│   ├── Runner/             # Native plugins: AudioCapture, AppleSpeechEngine
│   └── CaptionsWidget/     # Lock Screen / Control Center launcher
└── test/
```

**Structure Decision**: two sibling projects (`bench/`, `app/`) plus a shared `config/engines.yaml`. The harness and app are separate languages on purpose. The harness needs Python's ML and audio ecosystem, and the app needs Flutter. They share the contract and the config, not code. **Repo fix needed before scaffolding the app:** `.gitignore` has a bare `lib/` rule (from the Python template) that would ignore `app/lib/`. Change it to `/lib/`.

## Phasing (input for /speckit-tasks)

- **Phase 0 – Benchmark (Story 2, about 1 week)**: harness, adapters, 10–15 clips, report, decision record. Exit: primary and fallback engine per language, mic decision, SC-003 thresholds written into the spec.
- **Phase 1a – Caption core (Story 1)**: Flutter app with native capture, the winning engine, the caption screen, and partial vs. final display.
- **Phase 1b – Story 3** freeze/scroll-back; **Story 4** speaker-change markers; **Story 5** lock-screen control; background capture (FR-022); offline fallback (FR-024); stats, export and test mode (FR-023/019/025); cost display and cap (FR-014/015).
- **Post-v1**: Android build with simple mode (Story 6), macOS build.

## Complexity Tracking

No constitution violations to justify.
