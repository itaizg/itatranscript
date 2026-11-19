# Lessons

Surprises, recorded as they happen (constitution XX).

## 2026-11-19

- **iCloud Drive hides the editable-install `.pth` file.** macOS flags `.venv/.../itabench.pth` as
  `hidden` (`ls -lO`), and Python 3.13 ignores hidden `.pth` files, so `uv run itabench` randomly
  fails with `ModuleNotFoundError`. Fix: install non-editable (`export UV_NO_EDITABLE=1`, with
  `cache-keys` rebuilding on `src/**/*.py`), and find the repo root at runtime
  (`itabench.paths`) instead of from the package file's location. pytest uses
  `pythonpath = ["src"]`. See `bench/README.md`.
- **Apple voice processing is rejected in manual (offline) rendering mode.**
  `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` followed by
  `enableManualRenderingMode(.offline, ...)` fails with CoreAudio error -80800 on macOS 26.6.
  Per T036 the `voiceproc` cleanup therefore uses the helper's `--loopback` mode (play the clip
  out loud, record it through the voice-processed mic). Loopback is **built but not yet run**:
  it needs speakers, a quiet room and microphone permission.
- **`he-IL` on-device recognition is available on this Mac** (`apple-speech availability` reports
  `on_device: true` for `he-IL` and `en-US`). This answers the R-17 question for macOS only;
  the iPhone must be checked separately in the T051 spike.
- **This Mac has only the Command Line Tools** (no Xcode): `xcodebuild`, `simctl`, XCTest and the
  Swift Testing macro plugin are all missing. So the Swift/XCTest tests (T036, and the iOS
  `RunnerTests` in T051/T079/T083) cannot run locally. The pure Swift logic in `AppleSpeechCore`
  was checked with a throwaway executable instead; the XCTest files are written and run in CI
  (macOS runner has Xcode).
- **Swift `.build/` was not git-ignored**; added to `.gitignore` with the other native build dirs.
