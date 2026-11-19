# Vendor check (R-2a, task T011)

Accessed **2026-11-19**. Facts come from vendor docs fetched that day; where a page did not state something it says **not stated** (never guessed). Prices are list prices in USD. Re-check before relying on any row. This is not legal advice.

| | Agora RT-STT | Google STT (Chirp 3, V2) | Azure Speech | Soniox real-time | Speechmatics real-time |
|---|---|---|---|---|---|
| Streaming Hebrew | Yes, `he-IL` listed | Yes, `iw-IL`, **Preview** | Yes, `he-IL` real-time | Yes, `he` | Hebrew listed; real-time mode **not stated** |
| Mixed Hebrew/English | Up to 2 languages per channel with language ID (extra $5.00/1000 min) | Auto-detect GA; Hebrew inclusion **not stated** | Continuous language ID; **not per word**; he-IL support **not stated** | Yes: per-token language ID in real-time (tags may be revised) | No English+Hebrew pack; Hebrew via auto-switch models, **not confirmed** |
| Live speaker labels | Per-UID only (one stream per person), no diarization | **No** diarization in streaming | Real-time diarization available (add-on, price **not stated**) | Yes, real-time `speaker` per token (less accurate than async) | Yes, included in real-time |
| Price per hour | $16.99/1000 min = **$1.02** | $0.016/min = **$0.96** (V2 standard row; Chirp 3 row **not confirmed**) | **Not stated** on rendered page (placeholders) | **$0.12** | Standard **$0.45**, Enhanced **$0.80** |
| Audio retention | Real-time streaming data "not stored"; transcripts **not stated** | Not logged by default | Real-time: processed in memory, nothing stored at rest | Real-time not stored | Retention period **not stated** |
| Training on audio | **Not stated** | Only if project opts in to data logging | Not used / not stated as used | No (policy says customer content is not used) | Opt-in toggle in portal; default position **not stated** |
| Opt-out | n/a / ask privacy@agora.io | Default is already off | n/a | n/a | Switch the portal toggle off |

## Sources (all accessed 2026-11-19)

- Agora: [pricing](https://docs.agora.io/en/real-time-stt/overview/pricing), [supported languages](https://docs.agora.io/en/real-time-stt/develop/supported-languages), [overview](https://docs.agora.io/en/real-time-stt/overview/product-overview), [processor privacy statement](https://www.agora.io/en/agora-processor-privacy-statement/)
- Google: [Chirp 3](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3), [pricing](https://cloud.google.com/speech-to-text/pricing), [data logging](https://docs.cloud.google.com/speech-to-text/docs/data-logging)
- Azure: [language support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt), [language identification](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-identification), [data privacy](https://learn.microsoft.com/en-us/azure/foundry/responsible-ai/speech-service/speech-to-text/data-privacy-security), [pricing](https://azure.microsoft.com/en-us/pricing/details/speech/)
- Soniox: [pricing](https://soniox.com/pricing), [languages](https://docs.soniox.com/stt/concepts/supported-languages), [diarization](https://docs.soniox.com/stt/concepts/speaker-diarization), [language ID](https://docs.soniox.com/stt/concepts/language-identification), [security and privacy](https://soniox.com/docs/security-and-privacy), [privacy policy](https://soniox.com/policies/privacy-policy)
- Speechmatics: [pricing](https://www.speechmatics.com/pricing.md), [languages](https://docs.speechmatics.com/speech-to-text/languages), [data retention terms](https://www.speechmatics.com/legal/data-retention-terms)
- Apple and Android on-device, faster-whisper: no network, no vendor terms (audio stays on the device or Mac).

## Findings

- **Privacy gate (FR-020):** no candidate is shown to retain audio with no opt-out, so none is dropped. Agora's transcript retention and training terms and Speechmatics' retention are **not stated**; these are open questions, not clearances.
- **Soniox vs Speechmatics (decision for T041):** Soniox. It is the only vendor with per-token language ID in real-time and explicit no-store/no-train wording, and it costs about a quarter as much. Speechmatics' profile and adapter slot are removed.
- **Hebrew caveats:** Google's Hebrew is Preview and uses `iw-IL`, not `he-IL`. Azure's continuous language ID doesn't switch inside a sentence.
- **Unknowns to settle before relying on them:** Azure price per hour and Hebrew language ID; Google Chirp 3 streaming price; Agora transcript retention and training. Any of these can be asked of the vendor in writing.
- Soniox's own comparison pages are marketing and were not used as evidence.
