"""Regenerate ``shared/fixtures/vad-probs.json`` (Silero probabilities + the gate's output).

The app's Dart ``SpeechGate`` replays these probabilities through its own state machine and must
produce the same spans and pass-through counts as the Python gate (research R-5).

Run: ``uv run python scripts/gen_vad_fixture.py``
"""

import json

from itabench.models import AudioFrame
from itabench.paths import REPO_ROOT
from itabench.profiles import load_pipeline
from itabench.speech_gate import SpeechGate
from itabench.streaming import read_wav_pcm, split_frames

TAIL_MS = 1000
CASES = {"speech-short": "speech-short.wav", "silence-5s": "silence-5s.wav"}


def build_case(wav: str) -> dict[str, object]:
    """Run the Python gate over one WAV (plus tail silence) and record everything."""
    shared = REPO_ROOT / "shared"
    config = load_pipeline()
    gate = SpeechGate(config, shared / config.vad.model, enabled=True)
    probs: list[float] = []
    original = gate._speech_prob  # noqa: SLF001 - capturing the model output is the point
    gate._speech_prob = lambda chunk: probs.append(original(chunk)) or probs[-1]  # noqa: SLF001
    passed = 0
    frames = split_frames(read_wav_pcm(shared / "fixtures" / wav), tail_silence_ms=TAIL_MS)
    for i, pcm in enumerate(frames):
        passed += len(gate.push(AudioFrame(seq=i, t_ms=i * 20, pcm=pcm)))
    gate.finish()
    return {
        "wav": wav,
        "tail_ms": TAIL_MS,
        "probs": [round(p, 6) for p in probs],
        "spans": [[s.onset_ms, s.offset_ms] for s in gate.spans],
        "frames_passed": passed,
    }


def main() -> None:
    """Write the fixture file."""
    out = REPO_ROOT / "shared" / "fixtures" / "vad-probs.json"
    data = {"chunk_samples": 512, "cases": {k: build_case(v) for k, v in CASES.items()}}
    out.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
