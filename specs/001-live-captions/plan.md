# Implementation Plan: Live Captions for Hard Listening Situations

**Branch**: `feat/phase-0` | **Date**: 2026-11-18 (rev 2: checked against the constitution) | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-live-captions/spec.md`

## Summary

v1 is an iPhone app that turns nearby Hebrew/English speech into large captions in about 1 s (provisional) and 2 s (final). It includes speaker-change markers, freeze/scroll-back, lock-screen start, and an on-device fallback when offline. Audio is never stored.

There are two tracks, joined by **one language-neutral shared definition** in `shared/`: the event JSON Schema, the engine profiles, the pipeline settings (VAD, latency definitions), and fixture event logs.

1. **Benchmark harness** (Phase 0, Python 3.13 CLI on the Mac, managed with `uv`). It streams consented clips at real-time speed through the cloud candidates, the Whisper/ivrit.ai setup, and the Apple and Android on-device baselines. Each run is done with and without VAD and noise suppression. It reports WER, time to first word, time to final, made-up words on silence, speaker-change recall and $/h. Output: an engine per language, a mic decision, and SC-003 thresholds, which Itai chooses and records.
2. **App** (Phase 1, Flutter with thin native Swift plugins). Mic → OS voice processing → Silero VAD → engine adapter → caption screen. On-device session stats, export via the share sheet, and automatic on-device fallback.

## Technical Context

**Language/Version**: Python 3.13 via `uv` (`uv.lock` committed); Dart 3 / Flutter stable, with the SDK version pinned and `pubspec.lock` committed; Swift 6 for the native iOS plugins and Mac helper tools; Kotlin only for the Phase 0 Android baseline helper.

**Primary Dependencies**:
- Harness: `pydantic` v2 (frozen models), `jiwer`, `numpy`, `soundfile`, `websockets`/vendor SDKs, `silero-vad` (ONNX), `pyrnnoise`, `deepfilternet`, `faster-whisper` (ivrit.ai checkpoint, used as-is), `typer`, `jsonschema` (tests only). Dev tools: `ruff`, `ty`, `pytest`, `pre-commit`.
- App: `web_socket_channel`, `flutter_secure_storage`, `share_plus`, `battery_plus`, `connectivity_plus`, `path_provider`, `onnxruntime` (Silero VAD, the same model file as the harness), `json_schema` (dev, for contract tests), `logging`.
- Native: `AVAudioEngine` voice processing, `SpeechAnalyzer`/`SFSpeechRecognizer`, WidgetKit `ControlWidget` and App Intents.

**Storage**:
- No audio stored anywhere.
- Settings: one immutable model persisted to local preferences. API keys are in the Keychain.
- Session stats: local JSONL (FR-023).
- Export: temp file, deleted after sharing.
- Harness: clips and references in `bench/data/` and results in `bench/results/` (both gitignored), keyed by clip × engine × cleanup, so a re-run overwrites (XV).

**Testing**: `uv run pytest` (harness) and `flutter test` (app), plus native unit tests for the logic inside native code: `swift test` (Apple helper), `xcodebuild test` (iOS `RunnerTests`) and `./gradlew test` (Android helper). Native plugins keep OS calls in thin wrappers around pure, tested functions (VI). Unit tests run with no network, no mic, no model weights and no keys. They use fixture event logs from `shared/fixtures/`, fixture audio, and an injected fake clock (IV). Every mission requirement maps to a test (see Test Map). Live engine checks only run through `itabench check-engine` / `itabench run`, never under pytest or CI.

**Quality gates**:
- Pre-commit: ruff check/format, ty, dart format, dart analyze (strict-casts, strict-inference, strict-raw-types).
- GitHub Actions CI: pre-commit on all files, `uv run pytest`, `flutter test`. Least-privilege permissions, pinned actions, no secrets.

**Target Platform**: iOS 26 on Itai's iPhone (v1). The harness runs on macOS. The Android device or emulator is used only as a Phase 0 baseline. Android/macOS app builds are post-v1.

**Project Type**: mobile app plus a CLI benchmark tool.

**Performance Goals**: provisional text ≤ 1 s p90 (SC-001); final ≤ 2 s p90 (SC-002), both under the shared latency definition; fallback switch ≤ 3 s (FR-024); 60 fps caption list through a 2 h session.

**Constraints**: ≤ 60% battery per 2 h including locked time (SC-007); capture survives lock (FR-022); audio only to providers whose terms (recorded) don't retain it (FR-020); the app only requests the mic and background audio (XIV); separate provider keys for the harness and the app (XIV); no text, audio or secrets in logs (XII, XIII).

**Scale/Scope**: one user, one device. Sessions last up to ~3 h (~30k words, virtualized list). 10–15 benchmark clips of 1–5 min each.

## Constitution Check

*GATE: must pass before Phase 0 research. Re-checked after Phase 1 design.* Constitution v1.0.0 (`.specify/memory/constitution.md`).

**Mission trace (Principle I)**: every element below traces to `MISSION.md`:
- Phase 0 steps 1–5: harness, clips, adapters (cloud, Whisper/ivrit.ai, Apple and Android baselines), metrics, VAD/noise on/off.
- Phase 1 steps 6–8: spike, app pipeline mic → VAD/noise suppression → engine → caption screen, config, lock-screen widget, real use.
- Constraints: one codebase, engine interface, config not code, 3 controls, privacy, and OS speech as baseline and fallback.

| # | Principle | Pre-design | Post-design evidence |
|---|---|---|---|
| I | Mission fidelity | ✅ | Phase 0 has all MISSION step-3 baselines, including Android ([research R-12](research.md)). The VAD is a required app stage ([R-5](research.md)). The on-device fallback is MISSION's "OS speech … fallback" constraint, with the behavior chosen by the user in spec Clarifications. S9 conflict resolved 2026-11-18: the user approved updating MISSION.md, so v1 is done at S1–S8 and S9 is post-v1. Fallback conflict resolved 2026-11-18: the user approved updating MISSION.md, which now puts the on-device fallback in v1 (Phase 1 step 7) |
| II | Typed, statically checked | ✅ | ty and strict `dart analyze` in the gates. Seams are typed interfaces: `AudioSource`, `SpeechGate` (VAD/noise), `EngineAdapter`, `CaptionAssembler`, `SettingsStore`, `StatsStore` ([data-model.md](data-model.md)) |
| III | One linter/formatter per language | ✅ | ruff in `bench/pyproject.toml`; `app/analysis_options.yaml` |
| IV | Tests are the contract | ✅ | Test Map below covers every FR/SC. Contract tests run both sides against `shared/engine-events.schema.json` and shared fixtures. Fake clock. Live checks are kept out of pytest |
| V | KISS/YAGNI/DRY | ✅ | One shared definition (`shared/`) for the event schema, profiles, VAD and latency definitions. The speaker-change heuristic is built only if the chosen engine lacks speaker labels ([R-8](research.md)). A language change restarts the adapter instead of adding a new protocol op ([R-14](research.md)) |
| VI | SOLID / Demeter / low coupling | ✅ | Logic lives in plain Dart/Python units with injected collaborators. Widgets and platform-channel handlers are thin. The app and harness share only `shared/` |
| VII | Idiomatic code | ✅ | Enforced by the ruff families and Dart lints in the gates. Streams use async iterators / `Stream` |
| VIII | Exceptions only at boundaries | ✅ | Catch points: provider sockets, platform channels, file I/O, model inference, and the single isolation point per harness item / caption session. Failures become `health`/`error` events and visible status |
| IX | Immutable validated models | ✅ | Frozen Pydantic v2 models in Python, `@immutable` classes with `fromJson` validation in Dart, for every record in [data-model.md](data-model.md). Settings is one immutable model |
| X | Human oversight | ✅ | All work lands through PRs that Itai reviews. Agents don't merge |
| XI | Appropriate delegation | ✅ | Normalization, latency definitions, VAD thresholds and cost are code/config. SC-003 thresholds and engine choice are **Itai's recorded decision** in `decision.md`; the report only shows the data. No LLM anywhere |
| XII | Observability | ✅ | Every harness run logs processed/succeeded/skipped/failed counts. Each result records clip-set hash, engine, model/API version, cleanup and harness version. Session stats per session. Standard logging, with no text or audio in logs |
| XIII | Security & privacy | ✅ | All provider, channel, config and clip input is validated into models. TLS only. Keys in `.env` (harness) and the Keychain (app). No audio persisted. Provider terms recorded in `vendor-check.md`, and the privacy gate is enforced from profiles |
| XIV | Zero trust | ✅ | Separate harness and app keys, each scoped as narrowly as the provider allows. The app requests only mic + background audio. No SDK sample credentials |
| XV | Stateless, idempotent | ✅ | Results keyed by clip × engine × cleanup, so a re-run overwrites. Adapters keep no state between sessions. Fallback and reconnect are tested for no lost or duplicated segments |
| XVI | Documentation | ✅ | Contracts in `contracts/` + `shared/`, decisions in `research.md` / `decision.md` / `vendor-check.md`, docstrings required |
| XVII | Think before coding | ✅ | Open conflicts are flagged (MISSION S9, SC-010 wording) instead of being guessed |
| XVIII | Surgical changes | ✅ | Each task touches its own files |
| XIX | Goal-driven | ✅ | Every task gets a verify step traced to S1–S9 (enforced in `/speckit-tasks`) |
| XX | Memory | ✅ | `specs/001-live-captions/lessons.md` records surprises from the spike, benchmark and real use |
| Gates | pre-commit, CI, run-for-real | ✅ | Setup creates `.pre-commit-config.yaml` and `.github/workflows/ci.yml`. Phase 0 is done only after a full real run; Phase 1 only after an iPhone session in G1/G3 with S1/S2/S7 read from stats |
| Constraints | uv, Pydantic, shared contract, result integrity, consented clips, failure isolation, secrets | ✅ | All commands use `uv run`. Clips are gitignored. The harness continues past failed items and then marks the run failed |

**Result**: passes, with one item that needs the user (MISSION S9 vs. spec).

## Test Map (Principle IV: one or more tests per requirement)

| Requirement | Test (location) |
|---|---|
| Engine contract (FR-013, shared) | `bench/tests/test_contract.py`, `app/test/engine_contract_test.dart`: both validate `shared/fixtures/*.events.jsonl` against the schema and assemble the same segments |
| Each adapter | `bench/tests/adapters/test_<engine>.py` and `app/test/adapters/<engine>_test.dart`: recorded vendor messages in `shared/fixtures/vendor/<engine>/` → events that match the schema |
| WER/CER per language (FR-016) | `bench/tests/test_metrics_wer.py` |
| Latency defs (SC-001/002) | `bench/tests/test_metrics_latency.py` and `app/test/latency_test.dart`, run on the same fixture with the same expected numbers |
| Made-up words on silence (FR-005, SC-004) | `bench/tests/test_metrics_hallucination.py`; `app/test/speech_gate_test.dart` (silence fixture → no frames passed → no text) |
| Speaker markers (FR-006, SC-005) | `bench/tests/test_metrics_speakers.py`; `app/test/caption_assembler_test.dart` (speaker_change → marker) |
| Provisional → final (FR-002/008) | `app/test/caption_assembler_test.dart` |
| Freeze loses nothing (FR-009/010) | `app/test/caption_view_controller_test.dart` |
| Engine switch with no rebuild (FR-013) | `app/test/settings_test.dart`: change the active engine in settings → the next session builds that adapter |
| Cost / cap (FR-014/015) | `app/test/cost_meter_test.dart` |
| No audio persisted (FR-018) | `app/test/privacy_test.dart` |
| Export (FR-019/025) | `app/test/transcript_export_test.dart` |
| Privacy gate (FR-020) | `bench/tests/test_profiles.py`; `app/test/profiles_test.dart` |
| Status / no stale text (FR-021) | `app/test/session_controller_test.dart` |
| Stats contain no text (FR-023) | `app/test/session_stats_test.dart` |
| Fallback (FR-024) | `app/test/fallback_controller_test.dart` |
| Idempotent re-runs (XV) | `bench/tests/test_results_store.py` |
| Failure isolation (constraints) | `bench/tests/test_run_isolation.py` |
| Native code (FR-001, FR-022, FR-024, Phase 0 baselines) | Pure-logic units tested natively: `bench/tools/apple-speech/Tests/AppleSpeechCoreTests` (`swift test`); `app/ios/RunnerTests/{PcmFramer,AudioSessionEventMapper,SpeechResultMapper}Tests.swift` (`xcodebuild test`); `bench/tools/android-speech/.../EventMapperTest.kt` (`./gradlew test`). Thin OS glue around them is checked on the device |
| Lock-screen start (FR-011) | `app/test/launch_action_test.dart` (`start=true` → session starts; OS-kill → notice), plus device check V5 |
| FR-022, SC-006–008 | Device validation (quickstart V5, V8), plus the `paused_mic` cases in `session_controller_test`. The rest is OS behavior with no unit-testable logic |

## Project Structure

### Documentation (this feature)

```text
specs/001-live-captions/
├── plan.md  research.md  data-model.md  quickstart.md
├── contracts/   engine-stream.md · engine-profiles.md · pipeline-config.md · bench-cli.md · session-stats.md · export-format.md · caption-screen.md
├── vendor-check.md   decision.md   lessons.md   validation.md   (created during work)
└── tasks.md
```

### Source Code (repository root)

```text
shared/                           # the ONE language-neutral definition (V, Project Constraints)
├── engine-events.schema.json     # JSON Schema for engine events
├── engines.yaml                  # engine profiles (no secrets)
├── pipeline.yaml                 # VAD model + thresholds, latency definitions, speaker heuristic (if needed)
├── models/silero_vad.onnx        # pinned VAD model used by both sides
└── fixtures/                     # *.events.jsonl + short silence/speech WAVs used by both test suites

bench/                            # Phase 0 harness — uv project
├── pyproject.toml  uv.lock       # [tool.ruff], [tool.ty]
├── src/itabench/
│   ├── models.py                 # frozen Pydantic models (events, profiles, clip, reference, result)
│   ├── contract.py               # EngineAdapter Protocol
│   ├── profiles.py  streaming.py  speech_gate.py  results_store.py  run.py  score.py  report.py  align.py  cli.py
│   ├── engines/                  # fake, google, azure, agora, soniox|speechmatics, whisper_local, apple_speech, android_speech
│   ├── cleanup/                  # none, rnnoise, deepfilternet, voiceproc
│   └── metrics/                  # normalize, wer, latency, hallucination, speakers
├── tools/apple-speech/           # Swift CLI: on-device speech + voice-processing variant
├── tools/android-speech/         # minimal Android helper app (adb-forwarded socket)
└── tests/

app/                              # Phase 1 Flutter app
├── analysis_options.yaml  pubspec.yaml  pubspec.lock
├── lib/
│   ├── models/                   # immutable value classes
│   ├── engines/                  # EngineAdapter interface, profiles, adapters
│   ├── capture/  gate/           # AudioSource wrapper, SpeechGate (Silero VAD)
│   ├── session/                  # session controller, caption assembler, fallback, stats, cost meter
│   ├── ui/                       # caption screen, settings, stats
│   └── export/
├── ios/Runner/ (AudioCapturePlugin, AppleSpeechPlugin, StartCaptionsIntent)  ios/CaptionsWidget/
└── test/

.pre-commit-config.yaml   .github/workflows/ci.yml
```

**Structure Decision**: two projects plus `shared/`. The harness and app never import each other (VI). Both load and test against `shared/`. `.gitignore` must change `lib/` to `/lib/` and add `bench/data/`, `bench/results/`, `.env`.

## Phasing (input for /speckit-tasks)

- **Setup**: gitignore, uv project, tooling gates (pre-commit, CI), `shared/` skeleton, vendor check.
- **Foundational**: Pydantic models, schema, contract tests, profiles, fake engine, streaming, speech gate, results store.
- **Phase 0 / US2**: metrics, cleanup variants (including `voiceproc`), all adapters (including the Android baseline), run/score/report, clips, real run → `decision.md`.
- **Phase 1 / US1**: spike, app skeleton with gates, capture → gate → adapter → assembler → caption screen, settings.
- **US3, US4, US5, then Polish** (fallback, stats, export, cost, banners incl. battery-low, privacy), then v1 validation.
- **US6** post-v1.

## Open Items (need the user, not blocking `/speckit-tasks`)

1. ~~**MISSION.md S9**~~: resolved 2026-11-18. MISSION now says v1 is done at S1–S8.
1a. ~~**MISSION.md on-device fallback**~~: resolved 2026-11-18. MISSION now has the automatic on-device fallback in v1, and the non-goal now reads "no full-accuracy offline mode".
2. ~~**Spec SC-010** wording~~: resolved 2026-11-18. The clause with no baseline was dropped, and SC-010 now matches MISSION ("used it for real at least 5 times in G1 and G3"). SC-001/002 now use the shared VAD-based definition (R-3).
3. ~~**Stack spike scope**~~: resolved 2026-11-18. Itai chose a Flutter-only spike, and MISSION step 6 was updated (R-1).

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Kotlin helper app for the Android baseline (Phase 0) | MISSION Phase 0 step 3 requires the Android on-device baseline; `SpeechRecognizer` only runs on Android | Skipping it diverges from the mission (Principle I); an emulator alone without a helper can't take streamed PCM |
| ONNX VAD in the app (not an OS VAD) | The mission pipeline requires VAD, and the latency definitions must be identical in the harness and the app | iOS has no general-purpose public VAD API; a different VAD per side breaks the shared latency definition |
