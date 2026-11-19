"""Noise-cleanup variants applied before the VAD gate (research R-5)."""

from collections.abc import Callable

import numpy as np

CLEANUP_NAMES = ("none", "rnnoise", "deepfilternet", "voiceproc")

#: A cleanup maps 16 kHz mono s16le samples to samples of the same length.
Cleanup = Callable[[np.ndarray], np.ndarray]


class CleanupUnavailableError(RuntimeError):
    """A cleanup's optional dependency or tool is not installed."""


def fit_length(samples: np.ndarray, length: int) -> np.ndarray:
    """Trim or zero-pad ``samples`` to exactly ``length``."""
    if len(samples) >= length:
        return samples[:length]
    return np.pad(samples, (0, length - len(samples)))


def get_cleanup(name: str) -> Cleanup:
    """Return the cleanup function for ``name``.

    Raises:
        ValueError: ``name`` is not a known variant.
        CleanupUnavailableError: the variant's dependency is missing.
    """
    if name == "none":
        from itabench.cleanup.none import apply  # noqa: PLC0415

        return apply
    if name == "rnnoise":
        from itabench.cleanup.rnnoise import apply  # noqa: PLC0415

        return apply
    if name == "deepfilternet":
        from itabench.cleanup.deepfilternet import apply  # noqa: PLC0415

        return apply
    if name == "voiceproc":
        from itabench.cleanup.voiceproc import apply  # noqa: PLC0415

        return apply
    msg = f"unknown cleanup {name!r}; known: {', '.join(CLEANUP_NAMES)}"
    raise ValueError(msg)
