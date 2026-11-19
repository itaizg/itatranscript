"""Load and validate ``shared/engines.yaml`` and ``shared/pipeline.yaml``."""

import hashlib
from pathlib import Path

import yaml

from itabench.contract import KNOWN_ADAPTERS
from itabench.models import EnginesFile, EngineProfile, PipelineConfig
from itabench.paths import REPO_ROOT

SHARED_DIR = REPO_ROOT / "shared"


class ProfileError(ValueError):
    """A profile or config breaks a contract rule."""


class PrivacyGateError(ProfileError):
    """The engine's terms fail the privacy gate (FR-020)."""


def validate_profile(profile: EngineProfile) -> None:
    """Enforce the load-time rules from ``contracts/engine-profiles.md``."""
    if profile.runs_on == "device" and profile.cost_usd_per_hour != 0:
        msg = f"{profile.id}: a device profile must cost 0"
        raise ProfileError(msg)
    if profile.can_be_fallback and profile.runs_on != "device":
        msg = f"{profile.id}: only a device profile can be a fallback"
        raise ProfileError(msg)
    if profile.adapter not in KNOWN_ADAPTERS:
        msg = f"{profile.id}: unknown adapter {profile.adapter!r}"
        raise ProfileError(msg)
    if len(profile.languages) < 1:
        msg = f"{profile.id}: needs at least one language"
        raise ProfileError(msg)


def assert_openable(profile: EngineProfile) -> None:
    """Refuse engines with unverified terms, that keep audio, or train on it with no opt-out (FR-020).

    ``opt_out_required: true`` means a vendor opt-out exists and must be applied.
    """
    privacy = profile.privacy
    if privacy.terms_checked_on.strip().lower() == "unverified":
        msg = f"{profile.id}: vendor terms not verified (see vendor-check.md)"
        raise PrivacyGateError(msg)
    if privacy.retains_audio:
        msg = f"{profile.id}: vendor retains audio"
        raise PrivacyGateError(msg)
    if privacy.trains_on_audio and not privacy.opt_out_required:
        msg = f"{profile.id}: vendor trains on audio and offers no opt-out"
        raise PrivacyGateError(msg)


def load_engines(path: Path | None = None) -> dict[str, EngineProfile]:
    """Load every profile, enforcing all rules except the privacy gate."""
    path = path or SHARED_DIR / "engines.yaml"
    data = EnginesFile.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))
    for profile in data.engines:
        validate_profile(profile)
    return {p.id: p for p in data.engines}


def load_pipeline(path: Path | None = None) -> PipelineConfig:
    """Load ``pipeline.yaml`` and check the VAD model's sha256."""
    path = path or SHARED_DIR / "pipeline.yaml"
    config = PipelineConfig.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))
    model = path.parent / config.vad.model
    actual = hashlib.sha256(model.read_bytes()).hexdigest()
    if actual != config.vad.model_sha256:
        msg = f"VAD model sha256 mismatch: {actual} != {config.vad.model_sha256}"
        raise ProfileError(msg)
    return config


def shared_hashes(shared_dir: Path | None = None) -> dict[str, str]:
    """Hash the shared config files, for result provenance."""
    shared_dir = shared_dir or SHARED_DIR
    names = ("engines.yaml", "pipeline.yaml", "engine-events.schema.json")
    return {n: hashlib.sha256((shared_dir / n).read_bytes()).hexdigest() for n in names}
