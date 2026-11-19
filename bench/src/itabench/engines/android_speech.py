r"""Android on-device recognition through the helper app (``bench/tools/android-speech``).

Run ``adb forward tcp:7777 tcp:7777`` first. The helper takes ``locale=<id>\n`` and then raw
16 kHz mono s16le PCM, and answers with schema events as JSON lines.
"""

import asyncio
import contextlib
from collections.abc import AsyncIterator

from pydantic import ValidationError

from itabench.contract import register
from itabench.models import (
    EVENT_ADAPTER,
    AudioFrame,
    ClosedEvent,
    EngineEvent,
    EngineProfile,
    ErrorEvent,
)

LOCALES = {"he": "he-IL", "en": "en-US"}


class AndroidSpeechEngine:
    """Streams audio to the Android helper over a forwarded TCP socket."""

    version = "android-speech helper (SpeechRecognizer, on-device)"

    def __init__(self) -> None:
        """Create an engine that is not connected yet."""
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._queue: asyncio.Queue[EngineEvent] = asyncio.Queue()
        self._task: asyncio.Task[None] | None = None
        self._closed_seen = False

    async def open(
        self, profile: EngineProfile, language_mode: str, secrets: dict[str, str]
    ) -> None:
        """Connect to the helper (``options.host``/``options.port``) and pick the locale."""
        del secrets
        host = str(profile.options.get("host", "127.0.0.1"))
        port = int(profile.options.get("port", 7777))
        locale = LOCALES.get(language_mode, str(profile.options.get("locale", "en-US")))
        self._reader, self._writer = await asyncio.open_connection(host, port)
        self._writer.write(f"locale={locale}\n".encode())
        await self._writer.drain()
        self._task = asyncio.create_task(self._read())

    async def _read(self) -> None:
        assert self._reader is not None
        while line := await self._reader.readline():
            text = line.decode("utf-8", errors="replace").strip()
            if not text:
                continue
            try:
                event = EVENT_ADAPTER.validate_json(text)
            except ValidationError as exc:
                event = ErrorEvent(
                    t_ms=0, code="invalid_message", message=str(exc)[:200], retryable=False
                )
            if isinstance(event, ClosedEvent):
                self._closed_seen = True
            await self._queue.put(event)
        if not self._closed_seen:
            await self._queue.put(ClosedEvent(t_ms=0))

    async def push_audio(self, frame: AudioFrame) -> None:
        """Send one frame."""
        assert self._writer is not None
        self._writer.write(frame.pcm)
        await self._writer.drain()

    async def finish(self) -> None:
        """Signal end of audio and wait for the helper's final events."""
        assert self._writer is not None
        self._writer.write_eof()
        if self._task is not None:
            await self._task

    async def cancel(self) -> None:
        """Drop the connection; ``events()`` still ends with ``closed``."""
        if self._writer is not None:
            self._writer.close()
            with contextlib.suppress(ConnectionError):
                await self._writer.wait_closed()
        if self._task is not None:
            await asyncio.gather(self._task, return_exceptions=True)

    async def events(self) -> AsyncIterator[EngineEvent]:
        """Yield events until ``closed``."""
        while True:
            event = await self._queue.get()
            yield event
            if isinstance(event, ClosedEvent):
                return


register("android_speech", AndroidSpeechEngine)
