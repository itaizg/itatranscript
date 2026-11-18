# Research: Live Captions for Hard Listening Situations

These are the Phase 0 decisions for [plan.md](plan.md) (rev 2, checked against constitution v1.0.0). Vendor facts (language support, retention, prices) are **unverified until R-2a**, which records them in `vendor-check.md` with sources and dates (XIII, XVI).

## R-1 App stack

- **Decision**: Flutter, with thin native Swift plugins for the audio session, Apple speech and the Lock Screen control (MISSION constraint: one cross-platform codebase, with native code only where the OS forces it; constitution Project Constraints).
- **Rationale**: one codebase for iOS → Android → macOS. Every hard iOS piece is native in any stack anyway.
- **Alternatives**: React Native (weaker on macOS, and per-line right-to-left layout for mixed Hebrew/English captions takes extra work); Swift only (means rewriting for Android); PWA (can't capture while locked, so it fails FR-022 and SC-008). TypeScript inside the Flutter app (WebView or an embedded JavaScript engine) was also rejected: it adds a runtime and battery cost, and it would be a third copy of shared logic.
- **Decision record (2026-11-18)**: Itai chose a Flutter-only spike and updated MISSION step 6 to match. There's no React Native comparison.
- **Spike (first Phase 1 task)**: a Flutter iOS app streams 16 kHz PCM from a native `AVAudioEngine` tap over a platform channel into a WebSocket engine, and keeps running while locked.
  - Pass: the delay the app adds is ≤ 150 ms, and capture survives 10 min locked.
  - Fail: stop. Per the constitution, a different stack needs an amendment before any code is written.

## R-2 Engine candidates (MISSION Phase 0 step 3)

| Candidate | Kind | Why |
|---|---|---|
| Apple `SpeechAnalyzer` / `SFSpeechRecognizer` | on-device baseline | MISSION baseline and fallback candidate |
| Android `SpeechRecognizer` (on-device) | on-device baseline | MISSION baseline (R-12) |
| Agora RT-STT | cloud | Named in MISSION |
| Google Cloud STT streaming (`he-IL`) | cloud | Hebrew streaming |
| Azure AI Speech streaming (`he-IL`) | cloud | Hebrew plus language identification |
| Soniox or Speechmatics real-time | cloud | Advertised code-switching and live speaker labels (one is picked in R-2a) |
| faster-whisper + ivrit.ai Hebrew checkpoint, used as-is | local (Mac) | Privacy and offline; strongest Hebrew-specific option |

- MISSION asks for "2–3 cloud providers with Hebrew". Agora plus 2–3 of Google, Azure and Soniox/Speechmatics fills that.
- **R-2a (half a day, before any adapter)**: for each cloud candidate, record streaming Hebrew support, mixed-language support, speaker labels, price per hour, audio retention/training terms and opt-out, all with links and dates, in `vendor-check.md`.
  - Candidates that retain audio with no opt-out are dropped (FR-020).
  - The results fill the `privacy` and `cost` fields in `shared/engines.yaml`.

## R-3 Latency definitions: one definition, shared by both sides

- **Decision**: put these in `shared/pipeline.yaml` and implement them identically in `bench/metrics/latency.py` and `app/lib/session/latency.dart`, with both tested on the same fixture:
  - **Utterance**: a speech span from the shared Silero VAD (same model file and thresholds on both sides).
  - **Time to provisional** = arrival time of the first `partial` for the utterance − the utterance's VAD speech-onset time.
  - **Time to final** = arrival time of the last `final` covering the utterance − the utterance's VAD speech-offset time.
  - Reported as p50/p90 per session (app) or per clip/engine/language (harness).
- **Rationale**: the constitution requires the same latency definition everywhere, or benchmark numbers mean nothing for the app. Word-end times aren't known live, so a reference-based definition can't run in the app. Measuring from onset is *stricter* than SC-001's "after spoken", so passing it implies passing SC-001.
- **Feeding**: the harness feeds audio paced to the wall clock in 20 ms frames, with arrival times taken from an injected clock, so tests are deterministic.
- **Rejected**: word-end reference latency in the harness plus a VAD proxy in the app (two definitions, which the constitution forbids); engine-reported timestamps (not comparable across vendors).

## R-4 WER normalization (Hebrew/English/mixed)

- **Decision**: `jiwer` after shared normalization in `bench/metrics/normalize.py`:
  - lowercase, strip punctuation and niqqud, unify geresh/gershayim, fold final letters for comparison only, and map digits ↔ words using a small lexicon;
  - mixed clips are scored as a whole, and also split by the language tags on reference words;
  - CER is also reported for Hebrew.
- **Documented** in `contracts/bench-cli.md` (XVI). These rules are harness-only and not needed in the app, so this isn't a DRY issue.

## R-5 VAD and noise suppression (MISSION: "mic → VAD/noise suppression → winning engine")

- **Decision, app (required)**: native `AVAudioEngine` with `setVoiceProcessingEnabled(true)` (OS noise suppression, implementation ladder rung 2) → the `SpeechGate` running the shared Silero VAD ONNX in Dart via `onnxruntime`. Only speech frames plus padding reach the engine.
- **Decision, harness**: cleanup variants are `none`, `rnnoise`, `deepfilternet` and `voiceproc` (the same Apple voice processing, run through the Swift helper on the Mac). Each runs with the VAD gate on and off, so the pipeline the app ships is benchmarked (MISSION Phase 0 step 4).
- **Rationale**: VAD is part of the mission's mandated pipeline. It defines utterances for latency (R-3) and is the main protection against made-up text on silence (SC-004).
- **Shared**: VAD thresholds and padding live in `shared/pipeline.yaml`. Tuning changes that file only.
- **Test fixture decision (Principle IV)**: the Silero ONNX file is committed, pinned by sha256, and small (about 2 MB). It counts as a **checked-in fixture**, not a "downloaded model weight": tests never fetch it at run time, and it never changes without a commit. The large models (faster-whisper/ivrit.ai) stay out of unit tests and are stubbed.

## R-6 Background capture on iOS (FR-022)

- **Decision**:
  - `UIBackgroundModes: audio`.
  - `AVAudioSession` category `.playAndRecord`, mode chosen by the spike (`.voiceChat` or `.measurement`).
  - Interruptions and route changes become `paused_mic` / resume events.
  - Permissions requested: microphone only (XIV).
- **Risk**: WebSocket traffic while locked is part of the spike.

## R-7 Offline fallback (FR-024; MISSION constraint "OS built-in … fallback")

- **Decision**: a `FallbackController` triggers on a `health: lost` event, a socket error, or no events for 2 s during VAD speech. It then:
  1. starts the fallback adapter and replays a 5 s RAM ring buffer of gated frames;
  2. drops the failed engine's open provisional text;
  3. keeps fallback finals from the replay point onward;
  4. shows the badge;
  5. switches back at the next VAD pause once the connection is healthy.

  Every switch is recorded in the session stats (XII).
- **Constraint check**: the ring buffer is RAM only (FR-018). Reconnecting doesn't lose or duplicate speech (XV).

## R-8 Speaker-change markers (FR-006, SC-005)

- **Decision**: use the engine's streaming speaker labels, converted to change markers. **The heuristic is not built up front (YAGNI).** It's added only if the active engine chosen in `decision.md` lacks speaker labels or the benchmark shows recall < 80%. If it's built, its thresholds go in `shared/pipeline.yaml`, and both sides are tested on the same fixture.

## R-9 Lock-screen start (FR-011, SC-008)

- **Decision**: an iOS `ControlWidget` plus a `StartCaptionsIntent` App Intent that opens the app with the session starting. One tap plus Face ID is within 2 taps.

## R-10 Secrets and keys (XIII, XIV)

- **Decision**:
  - Harness keys come from env vars in a gitignored `bench/.env`.
  - App keys are entered in settings and stored in the Keychain.
  - **The harness and the app use separate keys**, each scoped as narrowly as the provider allows.
  - No keys in `shared/`, logs, or commits.
- **Accepted risk**: keys on the device can be extracted on a jailbroken phone. This is acceptable for a personal app with the optional cap.

## R-11 Consent and legality

- **Decision**: clip metadata must include `consent: true` and a date. The harness refuses clips without it.
- Before committing to a cloud engine, Itai checks the Israeli rules for live, unrecorded personal captioning. This is not legal advice.

## R-12 Android on-device baseline in Phase 0 (MISSION step 3)

- **Decision**: a minimal Kotlin helper app in `bench/tools/android-speech/`, run on an Android device or emulator.
  - It accepts PCM over an `adb forward` TCP socket, feeds it to the on-device `SpeechRecognizer` (`EXTRA_PREFER_OFFLINE`), and writes schema events back as JSONL.
  - **Requires Android 13+ (API 33)**: streamed audio is fed through `RecognizerIntent.EXTRA_AUDIO_SOURCE` (a `ParcelFileDescriptor` pipe). Older versions only accept the live mic. Use a device or emulator image with API ≥ 33, and record the version in `lessons.md`.
  - `bench/src/itabench/engines/android_speech.py` wraps it.
- **Rationale**: this is the only way to benchmark the Android OS engine with the same clips and timing.
- **Limitation, recorded**: emulator results reflect the emulator's recognizer version. A real device (e.g., grandma's phone, with consent) is preferred.

## R-13 Tooling and gates (II, III, Quality Gates)

- **Decision**:
  - `bench/pyproject.toml` has `[tool.ruff]` selecting at least `E,F,UP,SIM,C4,PTH,RET,PIE,PERF,E722,BLE,TRY`, plus `ANN` (annotations required, Principle II) and `D` with `pydocstyle.convention = "google"` (docstrings, Principle XVI; `D` relaxed for `tests/` only), and `[tool.ty]`.
  - `app/analysis_options.yaml` enables strict-casts/inference/raw-types and `avoid_catches_without_on_clauses`, `prefer_final_locals`, `prefer_const_constructors`, `avoid_print`, plus `always_declare_return_types`, `type_annotate_public_apis` (II) and `public_member_api_docs` (XVI).
  - `.pre-commit-config.yaml` has pinned hooks.
  - `.github/workflows/ci.yml` uses `contents: read`, pinned actions and no secrets, and runs pre-commit, `uv run pytest` and `flutter test`, plus `swift test` (Apple helper) and `xcodebuild test` (iOS `RunnerTests`) on a pinned macOS runner, and `./gradlew test` (Android helper) on Linux with a pinned JDK. Each native job is skipped until its directory exists.

## R-14 Language change mid-session (FR-004; caption-screen contract)

- **Decision**: changing the language mode applies at the next VAD pause. The session controller calls `finish()` on the current adapter and `open()`s a new one with the new mode. Segments continue in the same session. No new contract operation is added (KISS).

## R-15 Result storage, reproducibility, failure isolation (XII, XV, constraints)

- **Decision**:
  - Results go to `bench/results/<engine>/<cleanup>/<vad>/<clip>.json`, and a re-run overwrites the file.
  - Each result records the clip file hash, engine id, model/API version reported by the adapter, cleanup, VAD on/off, `shared/` file hashes, harness version and run time.
  - One clip × engine failure is logged and counted, and the run continues. At the end it logs processed/succeeded/skipped/failed counts and exits non-zero if anything failed.
  - `report` aggregates whatever results are current.

## R-16 Who sets thresholds (XI)

- **Decision**: `itabench report` shows per-language WER/CER distributions and latencies. It does **not** propose thresholds. Itai chooses the engines, the mic decision and the SC-003 thresholds, and records them in `decision.md` with the report numbers cited. Only then are they copied into `spec.md`.

## R-17 Hebrew fallback contingency (FR-024)

- **Decision**: the Apple baseline run (R-2) records whether `he-IL` on-device recognition is available.
  - If it isn't, `decision.md` records that Hebrew sessions show `paused_offline` on connection loss (the spec edge case allows this).
  - An on-device Hebrew Whisper fallback stays post-v1.

## R-18 Battery-low warning (spec edge case)

- **Decision**: warn when estimated time remaining is under 20 minutes at the session's measured drain rate, or the battery is ≤ 10%. The threshold lives in `shared/pipeline.yaml` (XI).
