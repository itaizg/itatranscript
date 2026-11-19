"""Apple voice processing, run through the Swift helper on the Mac (task T036)."""

import subprocess

import numpy as np

from itabench.cleanup import CleanupUnavailableError, fit_length
from itabench.paths import REPO_ROOT

TOOL_DIR = REPO_ROOT / "bench" / "tools" / "apple-speech"


def apply(samples: np.ndarray) -> np.ndarray:
    """Pipe PCM through ``apple-speech voiceproc``; the output has the same length."""
    exe = TOOL_DIR / ".build" / "release" / "apple-speech"
    if not exe.exists():
        msg = f"build the helper first: swift build -c release --package-path {TOOL_DIR}"
        raise CleanupUnavailableError(msg)
    result = subprocess.run(  # noqa: S603
        [str(exe), "voiceproc"],
        input=samples.astype(np.int16).tobytes(),
        capture_output=True,
        check=True,
    )
    out = np.frombuffer(result.stdout, dtype=np.int16)
    return fit_length(out, len(samples))
