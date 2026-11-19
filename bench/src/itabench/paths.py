"""Locate the repository root, whether the package is installed editable or not."""

import os
from pathlib import Path

MARKER = Path("shared") / "engines.yaml"


def find_repo_root(start: Path | None = None) -> Path:
    """Return the repo root: ``$ITABENCH_ROOT``, else the nearest parent holding ``shared/``.

    The search starts at ``start`` (default: the current directory), then falls back to
    this file's own location, which works for editable installs.
    """
    env = os.environ.get("ITABENCH_ROOT")
    if env:
        return Path(env)
    for origin in (start or Path.cwd(), Path(__file__).resolve()):
        for parent in (origin, *origin.parents):
            if (parent / MARKER).exists():
                return parent
    msg = "cannot find the repo root (no shared/engines.yaml above here); set ITABENCH_ROOT"
    raise FileNotFoundError(msg)


REPO_ROOT = find_repo_root()
