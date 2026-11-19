from collections.abc import Mapping
import shutil
import wave
from pathlib import Path

import pytest
import yaml
from pydantic import ValidationError

from itabench.data import load_clip
from itabench.streaming import AudioFormatError

META = {"situation": "cafe", "lang": "en", "speakers": 2, "mic": "phone"}


def _clip(tmp: Path, shared: Path, meta: Mapping[str, object]) -> Path:
    shutil.copy(shared / "fixtures/speech-short.wav", tmp / "c1.wav")
    path = tmp / "c1.yaml"
    path.write_text(yaml.safe_dump(meta))
    return path


def test_valid_clip_loads(tmp_path: Path, shared: Path) -> None:
    clip = load_clip(
        _clip(tmp_path, shared, {**META, "consent": True, "consent_date": "2026-11-18"})
    )
    assert clip.id == "c1"
    assert len(clip.sha256) == 64


def test_clip_without_consent_rejected(tmp_path: Path, shared: Path) -> None:
    with pytest.raises(ValidationError):
        load_clip(_clip(tmp_path, shared, META))


def test_wrong_sample_rate_rejected(tmp_path: Path, shared: Path) -> None:
    path = _clip(tmp_path, shared, {**META, "consent": True, "consent_date": "2026-11-18"})
    with wave.open(str(path.with_suffix(".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b"\0" * 400)
    with pytest.raises(AudioFormatError):
        load_clip(path)
