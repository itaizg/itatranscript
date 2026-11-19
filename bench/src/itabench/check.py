"""``itabench check-engine``: a live conformance smoke test (never run by pytest or CI)."""

import logging
from collections.abc import Callable, Mapping
from pathlib import Path

from itabench.clock import Clock
from itabench.contract import EngineAdapter
from itabench.models import (
    ClosedEvent,
    EngineEvent,
    EngineProfile,
    ErrorEvent,
    FinalEvent,
    PartialEvent,
)
from itabench.profiles import assert_openable
from itabench.streaming import stream_wav

log = logging.getLogger(__name__)

ScenarioFactory = Callable[[EngineProfile, Clock, str], EngineAdapter]


def load_env(path: Path) -> dict[str, str]:
    """Read ``KEY=value`` lines from a ``.env`` file; missing file means no keys."""
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip().strip("'\"")
    return values


def conformance_problems(events: list[EngineEvent]) -> list[str]:
    """Check the engine-stream rules that every adapter must meet."""
    problems: list[str] = []
    closed = [i for i, e in enumerate(events) if isinstance(e, ClosedEvent)]
    if len(closed) != 1 or closed[0] != len(events) - 1:
        problems.append("`closed` must be emitted exactly once, as the last event")
    finalised: set[str] = set()
    for event in events:
        if isinstance(event, FinalEvent):
            if event.segment_id in finalised:
                problems.append(f"two finals for segment {event.segment_id}")
            finalised.add(event.segment_id)
        elif isinstance(event, PartialEvent) and event.segment_id in finalised:
            problems.append(f"partial after final for segment {event.segment_id}")
    return problems


async def check_engine(  # noqa: PLR0913
    profile: EngineProfile,
    clock: Clock,
    shared_dir: Path,
    work_dir: Path,
    *,
    factory: ScenarioFactory,
    secrets: Mapping[str, str],
) -> list[str]:
    """Stream speech then silence; return the problems found (empty means pass)."""
    assert_openable(profile)
    problems: list[str] = []
    for scenario, wav in (("speech", "speech-short.wav"), ("silence", "silence-5s.wav")):
        engine = factory(profile, clock, scenario)
        events = await stream_wav(
            engine,
            profile,
            shared_dir / "fixtures" / wav,
            clock,
            work_dir / f"{profile.id}-{scenario}.events.jsonl",
            secrets=secrets,
        )
        problems += [f"{scenario}: {p}" for p in conformance_problems(events)]
        errors = [e for e in events if isinstance(e, ErrorEvent)]
        problems += [f"{scenario}: error {e.code}: {e.message}" for e in errors]
        if scenario == "silence":
            text = [e for e in events if isinstance(e, FinalEvent) and e.text.strip()]
            if text:
                problems.append(f"silence produced {len(text)} final text event(s)")
    for problem in problems:
        log.error("%s: %s", profile.id, problem)
    return problems
