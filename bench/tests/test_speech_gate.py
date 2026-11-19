from pathlib import Path

from itabench.models import AudioFrame
from itabench.profiles import load_pipeline
from itabench.speech_gate import SpeechGate
from itabench.streaming import read_wav_pcm, split_frames


def _run(shared: Path, wav: str, *, enabled: bool = True) -> tuple[int, SpeechGate]:
    gate = SpeechGate(
        load_pipeline(shared / "pipeline.yaml"),
        shared / "models/silero_vad.onnx",
        enabled=enabled,
    )
    passed = 0
    for i, pcm in enumerate(
        split_frames(read_wav_pcm(shared / "fixtures" / wav), tail_silence_ms=1000)
    ):
        passed += len(gate.push(AudioFrame(seq=i, t_ms=i * 20, pcm=pcm)))
    gate.finish()
    return passed, gate


def test_silence_passes_nothing(shared: Path) -> None:
    passed, gate = _run(shared, "silence-5s.wav")
    assert passed == 0
    assert gate.spans == []


def test_speech_gives_a_span(shared: Path) -> None:
    passed, gate = _run(shared, "speech-short.wav")
    assert passed > 0
    assert gate.spans
    assert gate.spans[0].onset_ms < 1000


def test_disabled_gate_passes_everything(shared: Path) -> None:
    passed, gate = _run(shared, "silence-5s.wav", enabled=False)
    assert passed == 5000 // 20 + 1000 // 20
    assert gate.spans == []
