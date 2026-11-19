"""DeepFilterNet (optional ``cleanup`` extra).

Not yet exercised against the real library in this repo (it pulls in torch); the
resampling and length handling are covered by a stub backend in the tests.
"""

import numpy as np

from itabench.cleanup import CleanupUnavailableError, fit_length

MODEL_RATE = 48000
RATE = 16000


def apply(samples: np.ndarray) -> np.ndarray:
    """Denoise 16 kHz mono s16le samples; the output has the same length."""
    try:
        import soxr  # noqa: PLC0415
        import torch  # noqa: PLC0415
        from df.enhance import enhance, init_df  # noqa: PLC0415
    except ImportError as exc:
        msg = "deepfilternet needs the 'cleanup' extra: uv sync --extra cleanup"
        raise CleanupUnavailableError(msg) from exc
    model, state, _ = init_df()
    audio = samples.astype(np.float32) / 32768.0
    up = soxr.resample(audio, RATE, MODEL_RATE)
    cleaned = enhance(model, state, torch.from_numpy(up)[None, :]).numpy().reshape(-1)
    down = soxr.resample(cleaned, MODEL_RATE, RATE)
    out = np.clip(down * 32768.0, -32768, 32767).astype(np.int16)
    return fit_length(out, len(samples))
