import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

from itabench.engines.android_speech import AndroidSpeechEngine
from itabench.engines.fake import load_events
from itabench.models import AudioFrame, ClosedEvent, ErrorEvent, FinalEvent
from itabench.profiles import load_engines


@asynccontextmanager
async def helper(reply: bytes) -> AsyncGenerator[tuple[int, list[bytes]]]:
    """A stand-in for the Android helper: reads PCM to EOF, then sends ``reply``."""
    received: list[bytes] = []

    async def serve(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        received.append(await reader.readline())
        received.append(await reader.read())
        writer.write(reply)
        await writer.drain()
        writer.close()

    server = await asyncio.start_server(serve, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    try:
        yield port, received
    finally:
        server.close()
        await server.wait_closed()


async def _run(port: int, mode: str) -> list:  # noqa: ANN401
    profile = load_engines()["android-ondevice"]
    profile = profile.model_copy(update={"options": {"port": port}})
    engine = AndroidSpeechEngine()
    await engine.open(profile, mode, {})
    for seq in range(3):
        await engine.push_audio(AudioFrame(seq=seq, t_ms=seq * 20, pcm=b"\x01\x00" * 320))
    await engine.finish()
    return [event async for event in engine.events()]


async def test_helper_lines_become_events_and_audio_reaches_the_helper(shared: Path) -> None:
    fixture = shared / "fixtures/native/android-partial-then-final.events.jsonl"
    async with helper(fixture.read_bytes()) as (port, received):
        events = await _run(port, "he")
    assert events == list(load_events(fixture))
    assert sum(isinstance(e, FinalEvent) for e in events) == 1
    assert received[0] == b"locale=he-IL\n"
    assert len(received[1]) == 3 * 640


async def test_error_fixture_is_mapped(shared: Path) -> None:
    fixture = shared / "fixtures/native/android-error.events.jsonl"
    async with helper(fixture.read_bytes()) as (port, _):
        events = await _run(port, "en")
    assert isinstance(events[0], ErrorEvent)
    assert events[0].code == "network"
    assert isinstance(events[-1], ClosedEvent)


async def test_garbage_from_the_helper_is_an_invalid_message_error() -> None:
    async with helper(b'{"type":"nonsense"}\nnot json\n') as (port, _):
        events = await _run(port, "auto")
    assert [e.code for e in events if isinstance(e, ErrorEvent)] == [
        "invalid_message",
        "invalid_message",
    ]
    assert isinstance(events[-1], ClosedEvent)
