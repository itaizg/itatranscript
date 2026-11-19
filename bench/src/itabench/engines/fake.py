"""A fake engine that replays a recorded event log on an injected clock."""

import json
from collections.abc import AsyncIterator
from pathlib import Path

from itabench.clock import Clock
from itabench.contract import register
from itabench.models import (
    EVENT_ADAPTER,
    AudioFrame,
    ClosedEvent,
    EngineEvent,
    EngineProfile,
)


def load_events(path: Path) -> tuple[EngineEvent, ...]:
    """Parse an ``.events.jsonl`` file into events."""
    lines = path.read_text(encoding="utf-8").splitlines()
    return tuple(EVENT_ADAPTER.validate_json(line) for line in lines if line.strip())


class FakeEngine:
    """Replays events at their recorded ``t_ms`` offsets after ``open``."""

    version = "fake-1"

    def __init__(self, events: tuple[EngineEvent, ...], clock: Clock) -> None:
        """Create the engine from a log and a clock."""
        self._log = events
        self._clock = clock
        self._opened_at = 0
        self._cancelled = False
        self.frames_received = 0

    async def open(
        self, profile: EngineProfile, language_mode: str, secrets: dict[str, str]
    ) -> None:
        """Start the replay clock."""
        del profile, language_mode, secrets
        self._opened_at = self._clock.now_ms()

    async def push_audio(self, frame: AudioFrame) -> None:
        """Count frames; the fake ignores audio content."""
        del frame
        self.frames_received += 1

    async def finish(self) -> None:
        """Nothing to flush: the log already holds the finals."""

    async def cancel(self) -> None:
        """Stop the replay; ``events()`` ends with ``closed``."""
        self._cancelled = True

    async def events(self) -> AsyncIterator[EngineEvent]:
        """Yield each logged event when its time comes, or ``closed`` on cancel."""
        for event in self._log:
            await self._clock.sleep_until(self._opened_at + event.t_ms)
            if self._cancelled:
                break
            yield event
            if isinstance(event, ClosedEvent):
                return
        yield ClosedEvent(t_ms=self._clock.now_ms() - self._opened_at)


def _unconfigured() -> FakeEngine:
    msg = "construct FakeEngine directly with a log and clock"
    raise NotImplementedError(msg)


register("fake", _unconfigured)


def dump_event(event: EngineEvent) -> str:
    """Serialize an event as one JSON line."""
    return json.dumps(event.model_dump(mode="json", exclude_none=True), ensure_ascii=False)
