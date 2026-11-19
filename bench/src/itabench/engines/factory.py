"""Build an engine adapter for a profile."""

import importlib
from pathlib import Path

from itabench.clock import Clock
from itabench.contract import EngineAdapter, create
from itabench.engines.fake import FakeEngine, load_events
from itabench.models import EngineProfile
from itabench.profiles import SHARED_DIR


class AdapterUnavailableError(RuntimeError):
    """The adapter module for a profile is not implemented or not installed."""


def build_engine(profile: EngineProfile, clock: Clock, scenario: str = "speech") -> EngineAdapter:
    """Create the adapter named by ``profile.adapter``.

    The ``fake`` adapter replays ``options.log`` (a path under ``shared/``), which
    defaults to the ``partial-then-final`` fixture; the ``silence`` scenario replays
    ``options.log_silence`` (default: a log with no text). Other adapters live in
    ``itabench.engines.<adapter>`` and register themselves on import.
    """
    if profile.adapter == "fake":
        key, default = (
            ("log_silence", "fixtures/silence.events.jsonl")
            if scenario == "silence"
            else ("log", "fixtures/partial-then-final.events.jsonl")
        )
        log = str(profile.options.get(key, default))
        return FakeEngine(load_events(Path(SHARED_DIR) / log), clock)
    try:
        importlib.import_module(f"itabench.engines.{profile.adapter}")
    except ModuleNotFoundError as exc:
        msg = f"{profile.id}: adapter {profile.adapter!r} is not available ({exc.name})"
        raise AdapterUnavailableError(msg) from exc
    return create(profile.adapter)
