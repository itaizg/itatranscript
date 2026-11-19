"""Results on disk: one file per item, replaced atomically (constitution XV)."""

import os
import tempfile
from pathlib import Path


class ResultsStore:
    """Stores ``<root>/<engine>/<cleanup>/<vad>/<clip>.<suffix>``."""

    def __init__(self, root: Path) -> None:
        """Create a store rooted at ``root``."""
        self._root = root

    def path(self, engine: str, cleanup: str, vad: str, clip: str, suffix: str) -> Path:
        """Return the file path for one item."""
        return self._root / engine / cleanup / vad / f"{clip}.{suffix}"

    def write(self, engine: str, cleanup: str, vad: str, clip: str, suffix: str, text: str) -> Path:
        """Write via a temp file and atomic replace; a re-run overwrites."""
        target = self.path(engine, cleanup, vad, clip, suffix)
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".tmp-")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
            Path(tmp).replace(target)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
        return target

    def files(self, suffix: str) -> list[Path]:
        """List every stored file with ``suffix``, sorted."""
        return sorted(self._root.glob(f"*/*/*/*.{suffix}"))
