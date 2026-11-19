from pathlib import Path

import pytest
from conftest import InstantClock
from typer.testing import CliRunner

from itabench import cli
from itabench.engines.factory import build_engine

COMMANDS = ("align", "run", "score", "report", "check-engine")


def test_help_lists_all_commands() -> None:
    result = CliRunner().invoke(cli.app, ["--help"])
    assert result.exit_code == 0
    assert all(name in result.output for name in COMMANDS)


def test_check_engine_fake_passes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(cli, "CLOCK_FACTORY", InstantClock)
    monkeypatch.setattr(cli, "BENCH_DIR", tmp_path)
    monkeypatch.setattr(cli, "ENGINE_FACTORY", build_engine)
    result = CliRunner().invoke(cli.app, ["check-engine", "fake"])
    assert result.exit_code == 0, result.output


def test_check_engine_fails_when_silence_produces_text(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(cli, "CLOCK_FACTORY", InstantClock)
    monkeypatch.setattr(cli, "BENCH_DIR", tmp_path)
    monkeypatch.setattr(
        cli, "ENGINE_FACTORY", lambda profile, clock, _scenario: build_engine(profile, clock)
    )
    result = CliRunner().invoke(cli.app, ["check-engine", "fake"])
    assert result.exit_code == 1


def test_unknown_engine_is_rejected() -> None:
    assert CliRunner().invoke(cli.app, ["check-engine", "nope"]).exit_code == 2
