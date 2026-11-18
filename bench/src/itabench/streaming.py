"""Real-time feeder: WAV file -> 20 ms frames paced by a clock -> engine -> events log."""

import asyncio
import wave
from pathlib import Path

from itabench.clock import Clock
from itabench.contract import EngineAdapter
from itabench.engines.fake import dump_event
from itabench.models import AudioFrame, EngineEvent, EngineProfile

FRAME_MS = 20
FRAME_BYTES = 640  # 20 ms of 16 kHz mono s16le
TAIL_SILENCE_MS = 5000


class AudioFormatError(ValueError):
    """The WAV file is not 16 kHz mono 16-bit PCM."""


def read_wav_pcm(path: Path) -> bytes:
    """Read raw PCM from a 16 kHz mono 16-bit WAV file."""
    with wave.open(str(path), "rb") as wav:
        if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) != (
            16000,
            1,
            2,
        ):
            msg = f"{path}: need 16 kHz mono 16-bit, got {wav.getparams()}"
            raise AudioFormatError(msg)
        return wav.readframes(wav.getnframes())


def split_frames(pcm: bytes, *, tail_silence_ms: int = 0) -> list[bytes]:
    """Cut PCM into 640-byte frames, zero-padding the last, plus optional silence."""
    pcm += b"\0" * (tail_silence_ms // FRAME_MS * FRAME_BYTES)
    if len(pcm) % FRAME_BYTES:
        pcm += b"\0" * (FRAME_BYTES - len(pcm) % FRAME_BYTES)
    return [pcm[i : i + FRAME_BYTES] for i in range(0, len(pcm), FRAME_BYTES)]


async def stream_frames(
    engine: EngineAdapter,
    profile: EngineProfile,
    frames: list[bytes],
    clock: Clock,
    *,
    language_mode: str = "auto",
) -> list[EngineEvent]:
    """Feed frames at real-time pace and return events stamped with arrival time (ms)."""
    await engine.open(profile, language_mode, {})
    t0 = clock.now_ms()
    arrived: list[EngineEvent] = []

    async def consume() -> None:
        arrived.extend(
            [
                event.model_copy(update={"t_ms": clock.now_ms() - t0})
                async for event in engine.events()
            ]
        )

    consumer = asyncio.create_task(consume())
    try:
        for seq, pcm in enumerate(frames):
            await clock.sleep_until(t0 + seq * FRAME_MS)
            await engine.push_audio(AudioFrame(seq=seq, t_ms=seq * FRAME_MS, pcm=pcm))
        await engine.finish()
        await consumer
    except BaseException:
        await engine.cancel()
        consumer.cancel()
        raise
    return arrived


async def stream_wav(
    engine: EngineAdapter,
    profile: EngineProfile,
    wav_path: Path,
    clock: Clock,
    out_path: Path,
    *,
    language_mode: str = "auto",
) -> list[EngineEvent]:
    """Stream a WAV (plus 5 s of trailing silence) and write the events log."""
    frames = split_frames(read_wav_pcm(wav_path), tail_silence_ms=TAIL_SILENCE_MS)
    events = await stream_frames(engine, profile, frames, clock, language_mode=language_mode)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("".join(dump_event(e) + "\n" for e in events), encoding="utf-8")
    return events
