"""RNNoise via ``pyrnnoise`` (optional ``cleanup`` extra)."""

import numpy as np

from itabench.cleanup import CleanupUnavailableError, fit_length


def apply(samples: np.ndarray) -> np.ndarray:
    """Denoise 16 kHz mono s16le samples; the output has the same length."""
    try:
        from pyrnnoise import RNNoise  # noqa: PLC0415
    except ImportError as exc:
        msg = "rnnoise needs the 'cleanup' extra: uv sync --extra cleanup"
        raise CleanupUnavailableError(msg) from exc
    denoiser = RNNoise(sample_rate=16000)
    frames = [frame for _, frame in denoiser.denoise_chunk(samples, partial=True)]
    if not frames:
        return samples
    out = np.concatenate([np.asarray(f).reshape(-1) for f in frames]).astype(np.int16)
    return fit_length(out, len(samples))
