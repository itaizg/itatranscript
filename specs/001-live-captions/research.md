# Research: Live Captions for Hard Listening Situations

Phase 0 decisions for [plan.md](plan.md). Claims about each vendor's language support and data retention are **not yet verified**. Task R-2a checks them against current vendor docs before any adapter is written, and the benchmark settles quality.

## R-1 App stack

- **Decision**: Flutter app, with native Swift for the audio session, Apple speech and the Lock Screen widget, connected through platform channels.
- **Rationale**: MISSION needs iOS, then Android (grandma) and macOS, from one codebase. Flutter targets all three from stable tooling, and React Native's macOS support is weaker. The parts that are hard on iOS (background audio, voice processing, Apple speech, WidgetKit) are native code in either stack, so the cross-platform layer only has to carry UI, state and WebSocket engines. Flutter's UI performance suits a virtualized, fast-updating caption list.
- **Alternatives**: React Native (macOS is less mature, and the audio streaming bridge is no simpler); native Swift only (best iOS fit, but means rewriting for Android); PWA (no reliable background capture or lock-screen launch on iOS, so it fails FR-022 and SC-008).
- **Spike (1 day, first Phase 1 task)**: a Flutter iOS app that streams 16 kHz PCM from a native `AVAudioEngine` tap over a platform channel to a WebSocket engine, keeps running while locked, and measures the added delay. Exit: the delay added in the app is ≤ 150 ms and capture survives 10 min locked. If it fails, fall back to native Swift for v1.

## R-2 Engine candidates (benchmark set)

- **Decision**: benchmark these, all behind the engine contract:

  | Candidate | Kind | Why include |
  |---|---|---|
  | Apple `SpeechAnalyzer` / `SFSpeechRecognizer` | on-device / OS | Free baseline and the fallback candidate. Hebrew support on-device is unverified |
  | Agora RT-STT | cloud | Named in MISSION |
  | Google Cloud Speech-to-Text (streaming, `he-IL`) | cloud | Mature Hebrew support |
  | Azure AI Speech (streaming, `he-IL`) | cloud | Hebrew support and language identification |
  | Soniox or Speechmatics (real-time) | cloud | Advertised mid-sentence language switching and real-time speaker labels |
  | faster-whisper + ivrit.ai Hebrew fine-tune, streamed in chunks | local (Mac in Phase 0) | Privacy and offline use; the strongest Hebrew-specific option |

- **Rationale**: this covers each cost/privacy tier and the two hard features (code-switching, live speaker changes). Choose by data (G-2).
- **Alternatives**: Deepgram and AssemblyAI streaming. Include them only if R-2a confirms they support streaming Hebrew.
- **R-2a (half a day)**: for each cloud candidate, check streaming Hebrew support, mixed-language support, live speaker labels, price per hour, and data-retention/training terms (FR-020). Candidates that fail retention are dropped before any adapter is written.

## R-3 Measuring latency honestly

- **Decision**: the harness feeds audio at real time (20 ms frames, wall-clock paced). Reference transcripts get word-level timings from forced alignment, which are then spot-checked by hand.
  - *Time to first word* = when a provisional event first contains a reference word, minus that word's end time.
  - *Time to final* = when the final event covering an utterance arrives, minus the utterance's end time.
  - Report p50 and p90 for each engine, language and situation.
- **Rationale**: SC-001 and SC-002 are defined as "after spoken" and "after the speaker finishes". Faster-than-real-time feeding would hide engine buffering.
- **Alternatives**: engine-reported timestamps (not comparable across vendors); whole-utterance timing (hides partial behavior).

## R-4 WER for Hebrew, English and mixed speech

- **Decision**: use `jiwer` with these normalizations, all applied to both reference and engine output:
  - Lowercase.
  - Strip punctuation and Hebrew niqqud.
  - Unify geresh/gershayim.
  - Normalize final letters (ך/כ etc.) only for comparison.
  - Map digits ↔ words using a small lexicon.
  - Mixed clips are scored as a whole, and also split by language tag on the reference words.
  - Also report CER for Hebrew, since prefixes like ו/ה/ב/ל/מ/ש inflate WER.
- **Rationale**: without normalization, Hebrew WER mostly measures spelling conventions rather than recognition.

## R-5 Noise cleanup and VAD

- **Decision**: the harness benchmarks three cleanup variants: `none`, `rnnoise`, `deepfilternet`. Each runs with Silero VAD gating, plus one OS-like variant (Mac voice processing).
  - The app starts with Apple voice processing (`setVoiceProcessingEnabled(true)` on the input node), which is free and power-efficient. A Silero VAD gate is added only if the benchmark shows it reduces made-up text (SC-004) without raising time to first word.
- **Rationale**: voice processing costs nothing on iOS. VAD gating is the main defense against made-up text in silence (SC-004), but a bad gate cuts off first words.
- **Alternatives**: always shipping DeepFilterNet on-device costs battery, so use it only if the benchmark shows a large WER gain in the café clips.

## R-6 Background capture on iOS (FR-022)

- **Decision**: use the `audio` background mode and an `AVAudioSession` with category `.playAndRecord`, mode `.voiceChat`/`.measurement` (pick from the spike), and `.mixWithOthers` off. Keep the `AVAudioEngine` running, and handle interruptions (calls, Siri) by showing a "paused – mic in use" state and resuming.
- **Rationale**: this is the supported way to record while locked, and the red recording indicator is acceptable.
- **Risk**: WebSocket traffic in the background is allowed while audio is active, but needs testing (it's part of the spike).

## R-7 Offline fallback (FR-024)

- **Decision**: a `FallbackController` watches the network and engine health. On loss of network or engine (no events for 2 s while speech is detected, or a socket error), it:
  1. starts the fallback engine, fed from a 5 s rolling audio ring buffer in memory, so speech around the break isn't lost;
  2. tags the resulting segments `engine=fallback`;
  3. shows the badge;
  4. switches back at the next pause in speech after the network returns.

  To avoid duplicates, the provisional text of the failed engine is dropped, and only fallback finals from the replay point onward are kept.
- **Rationale**: this meets "no lost or duplicated speech" and the 3 s switch. The ring buffer lives in RAM only, so FR-018 holds.
- **Open**: whether Apple on-device recognition supports Hebrew. If not, the Hebrew fallback is a pause notice (spec edge case) until a local Whisper model runs on iOS (post-v1).

## R-8 Speaker-change markers (FR-006, SC-005)

- **Decision**: use the engine's streaming speaker labels where available, and turn them into change markers only (no names in v1). Engines without labels get a fallback heuristic: a gap of more than 600 ms plus a jump in pitch/energy-profile distance. The harness scores both against annotated turn changes.
- **Rationale**: the spec only needs markers (≥ 80% recall), and live speaker separation is immature.

## R-9 Lock-screen start (FR-011, SC-008)

- **Decision**: an iOS Control Center / Lock Screen control (`ControlWidget`) plus an App Intent that opens the app with the session already starting. Fallback: a Lock Screen widget that deep-links to start.
- **Rationale**: one tap on the control plus Face ID unlock meets "≤ 2 taps".

## R-10 Secrets and config

- **Decision**: `config/engines.yaml` holds the profiles with no secrets. API keys are entered in the app's settings and stored in the Keychain. The harness reads keys from environment variables (`.env`, gitignored).
- **Rationale**: single user, no backend. FR-013 needs switching without a rebuild.
- **Accepted risk**: keys on the device can be extracted from a jailbroken phone. That's acceptable for a personal, unreleased app with a spending cap.

## R-11 Legal/consent (spec assumption)

- **Decision**: Phase 0 records clips only with verbal or written consent, noted in the clip metadata (`consent: true`, date). Before committing to a cloud engine, check the Israeli privacy/eavesdropping rules for live, unrecorded captioning for personal accessibility. Owner: Itai. Not legal advice.
