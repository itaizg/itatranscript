# Contract: Engine Profiles (`shared/engines.yaml`)

The harness and the app share this file. It has no secrets. Both sides parse it into the `EngineProfile` model.

```yaml
version: 1
engines:
  - id: google-stt-he          # unique, kebab-case
    display_name: Google STT
    adapter: google_streaming  # adapter registry key
    runs_on: cloud             # cloud | device | mac (bench-only)
    platforms: [ios, bench]    # where an adapter exists
    languages: [he, en]        # supported language modes; `auto` requires more than one language
    supports_code_switching: false
    supports_speaker_changes: false
    can_be_fallback: false     # requires runs_on: device
    cost_usd_per_hour: 1.44    # from vendor-check.md; 0 for device
    privacy:
      retains_audio: false
      trains_on_audio: false
      opt_out_required: true
      terms_source: vendor-check.md#google
      terms_checked_on: 2026-11-19
    options: {}                # adapter-specific (model, region, endpointing)
```

## Validation (enforced by both loaders and tested on both sides)

- `runs_on: device` requires `cost_usd_per_hour: 0`.
- `can_be_fallback: true` requires `runs_on: device`.
- **Privacy gate (FR-020)**: a profile with `retains_audio: true`, or with `trains_on_audio: true` and no confirmed opt-out, can't be opened. The app shows the reason, and the harness skips it and counts the skip.
- An unknown `adapter` is an error at load time.
- The values shown are placeholders until `vendor-check.md` (R-2a) exists.
