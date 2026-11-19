# Mission Brief: Live Captions for Hard Listening Situations
18 Nov 2026 · Itai Zemah Goren · v3

**Mission:** Show the speech around me as near-real-time Hebrew and English text (including switching mid-sentence), so I can keep up with the conversation. It's for following along, not for taking notes.

## Goals
- **v1:** G1 noisy café (1–2 speakers) · G2 group of 3–6 · G3 in-person meetings and interviews.
- **Later:** G4 lectures (distant speaker, reverb) · G5 phone and video calls.
- **Users:** me on iPhone and Mac, plus my grandma, who needs a version simple enough to use without help.
- Choose the speech-to-text engine from benchmark results, and keep it swappable.

## Non-goals (v1)
- No audio played back into ears. No summaries, no translation, no LLM layer.
- No accounts, sync or sharing; each device runs on its own. No app store, no monetization.
- No full speaker labels; speaker-change markers are enough. No full-accuracy offline mode (v1 only has the lower-accuracy on-device fallback).

## Constraints
- **Platforms:** iOS first, then macOS and Android (grandma). Use one cross-platform codebase (Flutter is the lead candidate), with native plugins only where the OS forces it (lock-screen widget, background audio, OS speech engines).
- **OS built-in captions:** a benchmark baseline and fallback only, since you can't swap their model or change their UI.
- **Engine interface:** `audio in → {partial|final text, timestamps, speaker-change}`. The app and the benchmark harness both use it, and the engine is chosen in config.
- **Config, not code:** engine, language mode, API keys and an optional cost cap (none by default) all live in config, and the app shows estimated cost per hour.
- **UI:** one caption screen with three controls (start/stop, freeze, language). It needs a "simple mode" for grandma: huge text and a single button.
- **Privacy:** audio is never saved. Transcripts are saved only on request. Use only cloud providers whose terms say they don't keep or train on audio, and record test clips only with consent.

## Success criteria
| # | Criterion | Target |
|---|---|---|
| S1 | First partial text | ≤ 1 s (p90) |
| S2 | Final text | ≤ 2 s (p90) |
| S3 | Accuracy (WER), G1 and G2, scored per language | Set from the Phase 0 benchmark |
| S4 | Silence and clatter | No made-up text |
| S5 | Speaker-change markers | ≥ 80% of turn changes marked |
| S6 | Readability | Readable at arm's length; partial and final text look different |
| S7 | Battery | 2 h of use on ≤ 60% battery (iPhone) |
| S8 | Instant start | ≤ 2 taps / 3 s from lock screen |
| S9 | Grandma test (post-v1, with the Android build) | She starts it and follows a conversation without help |

**v1 is done when** S1–S8 pass and I've used it for real at least 5 times in G1 and G3.

## Next implementation steps
**Phase 0: Benchmark (about 1 week)**
1. Record 10–15 clips with consent (Hebrew, English, mixed; G1–G3, plus one lecture). Hand-correct the transcripts.
2. Write a harness (Mac CLI) that streams each clip in real time through the engine interface.
3. Write adapters for Apple and Android on-device speech (baselines), 2–3 cloud streaming providers with Hebrew (Agora RT-STT is one), and a Whisper/ivrit.ai streaming setup.
4. Record WER, time to first word, time to final and cost per hour, and add VAD + noise-suppression on/off as a variable.
5. **Output:** an engine per language, a decision on whether an external mic is needed, and locked S3 thresholds.

**Phase 1: MVP (1–2 weeks)**
6. Confirm Flutter with a 1-day spike: live mic streaming on iOS that keeps running while locked. If it fails, re-plan before writing app code.
7. Build the app and ship it on iOS first: mic → VAD/noise suppression → winning engine → caption screen, with config and a lock-screen widget. If the connection drops, switch automatically to the on-device engine (lower accuracy, with a visible badge).
8. Use it for real in G1 and G3, then measure S1–S8.

**Phase 2 and later:** Android build with simple mode for grandma, macOS build, external mic, speaker labels, call capture (G5), lectures (G4). After that: the LLM layer, transcript history.

## Risks
- Hebrew streaming quality, especially slang and code-switching. Phase 0 exists to answer this.
- The phone mic may be the bottleneck rather than the model, so hardware may matter more than software.
- iOS limits on background audio and battery; Android device variety (mics, battery savers) on grandma's phone.
