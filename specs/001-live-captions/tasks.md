# Tasks: Live Captions for Hard Listening Situations

**Input**: Design documents from `specs/001-live-captions/` ([plan.md](plan.md) rev 2, [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)). Constitution v1.0.0 applies.

**Tests**: required by constitution Principle IV. Every requirement in the plan's Test Map has a test task, written before or alongside its code. Unit tests use no network, no microphone, no model downloads and no keys, and an injected fake clock. Live engine checks run only through `itabench check-engine` / `itabench run`.

**Verify**: every task ends with a **Verify:** clause, its success check (Principle XIX). A task is done only when that check passes.

**Commands**: all Python runs through `uv run` / `uvx`. Never call `python`, `pip` or `.venv/bin` directly.

**Order**: User Story 2 (benchmark, P2) runs before User Story 1 (P1), because the engine must be chosen from data first (plan, Principle XI). Task IDs follow execution order.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no unfinished dependency)
- **[Story]**: US1–US6 from spec.md

## Path Conventions

- `shared/`: the one language-neutral definition: schema, profiles, pipeline config, VAD model, fixtures
- `bench/`: Python harness (`uv` project); code in `bench/src/itabench/`, tests in `bench/tests/`
- `app/`: Flutter app; code in `app/lib/`, native code in `app/ios/`, tests in `app/test/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: repo hygiene, quality gates, the `shared/` definitions, and vendor facts.

- [X] T001 Fix `.gitignore`: change the bare `lib/` rule to `/lib/`, and add `bench/data/`, `bench/results/`, `.env`, `bench/.env`. **Verify:** `git check-ignore app/lib/main.dart` prints nothing, and `git check-ignore bench/data/x.wav bench/results/x bench/.env` prints all three
- [X] T002 Create the harness project with `uv init --package --name itabench bench`. In `bench/pyproject.toml`:
  - Python `>=3.13,<3.14`
  - deps `pydantic>=2 jiwer numpy soundfile websockets typer pyyaml onnxruntime`
  - optional groups `cleanup = [pyrnnoise, deepfilternet]`, `local = [faster-whisper]`, and one group per cloud SDK
  - dev group `pytest pytest-asyncio jsonschema ruff ty`
  - `[project.scripts] itabench = "itabench.cli:app"`
  - `[tool.ruff]` selecting at least `E,F,UP,SIM,C4,PTH,RET,PIE,PERF,E722,BLE,TRY,ANN,D`, with `pydocstyle.convention = "google"` and `D` ignored only under `tests/` (research R-13)
  - `[tool.ty]`
  - commit `bench/uv.lock`

  **Verify:** `cd bench && uv sync --locked && uv run ruff check && uv run ty check` pass
- [X] T003 [P] Create `shared/engines.yaml` with a `fake` profile and placeholder profiles `apple-ondevice`, `android-ondevice`, `agora-rtstt`, `google-stt-he`, `azure-speech-he`, `soniox-rt`, `speechmatics-rt` and `whisper-ivrit-local`, exactly per `contracts/engine-profiles.md`. **Verify:** each entry has every field in the contract
- [X] T004 [P] Create `shared/pipeline.yaml` with the values in `contracts/pipeline-config.md`, and `shared/README.md` explaining that both `bench/` and `app/` load these files and must not copy their values. **Verify:** `uv run --project bench python -c "import yaml,sys; yaml.safe_load(open('shared/pipeline.yaml'))"` exits 0
- [X] T005 [P] Write `shared/engine-events.schema.json` (JSON Schema draft 2020-12): a `oneOf` over the seven event types in `contracts/engine-stream.md`, with `additionalProperties: false` on each. **Verify:** `uvx check-jsonschema --check-metaschema shared/engine-events.schema.json` passes
- [X] T006 [P] Add the pinned Silero VAD ONNX model as `shared/models/silero_vad.onnx` (from the official `snakers4/silero-vad` release tag) and record its sha256 in `shared/pipeline.yaml` `vad.model_sha256`. **Verify:** `shasum -a 256 shared/models/silero_vad.onnx` matches the YAML
- [X] T007 [P] Create the shared fixtures in `shared/fixtures/`:
  - event logs: `partial-then-final.events.jsonl`, `speaker-change.events.jsonl`, `health-lost.events.jsonl`, `cancel-midstream.events.jsonl`
  - latency fixture: `latency-basic.events.jsonl` + `latency-basic.spans.json` + `latency-basic.expected.json` (hand-computed p50/p90 for both definitions)
  - audio: `silence-5s.wav` (16 kHz mono digital silence) and `speech-short.wav` (16 kHz mono, generated with macOS `say` then converted with `afconvert`)

  **Verify:** all nine files listed above exist, and both WAVs are 16 kHz mono (`afinfo`). Schema validity of every `.jsonl` line is checked by T014(a), which must pass before Phase 2's checkpoint
- [X] T008 [P] Create `.pre-commit-config.yaml` with pinned revisions:
  - `ruff` (check + format) and a local `ty` hook (`uv run --project bench ty check`)
  - local `dart format --set-exit-if-changed` and `dart analyze` hooks, limited to `^app/`

  **Verify:** `uvx pre-commit install` succeeds (the hooks run on the next `git commit`), and `uvx pre-commit run --all-files` passes
- [X] T009 [P] Create `.github/workflows/ci.yml`:
  - triggers on `pull_request` and `push` to `main`
  - `permissions: contents: read`; actions pinned to commit SHAs; no secrets
  - jobs: (1) pre-commit on all files; (2) `uv sync --locked` + `uv run pytest` in `bench/`; (3) `flutter test` in `app/`; (4) `swift test` in `bench/tools/apple-speech/` on a pinned `macos` runner; (5) `xcodebuild test` of `app/ios` `RunnerTests` on an iOS simulator (macOS runner), after setup steps `flutter build ios --config-only` and `pod install`; (6) `./gradlew test` in `bench/tools/android-speech/` (Linux, pinned JDK). Each job is skipped while its directory doesn't exist yet

  **Verify:** the workflow passes on the branch's PR
- [X] T010 [P] Create `bench/.env.example`, listing one env var name per cloud profile for **harness-only** keys (no values), with a header saying the app uses separate keys (XIV). **Verify:** `grep -E '=.+' bench/.env.example` finds nothing
- [ ] T011 Do research task R-2a. For Agora, Google, Azure, Soniox and Speechmatics, read the current vendor docs and write `specs/001-live-captions/vendor-check.md`, a table with source links and access dates covering: streaming Hebrew, mixed-language support, live speaker labels, price per hour, audio retention/training terms, and opt-out. Then:
  - fill `cost_usd_per_hour` and `privacy.*` in `shared/engines.yaml`
  - pick one of Soniox/Speechmatics and delete the other profile
  - remove profiles that retain audio with no opt-out

  **Verify:** every remaining cloud profile has `terms_source` + `terms_checked_on`, and none fails the privacy gate rules

**Checkpoint**: the gates run, and `shared/` is complete and valid.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: harness models, contract, clock, streaming, VAD gate and results store. Everything in US2 depends on these.

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T012 Implement frozen Pydantic v2 models (`ConfigDict(frozen=True, extra="forbid")`, tuple collections) in `bench/src/itabench/models.py`:
  - `AudioFrame`, `SpeechSpan`
  - the seven events as a discriminated union on `type`
  - `EngineProfile`, `PipelineConfig`, `TestClip`, `Reference`, `EvaluationResult`
  - every field per `data-model.md`

  **Verify:** `uv run ty check` passes; T014 passes
- [X] T013 [P] Implement `Clock` (Protocol), `SystemClock` and `FakeClock` (manual `advance(ms)`) in `bench/src/itabench/clock.py`. **Verify:** T014's tests use `FakeClock`, and no test sleeps
- [X] T014 [P] Write the contract tests in `bench/tests/test_contract.py`:
  - (a) every `shared/fixtures/**/*.events.jsonl` line (including `native/`) validates against `shared/engine-events.schema.json` **and** parses into the event model
  - (b) every model's JSON dump validates against the schema
  - (c) a schema field renamed in a temporary copy makes (a) fail

  **Verify:** `uv run pytest bench/tests/test_contract.py` passes
- [X] T015 [P] Write the profile and pipeline config tests in `bench/tests/test_profiles.py`:
  - each of these raises: device profile with non-zero cost; `can_be_fallback` on cloud; `retains_audio: true` opened; `trains_on_audio` with no opt-out; unknown adapter
  - an unknown key in `pipeline.yaml` raises

  **Verify:** passes, and fails if any rule is removed from `profiles.py`
- [X] T016 Implement the `EngineAdapter` Protocol (`open`, `push_audio`, `finish`, `cancel`, `events`) and an adapter registry keyed by `adapter` in `bench/src/itabench/contract.py`. **Verify:** `uv run ty check` flags a deliberately non-conforming dummy class in a scratch test, which is then deleted
- [X] T017 Implement loading of `shared/engines.yaml` and `shared/pipeline.yaml` into models in `bench/src/itabench/profiles.py`. Loading enforces every validation rule, including the privacy gate, plus the VAD model sha256 check. **Verify:** T015 passes
- [X] T018 [P] Implement `FakeEngine` (adapter key `fake`) in `bench/src/itabench/engines/fake.py`. It replays a fixture event log against an injected `Clock`. **Verify:** `bench/tests/test_fake_engine.py`: `partial-then-final` gives exactly one final, and with `cancel-midstream` nothing follows `closed`
- [X] T019 Implement the real-time feeder in `bench/src/itabench/streaming.py`:
  - read a validated 16 kHz mono WAV
  - push 20 ms `AudioFrame`s paced by the `Clock`
  - consume `events()` concurrently
  - write each event plus its arrival `t_ms` to an `.events.jsonl`
  - append 5 s of silence before `finish()`

  **Verify:** `bench/tests/test_streaming.py` with `FakeClock` + `FakeEngine` gives the expected arrival times
- [X] T020 Implement `SpeechGate` in `bench/src/itabench/speech_gate.py`: Silero ONNX via `onnxruntime`, with thresholds and padding from `PipelineConfig`. It outputs gated frames and `SpeechSpan`s, and has an `enabled=False` passthrough. **Verify:** `bench/tests/test_speech_gate.py`: `silence-5s.wav` → 0 frames passed and 0 spans; `speech-short.wav` → ≥ 1 span with onset < 1 s
- [X] T021 Implement the results store in `bench/src/itabench/results_store.py`:
  - path `bench/results/<engine>/<cleanup>/<vad>/<clip>.{events.jsonl,json}`
  - write to a temp file, then atomically replace (XV)

  **Verify:** `bench/tests/test_results_store.py`: writing the same key twice leaves one file holding the second content

**Checkpoint**: `uv run pytest` passes offline, and `uvx pre-commit run --all-files` is clean.

---

## Phase 3: User Story 2 – Pick the best speech engine using my own recordings (Priority: P2, runs first)

**Goal**: benchmark evidence across all of MISSION Phase 0, then Itai's recorded choice of engines, mic and SC-003 thresholds.

**Independent Test**: quickstart V0 + V1.

### Tests for User Story 2

- [X] T022 [P] [US2] Write normalization and WER tests in `bench/tests/test_metrics_wer.py`: niqqud, final letters, geresh, punctuation, digits↔words, the by-language split of a mixed reference, and Hebrew CER. **Verify:** passes, and each case fails if its normalization rule is removed
- [X] T023 [P] [US2] Write latency tests in `bench/tests/test_metrics_latency.py`, using the `shared/fixtures/latency-basic.*` files and asserting the numbers in `latency-basic.expected.json`. **Verify:** passes
- [X] T024 [P] [US2] Write made-up-word tests in `bench/tests/test_metrics_hallucination.py`: finals inside `non_speech` intervals are counted, and finals outside them are not. **Verify:** passes
- [X] T025 [P] [US2] Write speaker-change recall tests in `bench/tests/test_metrics_speakers.py` (±1 s tolerance, with a miss and a false alarm). **Verify:** passes
- [X] T026 [P] [US2] Write failure-isolation tests in `bench/tests/test_run_isolation.py`: with 3 fake engines where one raises mid-clip, the other two are scored, the log has `processed=3 succeeded=2 failed=1`, and the CLI exits non-zero. **Verify:** passes

### Implementation for User Story 2

- [X] T027 [US2] Implement the Typer CLI skeleton in `bench/src/itabench/cli.py`, with `align`, `run`, `score`, `report` and `check-engine <id> [--record DIR]` per `contracts/bench-cli.md`, and logging via `logging` (no `print` outside report output). **Verify:** `uv run itabench --help` lists all five commands
- [X] T028 [US2] Implement `check-engine` in `bench/src/itabench/check.py`. It opens the real adapter with keys from `bench/.env`, streams `speech-short.wav` and then `silence-5s.wav`, and checks that the events validate and that silence produces no final text. `--record` saves raw vendor messages to `shared/fixtures/vendor/<id>/` (stored once and used by both test suites). **Verify:** `uv run itabench check-engine fake` exits 0
- [X] T029 [P] [US2] Implement clip and reference loading in `bench/src/itabench/data.py`: validate WAVs (format, 16 kHz mono after conversion, duration), require `consent: true` + `consent_date`, and compute sha256. **Verify:** `bench/tests/test_data.py` rejects a clip with no consent and a clip with the wrong sample rate
- [X] T030 [P] [US2] Implement normalization (research R-4) in `bench/src/itabench/metrics/normalize.py`. **Verify:** T022 passes
- [X] T031 [P] [US2] Implement WER/CER overall and by language in `bench/src/itabench/metrics/wer.py`. **Verify:** T022 passes
- [X] T032 [P] [US2] Implement the shared latency definition (research R-3) in `bench/src/itabench/metrics/latency.py`, reading the definitions from `PipelineConfig`. **Verify:** T023 passes
- [X] T033 [P] [US2] Implement made-up-word counting in `bench/src/itabench/metrics/hallucination.py`. **Verify:** T024 passes
- [X] T034 [P] [US2] Implement speaker-change recall in `bench/src/itabench/metrics/speakers.py`. **Verify:** T025 passes
- [X] T035 [P] [US2] Implement the cleanup variants `none`, `rnnoise` and `deepfilternet` in `bench/src/itabench/cleanup/` (`__init__.py` factory + one module each). **Verify:** `bench/tests/test_cleanup.py`: each variant returns 16 kHz mono of the same length for `speech-short.wav`
- [ ] T036 [P] [US2] Build the Swift package `bench/tools/apple-speech/` with two subcommands:
  - `recognize`: stdin PCM → `SpeechAnalyzer`/`SFSpeechRecognizer` with on-device recognition → schema events as JSONL on stdout, and it reports whether `he-IL` on-device is available
  - `voiceproc`: applies `AVAudioEngine` voice processing in manual-rendering mode. If manual rendering rejects voice processing, record that in `specs/001-live-captions/lessons.md` and implement loopback (play + capture) instead
  - **Native tests (IV)**: put the pure logic (PCM framing, recognition result → schema event JSON, the `he-IL` availability report) in a library target `AppleSpeechCore` with no `Speech`/`AVFoundation` calls. Cover it with XCTest in `bench/tools/apple-speech/Tests/AppleSpeechCoreTests/`: partial → final for the same segment, empty result → no final, and every emitted line equals the expected JSON in `shared/fixtures/native/` (these `native/*.events.jsonl` files are schema-validated by the T014 contract test, so there is no Swift schema library)

  Add the wrappers `bench/src/itabench/engines/apple_speech.py` and `bench/src/itabench/cleanup/voiceproc.py`. **Verify:** `swift test` passes in `bench/tools/apple-speech/`, `uv run itabench check-engine apple-ondevice` exits 0, and the `voiceproc` output for `speech-short.wav` is non-empty 16 kHz mono
  **Status (2026-11-19)**: built and compiling; `AppleSpeechCore` logic verified with a scratch executable, wrappers and offline adapter test pass. Still open: `swift test` (this Mac has no Xcode, so XCTest cannot run; CI will), `check-engine apple-ondevice` (needs Speech permission, interactive), and the `voiceproc` loopback run (needs speakers + mic). Voice processing is rejected in offline rendering (see `lessons.md`).
- [ ] T037 [P] [US2] Build the Kotlin helper app `bench/tools/android-speech/` (research R-12; `minSdk 33`, since streamed audio goes in through `RecognizerIntent.EXTRA_AUDIO_SOURCE`): it takes PCM over a TCP socket (`adb forward`), runs on-device `SpeechRecognizer` (`EXTRA_PREFER_OFFLINE`), and writes schema events as JSONL back over the socket. Put the recognizer-callback → schema-event mapping and the PCM framing in a plain Kotlin class `EventMapper.kt`, and cover it with a JVM unit test in `bench/tools/android-speech/app/src/test/.../EventMapperTest.kt`: partial and final results, errors becoming `error` events, and output equal to the expected JSON in `shared/fixtures/native/` (schema-validated by the T014 contract test, so there is no extra Kotlin schema library) (IV). Add the wrapper `bench/src/itabench/engines/android_speech.py`. **Verify:** `./gradlew test` passes in `bench/tools/android-speech/`, and with a device or emulator attached, `uv run itabench check-engine android-ondevice` exits 0, and `lessons.md` notes whether it ran on a device or an emulator
- [ ] T038 [P] [US2] Implement the Google streaming adapter in `bench/src/itabench/engines/google_streaming.py`, validating vendor messages into models (`error: invalid_message` on bad input). Record with `check-engine --record`, then add `bench/tests/adapters/test_google.py` replaying the recordings offline. **Verify:** the offline test passes and `check-engine google-stt-he` exits 0
- [ ] T039 [P] [US2] Implement the Azure adapter (language ID when `auto`) in `bench/src/itabench/engines/azure_streaming.py`, plus `bench/tests/adapters/test_azure.py` from recordings. **Verify:** same as T038
- [ ] T040 [P] [US2] Implement the Agora RT-STT adapter in `bench/src/itabench/engines/agora_rtstt.py`, plus `bench/tests/adapters/test_agora.py` from recordings. **Verify:** same as T038
- [ ] T041 [P] [US2] Implement the adapter for the Soniox/Speechmatics choice from T011, emitting `speaker_change` from vendor labels, in `bench/src/itabench/engines/<choice>_rt.py`, plus `bench/tests/adapters/test_<choice>.py` from recordings. **Verify:** same as T038, and a recording with two speakers produces a `speaker_change`
- [ ] T042 [P] [US2] Implement the local Whisper adapter in `bench/src/itabench/engines/whisper_local.py`: `faster-whisper` with the ivrit.ai checkpoint pinned in `shared/engines.yaml` `options` and used as-is; a 10 s rolling window with 1 s hops; partials every hop; finals when a prefix is stable across 2 hops. **Verify:** `bench/tests/adapters/test_whisper_local.py` checks the finalization policy with a stubbed transcriber, and `check-engine whisper-ivrit-local` exits 0
  **Status (2026-11-19)**: adapter and finalization policy built; `test_whisper_local.py` passes with a stubbed transcriber. Open: `check-engine whisper-ivrit-local` (needs the `local` extra, a model download, and confirming the ivrit.ai checkpoint id in `shared/engines.yaml`).
- [X] T043 [US2] Implement `itabench align` in `bench/src/itabench/align.py`: hand-corrected `refs/<clip>.txt` (lines tagged `he|en`) → `refs/<clip>.json` with words + lang, `non_speech` intervals ≥ 1 s from `SpeechGate`, and empty `turn_changes_ms`. Uncertain spans are flagged `needs_check`. **Verify:** `bench/tests/test_align.py` on a tiny fixture produces the expected JSON
- [X] T044 [US2] Implement `itabench run` in `bench/src/itabench/run.py`:
  - loop over engines × cleanup × VAD on/off × clips: cleanup → `SpeechGate` (when on) → `streaming.py`
  - write through `results_store`
  - isolate each item (a single catch-all at the item boundary, logged with a stack trace)
  - log processed/succeeded/skipped/failed counts, and exit non-zero on any failure
  - skip privacy-gated profiles and count the skips

  **Verify:** T026 passes, and re-running one combination leaves one result
- [X] T045 [US2] Implement `itabench score` in `bench/src/itabench/score.py`, writing an `EvaluationResult` JSON per item with full provenance (clip sha256, engine version, `shared/` hashes, harness version, `ran_at`, status). **Verify:** `bench/tests/test_score.py` on fake-engine results gives the expected metrics, with every provenance field set
- [X] T046 [US2] Implement `itabench report` in `bench/src/itabench/report.py`, writing `bench/results/report.md`:
  - the R-4 normalization rules at the top
  - tables by engine × language × situation × cleanup × VAD (WER/CER, provisional/final p50/p90, made-up words, speaker recall, $/h)
  - a provenance appendix
  - **no recommendations or thresholds** (XI)

  **Verify:** `bench/tests/test_report.py` has separate Hebrew, English and mixed columns, and no "recommend" text
- [ ] T047 [US2] (Manual, Itai) Record 10–15 clips with the consent of everyone in them: café, group, meeting and 1 lecture; Hebrew, English and mixed; at least 2 through an external or table mic.
  - Add `bench/data/clips/<id>.wav` + `.yaml` and the hand-corrected `bench/data/refs/<id>.txt`
  - Run `uv run itabench align <id>` and fix the `needs_check` flags
  - Annotate turn changes on the group clips

  **Verify:** `uv run itabench run --engines fake --clips all` loads every clip with 0 failures
- [ ] T048 [US2] Run the full benchmark for real (Quality Gates): `uv run itabench run --cleanup none,rnnoise,deepfilternet,voiceproc --vad on,off && uv run itabench score && uv run itabench report`. **Verify:** the run log shows 0 failed (or failures explained in `lessons.md` and re-run), and `report.md` covers every engine, including the Apple and Android baselines
- [ ] T049 [US2] (Itai decides) Write `specs/001-live-captions/decision.md` citing `report.md` numbers:
  - active engine per language mode, and the on-device fallback (or none for Hebrew, R-17)
  - mic decision
  - SC-003 thresholds
  - whether the speaker heuristic is needed (R-8)
  - VAD threshold changes, if any

  Then copy the thresholds into SC-003 of `specs/001-live-captions/spec.md`, mark the defaults in `shared/engines.yaml`, and add the run's surprises to `lessons.md`. **Verify:** `spec.md` SC-003 has numbers, and each number appears in `decision.md` with its source

**Checkpoint**: Phase 0 is done. MISSION's Phase 0 output exists, and app work can begin.

---

## Phase 4: User Story 1 – Follow a conversation in a noisy café (Priority: P1) 🎯 MVP

**Goal**: live Hebrew/English captions on the iPhone through the mission pipeline: mic → voice processing → VAD → engine → caption screen.

**Independent Test**: quickstart V2.

### Setup and spike for User Story 1

- [ ] T050 [US1] Install Flutter stable, pinning the version in `app/.flutter-version` and in the CI step. Run `flutter create --org dev.itai --platforms ios,android,macos app`.
  - `app/analysis_options.yaml`: strict-casts, strict-inference, strict-raw-types, `avoid_catches_without_on_clauses`, `prefer_final_locals`, `prefer_const_constructors`, `avoid_print`, `always_declare_return_types`, `type_annotate_public_apis`, `public_member_api_docs`
  - add the plan's dependencies to `app/pubspec.yaml` and commit `pubspec.lock`
  - expose `shared/` as assets through the symlink `app/assets/shared → ../../shared`; if the iOS build doesn't follow symlinks, add `app/tool/sync_shared.sh` plus a CI check that the copy's hashes match `shared/`

  **Verify:** `cd app && dart analyze && flutter test` pass, and `uvx pre-commit run --all-files` passes with the Dart hooks active
- [ ] T051 [US1] Do the R-1 spike: write `app/ios/Runner/AudioCapturePlugin.swift`.
  - `AVAudioEngine` input with `setVoiceProcessingEnabled(true)`, converted to 16 kHz mono s16le 20 ms frames on the `EventChannel` `itatranscript/audio`
  - `UIBackgroundModes: audio` and a microphone usage string in `app/ios/Runner/Info.plist`; no other permissions (XIV)
  - session `.playAndRecord`
  - **Native tests (IV)**: put the conversion in a pure `app/ios/Runner/PcmFramer.swift` (float input at any sample rate → 16 kHz mono s16le, exactly 640-byte frames, leftover samples carried over between buffers). Cover it with XCTest in `app/ios/RunnerTests/PcmFramerTests.swift`: a 48 kHz sine wave keeps its frequency within ±1%, an odd buffer size loses no samples, and the frame size is always 640

  **Verify:** `xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'generic/platform=iOS Simulator'` (or any available iPhone simulator) passes in `app/ios/`. Then on the iPhone, the delay the app adds is ≤ 150 ms and capture survives 10 min locked, with results written under R-1 in `research.md`. **If it fails, stop**: a different stack needs a constitution amendment

### Tests for User Story 1

- [ ] T052 [P] [US1] Write contract tests in `app/test/engine_contract_test.dart`: every `assets/shared/fixtures/**/*.events.jsonl` line validates against the schema (`json_schema`) **and** parses through the Dart `fromJson`. **Verify:** passes, and fails if a model field is renamed
- [ ] T053 [P] [US1] Write latency tests in `app/test/latency_test.dart` on `latency-basic.*`, asserting the same `expected.json` numbers as T023. **Verify:** passes
- [ ] T054 [P] [US1] Write caption assembler tests in `app/test/caption_assembler_test.dart`: partial→final gives one final; finals are never changed; `lang: unknown` renders as `[unrecognized]`; `speaker_change` sets `speaker_change_before`. **Verify:** passes
- [ ] T055 [P] [US1] Write SpeechGate tests in `app/test/speech_gate_test.dart`: `silence-5s.wav` frames → 0 passed; `speech-short.wav` → ≥ 1 span. **Verify:** passes
- [ ] T056 [P] [US1] Write profile and settings tests in `app/test/profiles_test.dart` and `app/test/settings_test.dart`: the privacy gate refuses a retaining profile; changing `active_engine_id` in `Settings` makes the next session build that adapter, with no code change (FR-013). **Verify:** passes
- [ ] T057 [P] [US1] Write session controller tests in `app/test/session_controller_test.dart`: `idle→starting→live→ended`; a language change applies at the next VAD pause through finish + reopen (R-14); a socket error produces a visible error state, never stale text shown as live (FR-021). **Verify:** passes

### Implementation for User Story 1

- [ ] T058 [P] [US1] Implement the immutable models in `app/lib/models/` (`audio_frame.dart`, `engine_event.dart` as a sealed class family, `engine_profile.dart`, `pipeline_config.dart`, `caption_segment.dart`, `session_snapshot.dart`, `settings.dart`): `@immutable`, `final` fields, `const` constructors, value equality, `copyWith`, and a `fromJson` that validates every field. **Verify:** T052 passes, and `dart analyze` is clean
- [ ] T059 [P] [US1] Implement `Clock`, `SystemClock` and `FakeClock` in `app/lib/core/clock.dart`. **Verify:** used by T053, T057
- [ ] T060 [P] [US1] Implement the `EngineAdapter` abstract interface class, the registry, and `FakeEngine` (replaying fixtures with `Clock`) in `app/lib/engines/engine_adapter.dart` and `app/lib/engines/fake_engine.dart`. **Verify:** T052, T054 pass using `FakeEngine`
- [ ] T061 [P] [US1] Implement loading of `assets/shared/engines.yaml` and `pipeline.yaml` into models, with the privacy gate and the VAD sha256 check, in `app/lib/engines/profiles.dart`. **Verify:** T056 passes
- [ ] T062 [P] [US1] Implement the `AudioSource` interface and the platform-channel implementation in `app/lib/capture/audio_source.dart`, validating channel messages into `AudioFrame`. **Verify:** `app/test/audio_source_test.dart` with a mocked channel rejects a malformed frame
- [ ] T063 [US1] Implement `SpeechGate` in `app/lib/gate/speech_gate.dart`: Silero via `onnxruntime`, the same model file and thresholds as the harness, emitting gated frames and `SpeechSpan`s. **Verify:** T055 passes
- [ ] T064 [US1] Implement the shared latency definition in `app/lib/session/latency.dart`. **Verify:** T053 passes
- [ ] T065 [US1] Implement `CaptionAssembler` in `app/lib/session/caption_assembler.dart` (events → unmodifiable segment list). **Verify:** T054 passes
- [ ] T066 [US1] Implement `SettingsStore` in `app/lib/session/settings_store.dart`: one immutable `Settings` holding the only defaults, persisted to preferences; keys read and written through `flutter_secure_storage` and never logged. **Verify:** T056 passes
- [ ] T067 [US1] Implement `SessionController` in `app/lib/session/session_controller.dart`: owns the session, wires AudioSource → SpeechGate → adapter → assembler, exposes immutable snapshots, and contains the single per-session failure isolation point. **Verify:** T057 passes
- [ ] T068 [US1] Implement the WebSocket adapter for the active engine chosen in `decision.md`, in `app/lib/engines/<engine_id>_adapter.dart`. It validates every vendor message (invalid → `error: invalid_message`), uses TLS only, and uses app-only keys. Add `app/test/adapters/<engine_id>_test.dart`, replaying the recordings from `assets/shared/fixtures/vendor/<engine_id>/` (the same files the harness tests use; no copy). **Verify:** the test passes, and a live session on the iPhone shows captions
- [ ] T069 [US1] Implement the caption screen in `app/lib/ui/caption_screen.dart` per `contracts/caption-screen.md`: renders snapshots only; virtualized list; newest line largest; provisional text grey italic; RTL/LTR per segment; start/stop and language controls (the freeze slot is reserved for US3); dark default. **Verify:** `app/test/caption_screen_render_test.dart` golden or finder checks: provisional and final text styles differ, and a Hebrew segment is right-aligned
- [ ] T070 [US1] Implement the settings screen in `app/lib/ui/settings_screen.dart`: engine picker (FR-013), language mode, app API key entry, $/h of the active engine (FR-014). **Verify:** a widget test confirms that picking an engine updates `Settings.active_engine_id`
- [ ] T071 [US1] Wire everything in `app/lib/main.dart` with injected collaborators (VI). **Verify:** `flutter test` passes, and the app builds and runs on the iPhone
- [ ] T072 [US1] Run a quickstart V2 **smoke check** in a café on the iPhone. Record the results in `specs/001-live-captions/validation.md` and the surprises in `lessons.md`. **Verify:** captions appear for both Hebrew and English speech, mixed sentences keep both languages, and 30 s of clatter produced no text. Measured S1/S2 come from session stats in T095 (Quality Gates); the per-utterance numbers from `latency.dart` logged here are indicative only, and logs never contain text

**Checkpoint**: MVP is usable in a café.

---

## Phase 5: User Story 3 – Not miss a question in a meeting (Priority: P3)

**Goal**: freeze and scroll back with no speech lost.

**Independent Test**: quickstart V3.

- [ ] T073 [P] [US3] Write view-controller tests in `app/test/caption_view_controller_test.dart`: freeze keeps the visible lines fixed while 20 new segments arrive; resume jumps to the newest; scrolling back pauses auto-scroll; no segment is lost. **Verify:** passes, and fails if freeze drops events
- [ ] T074 [US3] Implement view state (`following | frozen | scrolledBack`), separate from `SessionState`, in `app/lib/ui/caption_view_controller.dart`. **Verify:** T073 passes
- [ ] T075 [US3] Add the freeze button and the "jump to live" chip in `app/lib/ui/caption_screen.dart`, driven by the view controller (FR-009, FR-010). **Verify:** run quickstart V3 on the iPhone and record it in `validation.md`

---

## Phase 6: User Story 4 – Know when the speaker changes in a group (Priority: P4)

**Goal**: markers on ≥ 80% of turn changes.

**Independent Test**: quickstart V4.

- [ ] T076 [US4] Render the speaker-change divider with a colored dot from `speaker_change_before` in `app/lib/ui/caption_screen.dart` (FR-006). **Verify:** a widget test shows a divider before a segment with `speaker_change_before: true`, and none otherwise
- [ ] T077 [US4] **Only if `decision.md` says the heuristic is needed (R-8)**:
  - add `speaker_heuristic` thresholds to `shared/pipeline.yaml`
  - implement `bench/src/itabench/speaker_heuristic.py` and `app/lib/session/speaker_change_heuristic.dart`
  - add the shared fixture `shared/fixtures/speaker-heuristic.*`, with tests on both sides asserting the same output

  Otherwise mark this task N/A in `decision.md`. **Verify:** both tests pass, and recall on the group clips is ≥ 80% in `report.md`
- [ ] T078 [US4] Run quickstart V4 (report recall plus a live dinner) and record it in `validation.md`. **Verify:** recall ≥ 80%

---

## Phase 7: User Story 5 – Start captions instantly (Priority: P5)

**Goal**: ≤ 2 taps / 3 s from the lock screen, and captions keep running while locked.

**Independent Test**: quickstart V5.

- [ ] T079 [US5] Handle `AVAudioSession` interruption and route-change notifications in `app/ios/Runner/AudioCapturePlugin.swift`, emitting `paused_mic` and resume events. Put the notification → event decision in a pure `app/ios/Runner/AudioSessionEventMapper.swift` (interruption began/ended with and without `.shouldResume`, route change with `oldDeviceUnavailable` → `paused_mic` / `resume` / none), with XCTest in `app/ios/RunnerTests/AudioSessionEventMapperTests.swift`. Add the `paused_mic` transitions to `app/lib/session/session_controller.dart`, plus cases in `app/test/session_controller_test.dart` (FR-022). **Verify:** the XCTest and Dart tests pass, and on the iPhone an incoming call pauses captions with the banner and they resume afterwards
- [ ] T080 [P] [US5] Add the `StartCaptionsIntent` App Intent in `app/ios/Runner/StartCaptionsIntent.swift`; it opens the app with `start=true`. **Verify:** running it from Shortcuts starts a session
- [ ] T081 [P] [US5] Add the widget extension `app/ios/CaptionsWidget/` with a `ControlWidget` and an accessory Lock Screen widget, both running `StartCaptionsIntent`. **Verify:** both appear in the Control Center / Lock Screen gallery on the iPhone
- [ ] T082 [US5] Handle `start=true` to auto-start, in a plain function `app/lib/session/launch_action.dart` (launch arguments plus the last stats entry → `startSession | showStoppedNotice(time) | none`) called from `app/lib/main.dart`. Show "captions stopped at HH:MM" after an OS kill (`end_reason: os_killed`). Add `app/test/launch_action_test.dart` covering all three outcomes (FR-011, Principle IV). **Verify:** the test passes, then run quickstart V5 (stopwatch ≤ 3 s / ≤ 2 taps; 5 min locked with no lost speech) and record it in `validation.md`

---

## Phase 8: Polish & Cross-Cutting (v1 requirements spanning stories)

**Purpose**: on-device fallback (MISSION Phase 1 step 7), stats, export, cost, banners and privacy. All are needed for v1 acceptance.

- [ ] T083 [P] Implement the native Apple on-device engine in `app/ios/Runner/AppleSpeechPlugin.swift` and its Dart adapter in `app/lib/engines/apple_speech_adapter.dart` (profile `apple-ondevice`, `can_be_fallback: true`), validating channel messages. Put the recognition result → channel event mapping in a pure `app/ios/Runner/SpeechResultMapper.swift`, with XCTest in `app/ios/RunnerTests/SpeechResultMapperTests.swift`: partial → final for the same segment, an empty result gives no final, `he-IL` unavailable gives `error: unsupported_language`, and output equal to the expected JSON in `shared/fixtures/native/` (schema-validated by the T014 and T052 contract tests) (IV). It's a small, deliberate duplicate of T036's `AppleSpeechCore`, because the app may not depend on the harness (VI), and two copies are accepted until a third one appears (V). **Verify:** the XCTest passes, `app/test/adapters/apple_speech_test.dart` with a mocked channel passes, and a live English session on the iPhone in airplane mode shows captions
- [ ] T084 [P] Write fallback tests in `app/test/fallback_controller_test.dart`, using two fake engines and `FakeClock`:
  - loss detected via `health: lost`, a socket error, or 2 s of silence during speech
  - switch ≤ 3 s; ring-buffer replay; no lost or duplicated finals on switching out and back
  - `paused_offline` when the fallback doesn't support the language

  **Verify:** passes
- [ ] T085 Implement `FallbackController` per research R-7 in `app/lib/session/fallback_controller.dart`, using `connectivity_plus` and a RAM-only 5 s ring buffer sized from `pipeline.yaml`, and integrate it into `SessionController`. **Verify:** T084 passes
- [ ] T086 [P] Write cost meter tests in `app/test/cost_meter_test.dart`: `usage` events × profile price accumulate per calendar month; warn at 90%; at 100%, the continue / switch-to-free decision is required; no warnings when the cap is null. **Verify:** passes
- [ ] T087 Implement the cost meter and monthly cap (FR-014/015) in `app/lib/session/cost_meter.dart`. **Verify:** T086 passes
- [ ] T088 [P] Write session stats tests in `app/test/session_stats_test.dart`: after a fake session with known caption text, the written JSONL line contains none of that text and no key; latency fields match `latency.dart` on the fixture; delete-one and delete-all work. **Verify:** passes
- [ ] T089 [P] Implement battery-low detection in `app/lib/session/battery_watch.dart`: uses `battery_plus`, measures the drain rate, and applies the thresholds from `pipeline.yaml` (R-18). Add `app/test/battery_watch_test.dart`. **Verify:** the test passes for both the minutes-left trigger and the percent trigger
- [ ] T090 Implement `StatsStore` + the recorder in `app/lib/session/session_stats.dart` per `contracts/session-stats.md` (latency, battery, locked time, switches, interruptions, errors, billed seconds, end reason), and the stats screen `app/lib/ui/stats_screen.dart` with delete (FR-023). **Verify:** T088 passes
- [ ] T091 [P] Implement status banners (`fallback`, `paused_offline`, `paused_mic`, OS-kill notice, battery low, cost cap) in `app/lib/ui/status_banner.dart`, mounted in `caption_screen.dart` so they don't cover the newest line (FR-021). **Verify:** a widget test shows the right banner per state, and the newest line stays visible
- [ ] T092 [P] Write export tests in `app/test/transcript_export_test.dart`: the format matches `contracts/export-format.md`; no provisional text; `[unrecognized]`; stats only when `test_mode` is on; the temp file is deleted even when sharing fails. **Verify:** passes
- [ ] T093 Implement export in `app/lib/export/transcript_export.dart` (temp file → `share_plus` → delete, with a single owner) and add the test-mode switch in `app/lib/ui/settings_screen.dart` (FR-019, FR-025). **Verify:** T092 passes
- [ ] T094 Write privacy tests in `app/test/privacy_test.dart`:
  - after a fake session plus export, the app documents directory contains only `stats.jsonl` (FR-018)
  - log records captured during the session contain no caption text and no key (XII, XIII)

  **Verify:** passes, and fails if a debug log of segment text is added
- [ ] T095 Run quickstart V6–V8 for real on the iPhone, plus 5 real uses across G1/G3. Record them in `validation.md`, with S1/S2/S7 taken from real session stats (Quality Gates), and the lessons in `lessons.md`. **Verify:** SC-001–SC-008 pass and SC-010 is met, so v1 is accepted

---

## Phase 9: User Story 6 – Simple mode for grandma (Priority: P6, post-v1)

**Goal**: an Android build with a single-button, extra-large simple mode. **Independent Test**: SC-009.

- [ ] T096 [P] [US6] Implement Android capture in `app/android/app/src/main/kotlin/dev/itai/itatranscript/AudioCapturePlugin.kt`: `AudioRecord` with `VOICE_COMMUNICATION` and `NoiseSuppressor`, a foreground service for locked capture, and the same `itatranscript/audio` contract. Put the framing in a pure `PcmFramer.kt` with a JVM unit test (`app/android/app/src/test/.../PcmFramerTest.kt`) that mirrors T051's cases (IV). **Verify:** `./gradlew test` and `flutter test` pass, and a live session runs on the Android phone with the screen locked for 5 min
- [ ] T097 [P] [US6] Implement simple mode in `app/lib/ui/simple_mode_screen.dart`: one start/stop button, extra-large text, settings behind a long-press (FR-012). **Verify:** a widget test finds exactly one button and no settings entry
- [ ] T098 [US6] Add the Android on-device fallback adapter in `app/lib/engines/android_speech_adapter.dart`, then validate quickstart V2 and V6 on Android. **Verify:** results recorded in `validation.md`
- [ ] T099 [US6] Run the grandma test (SC-009). **Verify:** recorded in `validation.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (T001–T011) → Foundational (T012–T021) → **US2** (T022–T049) → **US1** (T050–T072).
- US3, US4, US5 and Polish each depend only on US1, and can run in any order. T077 also depends on `decision.md`.
- US6 is post-v1. It depends on US1 and Polish.

### Key Task-Level Dependencies

- T011 → T041 (which vendor) and → the privacy fields used by T017/T061.
- T047 (recording clips, manual) can start on day 1, alongside all the coding.
- T048 → T049 → T068 (which engine to build in the app).
- Each adapter's live recording (T038–T041) → its offline test, and → T068 for the chosen engine.
- T051 (spike) blocks T058 onward. If it fails, stop and amend the constitution.
- T063–T067 → T072; T067 → T079, T085, T090; T083 → T085.

### Parallel Opportunities

- Setup: T003–T010 in parallel; T011 alongside them.
- Foundational: T013–T015 and T018 after T012.
- US2: tests T022–T026 together; then metrics T030–T034, cleanup T035, Apple/Android tools T036–T037 and adapters T038–T042 all in parallel; T047 runs throughout.
- US1: tests T052–T057 together; models and infrastructure T058–T062 together after T051.
- Polish: T083, T084, T086, T088, T089, T091, T092 in parallel.

## Parallel Example: User Story 2

```bash
# After Phase 2:
Task: "T030 normalize.py"   Task: "T032 latency.py"   Task: "T035 cleanup variants"
Task: "T036 apple-speech tool"   Task: "T037 android-speech helper"
Task: "T038 Google adapter"   Task: "T039 Azure adapter"   Task: "T042 Whisper adapter"
# In parallel, manual: T047 record and transcribe clips
```

## Parallel Example: User Story 1

```bash
# After T051 spike passes:
Task: "T052 engine_contract_test.dart"   Task: "T055 speech_gate_test.dart"   Task: "T057 session_controller_test.dart"
Task: "T058 models"   Task: "T060 EngineAdapter + FakeEngine"   Task: "T062 AudioSource"
```

## Implementation Strategy

### MVP First

1. Setup + Foundational (about 2 days): the gates are green.
2. US2 benchmark (about 1 week; record clips from day 1) → Itai writes `decision.md`.
3. US1 on the iPhone → **stop and validate** with V2 in a real café.

### Incremental Delivery

US1 → US3 → Polish (fallback, stats, export: these are needed for trustworthy real-use numbers) → US5 → US4 → v1 acceptance (T095) → US6 post-v1.

## Notes

- **Itai only**: T011 (vendor accounts, terms), T047 (consented recordings), T049 (decisions), and the real-world validation runs (T072, T075, T078, T082, T095, T099).
- Each task ends in a PR or commit reviewed by Itai (X). Agents don't merge.
- Surprises go into `lessons.md` as they happen (XX).
