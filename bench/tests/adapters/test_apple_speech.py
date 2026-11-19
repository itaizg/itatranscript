import stat
from pathlib import Path

from itabench.engines.apple_speech import AppleSpeechEngine
from itabench.engines.fake import load_events
from itabench.models import AudioFrame, ClosedEvent, ErrorEvent, FinalEvent
from itabench.profiles import load_engines


def _stub_helper(tmp_path: Path, body: str) -> Path:
    path = tmp_path / "helper.sh"
    path.write_text(f"#!/bin/sh\ncat > /dev/null\n{body}\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


async def _run(tmp_path: Path, body: str) -> list:  # noqa: ANN401
    profile = load_engines()["apple-ondevice"]
    profile = profile.model_copy(update={"options": {"helper": str(_stub_helper(tmp_path, body))}})
    engine = AppleSpeechEngine()
    await engine.open(profile, "en", {})
    for seq in range(3):
        await engine.push_audio(AudioFrame(seq=seq, t_ms=seq * 20, pcm=b"\0" * 640))
    await engine.finish()
    return [event async for event in engine.events()]


async def test_helper_output_becomes_events(shared: Path, tmp_path: Path) -> None:
    fixture = shared / "fixtures/native/apple-partial-then-final.events.jsonl"
    events = await _run(tmp_path, f"cat '{fixture}'")
    assert events == list(load_events(fixture))
    assert sum(isinstance(e, FinalEvent) for e in events) == 1
    assert isinstance(events[-1], ClosedEvent)


async def test_invalid_helper_line_becomes_an_error_event(tmp_path: Path) -> None:
    events = await _run(tmp_path, 'echo \'{"type":"nonsense"}\'')
    assert isinstance(events[0], ErrorEvent)
    assert events[0].code == "invalid_message"
    assert isinstance(events[-1], ClosedEvent)


async def test_helper_exiting_without_closed_still_ends_the_stream(tmp_path: Path) -> None:
    events = await _run(tmp_path, "true")
    assert [type(e) for e in events] == [ClosedEvent]
