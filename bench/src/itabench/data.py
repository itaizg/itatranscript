"""Clip and reference loading with consent and format checks."""

import hashlib
import wave
from pathlib import Path

import yaml

from itabench.models import Reference, TestClip
from itabench.streaming import AudioFormatError


def sha256_file(path: Path) -> str:
    """Hash a file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_clip(meta_path: Path) -> TestClip:
    """Load ``<id>.yaml`` next to ``<id>.wav``.

    Raises:
        pydantic.ValidationError: consent is missing or not ``true``.
        AudioFormatError: the WAV is not 16 kHz mono 16-bit.
    """
    meta = yaml.safe_load(meta_path.read_text(encoding="utf-8"))
    wav_path = meta_path.with_suffix(".wav")
    with wave.open(str(wav_path), "rb") as wav:
        if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) != (16000, 1, 2):
            msg = f"{wav_path}: need 16 kHz mono 16-bit"
            raise AudioFormatError(msg)
        duration = wav.getnframes() / wav.getframerate()
    meta.update(
        id=meta_path.stem,
        audio_path=str(wav_path),
        sha256=sha256_file(wav_path),
        duration_s=duration,
    )
    return TestClip.model_validate(meta)


def load_reference(path: Path) -> Reference:
    """Load a ``<id>.json`` reference."""
    return Reference.model_validate_json(path.read_text(encoding="utf-8"))
