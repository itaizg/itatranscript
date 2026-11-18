"""Shared test helpers."""

from pathlib import Path

import pytest

SHARED = Path(__file__).resolve().parents[2] / "shared"


@pytest.fixture
def shared() -> Path:
    """Path to the repo's ``shared/`` directory."""
    return SHARED
