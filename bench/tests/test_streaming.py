from pathlib import Path

import pytest

from itabench.clock import FakeClock
from itabench.engines.fake import FakeEngine, load_events
from itabench.profiles import load_engines
from itabench.streaming import (
    AudioFormatError,
    read_wav_pcm,
    split_frames,
    stream_frames,
    stream_wav,
)


def test_split_frames_pads_and_adds_tail() -> None:
    frames = split_frames(b"\1" * 700, tail_silence_ms=40)
    assert all(len(f) == 640 for f in frames)
    assert len(frames) == 2 + 2


def test_wrong_format_rejected(tmp_path: Path) -> None:
    import wave

    p = tmp_path / "bad.wav"
    with wave.open(str(p), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b"\0" * 400)
    with pytest.raises(AudioFormatError):
        read_wav_pcm(p)


async def test_events_arrive_at_expected_times(shared: Path) -> None:
    clock = FakeClock()
    log = load_events(shared / "fixtures/latency-basic.events.jsonl")
    profile = load_engines(shared / "engines.yaml")["fake"]
    engine = FakeEngine(log, clock)
    frames = split_frames(b"\0" * 640 * 10)
    events = await clock.drive(stream_frames(engine, profile, frames, clock))
    assert [e.t_ms for e in events] == [e.t_ms for e in log]
    assert engine.frames_received == 10


async def test_stream_wav_writes_log(shared: Path, tmp_path: Path) -> None:
    clock = FakeClock()
    log = load_events(shared / "fixtures/partial-then-final.events.jsonl")
    profile = load_engines(shared / "engines.yaml")["fake"]
    out = tmp_path / "x.events.jsonl"
    await clock.drive(
        stream_wav(
            FakeEngine(log, clock),
            profile,
            shared / "fixtures/speech-short.wav",
            clock,
            out,
        )
    )
    assert len(out.read_text().splitlines()) == len(log)
