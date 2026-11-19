"""The baseline: no cleanup."""

import numpy as np


def apply(samples: np.ndarray) -> np.ndarray:
    """Return the audio unchanged."""
    return samples
