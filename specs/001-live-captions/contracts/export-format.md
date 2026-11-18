# Contract: Transcript Export (FR-019, FR-025)

Triggered only by the user from the caption screen's overflow menu or after stopping a session. It writes a UTF-8 `.txt` file to a temp directory, opens the iOS share sheet, and deletes the temp file when the share sheet closes. The app keeps no copy.

## File name

`captions-YYYY-MM-DD-HHmm.txt`

## Body

```text
# Captions – 2026-12-01 19:02 (1h 30m) · engine: google-stt-he · mode: auto

[00:00:04] שלום, מה נשמע?
[00:00:07] — speaker change —
[00:00:07] Fine thanks, ואיתך?
[00:20:03] (offline – lower accuracy)
[00:20:05] ...
```

- Only final segments are exported; provisional text is never included.
- The temp-file write and the share sheet are the trust boundary. A failure there produces a visible error, and the temp file is still removed by its single owner (VIII).
- Hebrew lines are written as plain text in logical order. Direction is left to the viewer app (no bidi control characters).
- Segments with `lang: unknown` are written as `[unrecognized]`.

## Test mode (FR-025)

When `test_mode` is on, the session's stats record ([session-stats.md](session-stats.md)) is appended after this line:

```text
--- session stats ---
{ ...single JSON object... }
```
