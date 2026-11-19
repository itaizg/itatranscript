import logging
from pathlib import Path

import pytest
from conftest import InstantClock, make_clip
from typer.testing import CliRunner

from itabench import cli
from itabench.clock import Clock
from itabench.contract import EngineAdapter
from itabench.engines.fake import FakeEngine, load_events
from itabench.models import AudioFrame, EngineProfile
from itabench.profiles import SHARED_DIR, load_engines, load_pipeline
from itabench.results_store import ResultsStore
from itabench.run import run_all


class ExplodingEngine(FakeEngine):
    """Fails on the third frame, mid-clip."""

    async def push_audio(self, frame: AudioFrame) -> None:
        if frame.seq == 2:
            msg = "boom"
            raise RuntimeError(msg)
        await super().push_audio(frame)


def _profiles() -> list[EngineProfile]:
    fake = load_engines()["fake"]
    return [fake.model_copy(update={"id": name}) for name in ("ok-a", "bad", "ok-b")]


def _factory(profile: EngineProfile, clock: Clock, scenario: str = "speech") -> EngineAdapter:
    del scenario
    log = load_events(SHARED_DIR / "fixtures/partial-then-final.events.jsonl")
    return (ExplodingEngine if profile.id == "bad" else FakeEngine)(log, clock)


async def test_one_failing_engine_does_not_stop_the_others(
    shared: Path, tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    config = load_pipeline()
    store = ResultsStore(tmp_path / "results")
    with caplog.at_level(logging.INFO, logger="itabench"):
        counts = await run_all(
            profiles=_profiles(),
            clips=[make_clip(tmp_path / "data", shared)],
            cleanups=["none"],
            vads=["on"],
            config=config,
            model_path=shared / config.vad.model,
            store=store,
            clock_factory=InstantClock,
            factory=_factory,
        )
    assert (counts.processed, counts.succeeded, counts.failed) == (3, 2, 1)
    assert "processed=3 succeeded=2 skipped=0 failed=1" in caplog.text
    assert counts.exit_code() == 1
    assert [p.parent.parent.parent.name for p in store.files("events.jsonl")] == ["ok-a", "ok-b"]


async def test_rerun_overwrites_one_result(shared: Path, tmp_path: Path) -> None:
    config = load_pipeline()
    store = ResultsStore(tmp_path / "results")
    for _ in range(2):
        await run_all(
            profiles=_profiles()[:1],
            clips=[make_clip(tmp_path / "data", shared)],
            cleanups=["none"],
            vads=["on"],
            config=config,
            model_path=shared / config.vad.model,
            store=store,
            clock_factory=InstantClock,
            factory=_factory,
        )
    assert len(store.files("events.jsonl")) == 1


async def test_privacy_gated_engine_is_skipped_and_counted(shared: Path, tmp_path: Path) -> None:
    config = load_pipeline()
    gated = _profiles()[0].model_copy(
        update={"privacy": _profiles()[0].privacy.model_copy(update={"retains_audio": True})}
    )
    counts = await run_all(
        profiles=[gated],
        clips=[make_clip(tmp_path / "data", shared)],
        cleanups=["none"],
        vads=["on", "off"],
        config=config,
        model_path=shared / config.vad.model,
        store=ResultsStore(tmp_path / "results"),
        clock_factory=InstantClock,
        factory=_factory,
    )
    assert (counts.processed, counts.skipped, counts.failed) == (2, 2, 0)
    assert counts.exit_code() == 1  # everything skipped is not a success


def test_cli_exits_non_zero_when_an_item_fails(
    shared: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    make_clip(tmp_path / "data", shared)
    monkeypatch.setattr(cli, "CLOCK_FACTORY", InstantClock)
    monkeypatch.setattr(cli, "ENGINE_FACTORY", _factory)
    monkeypatch.setattr(cli, "load_env", lambda _path: {})
    args = [
        "run",
        "--cleanup",
        "none",
        "--vad",
        "on",
        "--data-dir",
        str(tmp_path / "data"),
        "--results-dir",
        str(tmp_path / "results"),
    ]
    runner = CliRunner()
    assert runner.invoke(cli.app, [*args, "--engines", "fake"]).exit_code == 0
    monkeypatch.setattr(cli, "load_engines", lambda: {p.id: p for p in _profiles()})
    assert runner.invoke(cli.app, [*args, "--engines", "ok-a,bad,ok-b"]).exit_code == 1
