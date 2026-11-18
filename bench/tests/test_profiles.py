from pathlib import Path

import pytest
import yaml
from pydantic import ValidationError

from itabench.models import EngineProfile
from itabench.profiles import (
    PrivacyGateError,
    ProfileError,
    assert_openable,
    load_engines,
    load_pipeline,
    validate_profile,
)


def _profile(
    shared: Path, privacy_over: dict[str, bool] | None = None, **over: object
) -> EngineProfile:
    base = load_engines(shared / "engines.yaml")["google-stt-he"].model_dump()
    privacy = {**dict(base["privacy"]), **(privacy_over or {})}
    return EngineProfile.model_validate({**base, **over, "privacy": privacy})


def test_shared_files_load(shared: Path) -> None:
    assert "fake" in load_engines(shared / "engines.yaml")
    assert load_pipeline(shared / "pipeline.yaml").vad.threshold == 0.5


def test_device_profile_with_cost_raises(shared: Path) -> None:
    with pytest.raises(ProfileError):
        validate_profile(_profile(shared, runs_on="device", cost_usd_per_hour=1.0))


def test_fallback_on_cloud_raises(shared: Path) -> None:
    with pytest.raises(ProfileError):
        validate_profile(_profile(shared, can_be_fallback=True))


def test_unknown_adapter_raises(shared: Path) -> None:
    with pytest.raises(ProfileError):
        validate_profile(_profile(shared, adapter="nope"))


def test_retained_audio_cannot_open(shared: Path) -> None:
    with pytest.raises(PrivacyGateError):
        assert_openable(_profile(shared, privacy_over={"retains_audio": True}))


def test_training_without_opt_out_cannot_open(shared: Path) -> None:
    with pytest.raises(PrivacyGateError):
        assert_openable(
            _profile(shared, privacy_over={"trains_on_audio": True, "opt_out_required": False})
        )


def test_clean_profile_opens(shared: Path) -> None:
    assert_openable(_profile(shared))


def test_unknown_pipeline_key_raises(shared: Path, tmp_path: Path) -> None:
    data = yaml.safe_load((shared / "pipeline.yaml").read_text())
    data["surprise"] = 1
    (tmp_path / "models").mkdir()
    (tmp_path / "models" / "silero_vad.onnx").write_bytes(
        (shared / "models/silero_vad.onnx").read_bytes()
    )
    path = tmp_path / "pipeline.yaml"
    path.write_text(yaml.safe_dump(data))
    with pytest.raises(ValidationError):
        load_pipeline(path)


def test_wrong_vad_hash_raises(shared: Path, tmp_path: Path) -> None:
    data = yaml.safe_load((shared / "pipeline.yaml").read_text())
    (tmp_path / "models").mkdir()
    (tmp_path / "models" / "silero_vad.onnx").write_bytes(b"not the model")
    path = tmp_path / "pipeline.yaml"
    path.write_text(yaml.safe_dump(data))
    with pytest.raises(ProfileError):
        load_pipeline(path)
