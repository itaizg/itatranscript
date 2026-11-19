"""Apple on-device recognition through the Swift helper (``bench/tools/apple-speech``)."""

import asyncio
import contextlib
from asyncio.subprocess import Process
from collections.abc import AsyncIterator
from pathlib import Path

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
from itabench.paths import REPO_ROOT

DEFAULT_HELPER = (
    REPO_ROOT / "bench" / "tools" / "apple-speech" / ".build" / "release" / "apple-speech"
)
LOCALES = {"he": "he-IL", "en": "en-US"}


class AppleSpeechEngine:
    """Runs ``apple-speech recognize`` and turns its JSON lines into events."""

    version = "apple-speech helper (SFSpeechRecognizer, on-device)"

    def __init__(self) -> None:
        """Create an engine that has not started the helper yet."""
        self._proc: Process | None = None
        self._queue: asyncio.Queue[EngineEvent] = asyncio.Queue()
        self._reader: asyncio.Task[None] | None = None
        self._closed_seen = False

    async def open(
        self, profile: EngineProfile, language_mode: str, secrets: dict[str, str]
    ) -> None:
        """Start the helper for the language (``auto`` uses ``options.locale`` or en-US)."""
        del secrets
        helper = Path(str(profile.options.get("helper", DEFAULT_HELPER)))
        locale = LOCALES.get(language_mode, str(profile.options.get("locale", "en-US")))
        self._proc = await asyncio.create_subprocess_exec(
            str(helper),
            "recognize",
            "--locale",
            locale,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
        )
        self._reader = asyncio.create_task(self._read())

    async def _read(self) -> None:
        assert self._proc is not None
        assert self._proc.stdout is not None
        async for raw in self._proc.stdout:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                event = EVENT_ADAPTER.validate_json(line)
            except ValidationError as exc:
                event = ErrorEvent(
                    t_ms=0, code="invalid_message", message=str(exc)[:200], retryable=False
                )
            if isinstance(event, ClosedEvent):
                self._closed_seen = True
            await self._queue.put(event)
        await self._proc.wait()
        if not self._closed_seen:
            await self._queue.put(ClosedEvent(t_ms=0))

    async def push_audio(self, frame: AudioFrame) -> None:
        """Pipe one frame to the helper."""
        assert self._proc is not None
        assert self._proc.stdin is not None
        self._proc.stdin.write(frame.pcm)
        await self._proc.stdin.drain()

    async def finish(self) -> None:
        """Close stdin so the helper flushes its finals and exits."""
        assert self._proc is not None
        assert self._proc.stdin is not None
        self._proc.stdin.close()
        if self._reader is not None:
            await self._reader

    async def cancel(self) -> None:
        """Kill the helper; ``events()`` still ends with ``closed``."""
        if self._proc is not None and self._proc.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                self._proc.kill()
        if self._reader is not None:
            await asyncio.gather(self._reader, return_exceptions=True)

    async def events(self) -> AsyncIterator[EngineEvent]:
        """Yield events until ``closed``."""
        while True:
            event = await self._queue.get()
            yield event
            if isinstance(event, ClosedEvent):
                return


register("apple_speech", AppleSpeechEngine)
