"""Injectable clocks so tests never sleep (constitution IV)."""

import asyncio
import heapq
import time
from collections.abc import Awaitable
from typing import Protocol


class Clock(Protocol):
    """Monotonic millisecond clock that can wait until a deadline."""

    def now_ms(self) -> int:
        """Return the current time in milliseconds."""
        ...

    async def sleep_until(self, deadline_ms: int) -> None:
        """Wait until ``now_ms() >= deadline_ms``."""
        ...


class SystemClock:
    """Real wall-clock time."""

    def now_ms(self) -> int:
        """Return monotonic milliseconds."""
        return time.monotonic_ns() // 1_000_000

    async def sleep_until(self, deadline_ms: int) -> None:
        """Sleep for real until the deadline."""
        delay = (deadline_ms - self.now_ms()) / 1000
        if delay > 0:
            await asyncio.sleep(delay)


class FakeClock:
    """Manual clock: time moves only through ``advance`` or ``drive``."""

    def __init__(self, start_ms: int = 0) -> None:
        """Create a clock at ``start_ms``."""
        self._now = start_ms
        self._waiters: list[tuple[int, int, asyncio.Future[None]]] = []
        self._counter = 0

    def now_ms(self) -> int:
        """Return the fake current time."""
        return self._now

    async def sleep_until(self, deadline_ms: int) -> None:
        """Wait until the fake time reaches the deadline."""
        if deadline_ms <= self._now:
            await asyncio.sleep(0)
            return
        future: asyncio.Future[None] = asyncio.get_running_loop().create_future()
        self._counter += 1
        heapq.heappush(self._waiters, (deadline_ms, self._counter, future))
        await future

    def advance(self, ms: int) -> None:
        """Move time forward and wake every waiter that is now due."""
        self._now += ms
        self._release_due()

    def _release_due(self) -> None:
        while self._waiters and self._waiters[0][0] <= self._now:
            _, _, future = heapq.heappop(self._waiters)
            if not future.done():
                future.set_result(None)

    async def drive[T](self, awaitable: Awaitable[T]) -> T:
        """Run ``awaitable``, jumping time to the next deadline whenever all tasks wait."""
        task = asyncio.ensure_future(awaitable)
        while not task.done():
            for _ in range(10):
                await asyncio.sleep(0)
            if task.done():
                break
            if self._waiters:
                self._now = max(self._now, self._waiters[0][0])
                self._release_due()
        return task.result()
