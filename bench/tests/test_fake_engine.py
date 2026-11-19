from pathlib import Path

from itabench.clock import FakeClock
from itabench.engines.fake import FakeEngine, load_events
from itabench.models import ClosedEvent, EngineEvent, EngineProfile, FinalEvent
from itabench.profiles import load_engines


async def _collect(
    engine: FakeEngine, clock: FakeClock, shared: Path, cancel_after: int | None
) -> list[EngineEvent]:
    profile: EngineProfile = load_engines(shared / "engines.yaml")["fake"]
    await engine.open(profile, "auto", {})
    seen = []
    async for ev in engine.events():
        seen.append(ev)
        if cancel_after is not None and len(seen) == cancel_after:
            await engine.cancel()
    return seen


async def test_partial_then_final_gives_one_final(shared: Path) -> None:
    clock = FakeClock()
    log = load_events(shared / "fixtures/partial-then-final.events.jsonl")
    seen = await clock.drive(_collect(FakeEngine(log, clock), clock, shared, None))
    finals = [e for e in seen if isinstance(e, FinalEvent)]
    assert len(finals) == 1
    assert isinstance(seen[-1], ClosedEvent)


async def test_nothing_follows_closed_after_cancel(shared: Path) -> None:
    clock = FakeClock()
    log = load_events(shared / "fixtures/cancel-midstream.events.jsonl")
    seen = await clock.drive(_collect(FakeEngine(log, clock), clock, shared, 1))
    assert isinstance(seen[-1], ClosedEvent)
    assert sum(isinstance(e, ClosedEvent) for e in seen) == 1
    assert len(seen) == 2
