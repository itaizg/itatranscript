"""Shared test helpers."""

import asyncio
import shutil
from pathlib import Path

import pytest

from itabench.data import load_clip
from itabench.models import TestClip

SHARED = Path(__file__).resolve().parents[2] / "shared"


@pytest.fixture
def shared() -> Path:
    """Path to the repo's ``shared/`` directory."""
    return SHARED


class InstantClock:
    """A clock whose ``sleep_until`` jumps straight to the deadline (no waiting)."""

    def __init__(self) -> None:
        self._now = 0

    def now_ms(self) -> int:
        return self._now

    async def sleep_until(self, deadline_ms: int) -> None:
        self._now = max(self._now, deadline_ms)
        await asyncio.sleep(0)


def make_clip(data_dir: Path, shared: Path, clip_id: str = "c1", lang: str = "en") -> TestClip:
    """Write a consented clip (``speech-short.wav``) into ``data_dir/clips`` and load it."""
    clips = data_dir / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    shutil.copy(shared / "fixtures/speech-short.wav", clips / f"{clip_id}.wav")
    (clips / f"{clip_id}.yaml").write_text(
        f"situation: cafe\nlang: {lang}\nconsent: true\nconsent_date: 2026-01-01\n"
        "speakers: 1\nmic: phone\n",
        encoding="utf-8",
    )
    return load_clip(clips / f"{clip_id}.yaml")
