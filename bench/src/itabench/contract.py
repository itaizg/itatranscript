"""The engine adapter contract (``contracts/engine-stream.md``)."""

from collections.abc import AsyncIterator, Callable
from typing import Protocol

from itabench.models import AudioFrame, EngineEvent, EngineProfile

#: Every adapter key that ``shared/engines.yaml`` may name.
KNOWN_ADAPTERS = frozenset(
    {
        "fake",
        "apple_speech",
        "android_speech",
        "agora_rtstt",
        "google_streaming",
        "azure_streaming",
        "soniox_streaming",
        "speechmatics_streaming",
        "whisper_local",
    }
)


class EngineAdapter(Protocol):
    """Audio in, events out. Adapters keep no state between sessions."""

    async def open(
        self, profile: EngineProfile, language_mode: str, secrets: dict[str, str]
    ) -> None:
        """Start a session."""
        ...

    async def push_audio(self, frame: AudioFrame) -> None:
        """Send one gated 20 ms frame."""
        ...

    async def finish(self) -> None:
        """Flush, emit remaining finals, then ``closed``."""
        ...

    async def cancel(self) -> None:
        """Stop now and emit ``closed``; nothing follows it."""
        ...

    def events(self) -> AsyncIterator[EngineEvent]:
        """Stream events until ``closed``."""
        ...


AdapterFactory = Callable[[], EngineAdapter]
_REGISTRY: dict[str, AdapterFactory] = {}


def register(key: str, factory: AdapterFactory) -> None:
    """Register an adapter factory under ``key``."""
    if key not in KNOWN_ADAPTERS:
        msg = f"unknown adapter key: {key}"
        raise ValueError(msg)
    _REGISTRY[key] = factory


def create(key: str) -> EngineAdapter:
    """Create a registered adapter."""
    try:
        return _REGISTRY[key]()
    except KeyError as exc:
        msg = f"no adapter registered for: {key}"
        raise LookupError(msg) from exc
