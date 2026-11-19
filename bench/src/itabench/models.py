"""Immutable, validated models shared by the whole harness (constitution IX)."""

from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter

Lang = Literal["he", "en", "mixed"]


class Frozen(BaseModel):
    """Base class: immutable and strict about unknown fields."""

    model_config = ConfigDict(frozen=True, extra="forbid")


class AudioFrame(Frozen):
    """One 20 ms frame of 16 kHz mono s16le audio (640 bytes)."""

    seq: int = Field(ge=0)
    t_ms: int = Field(ge=0)
    pcm: bytes


class SpeechSpan(Frozen):
    """A speech interval detected by the shared VAD."""

    onset_ms: int = Field(ge=0)
    offset_ms: int | None = None


class Word(Frozen):
    """A timed word inside a final event."""

    text: str
    start_ms: int = Field(ge=0)
    end_ms: int = Field(ge=0)
    lang: Lang | None = None


class PartialEvent(Frozen):
    """Provisional text that replaces the earlier partial with the same id."""

    type: Literal["partial"] = "partial"
    t_ms: int = Field(ge=0)
    segment_id: str
    text: str
    lang: Lang | None = None
    start_ms: int = Field(ge=0)
    end_ms: int | None = Field(default=None, ge=0)


class FinalEvent(Frozen):
    """Final text for a segment. Exactly one per segment id."""

    type: Literal["final"] = "final"
    t_ms: int = Field(ge=0)
    segment_id: str
    text: str
    lang: Lang
    start_ms: int = Field(ge=0)
    end_ms: int = Field(ge=0)
    words: tuple[Word, ...] | None = None


class SpeakerChangeEvent(Frozen):
    """A new speaker starts at ``at_ms``."""

    type: Literal["speaker_change"] = "speaker_change"
    t_ms: int = Field(ge=0)
    at_ms: int = Field(ge=0)
    speaker_hint: str | None = None


class HealthEvent(Frozen):
    """Connection health. ``lost`` triggers the on-device fallback."""

    type: Literal["health"] = "health"
    t_ms: int = Field(ge=0)
    state: Literal["ok", "degraded", "lost"]
    reason: str


class UsageEvent(Frozen):
    """Billed audio, used for cost."""

    type: Literal["usage"] = "usage"
    t_ms: int = Field(ge=0)
    audio_seconds_billed: float = Field(ge=0)


class ErrorEvent(Frozen):
    """An engine or vendor error."""

    type: Literal["error"] = "error"
    t_ms: int = Field(ge=0)
    code: Literal[
        "auth",
        "quota",
        "network",
        "unsupported_language",
        "invalid_message",
        "internal",
    ]
    message: str
    retryable: bool


class ClosedEvent(Frozen):
    """Always the last event of a stream."""

    type: Literal["closed"] = "closed"
    t_ms: int = Field(ge=0)


EngineEvent = Annotated[
    PartialEvent
    | FinalEvent
    | SpeakerChangeEvent
    | HealthEvent
    | UsageEvent
    | ErrorEvent
    | ClosedEvent,
    Field(discriminator="type"),
]
EVENT_ADAPTER: TypeAdapter[EngineEvent] = TypeAdapter(EngineEvent)


class Privacy(Frozen):
    """What the vendor does with audio (FR-020)."""

    retains_audio: bool
    trains_on_audio: bool
    opt_out_required: bool
    terms_source: str
    terms_checked_on: str


class EngineProfile(Frozen):
    """One engine as listed in ``shared/engines.yaml``."""

    id: str
    display_name: str
    adapter: str
    runs_on: Literal["cloud", "device", "mac"]
    platforms: tuple[str, ...]
    languages: tuple[Literal["he", "en"], ...]
    supports_code_switching: bool
    supports_speaker_changes: bool
    can_be_fallback: bool
    cost_usd_per_hour: float = Field(ge=0)
    privacy: Privacy
    options: dict[str, str | int | float | bool] = Field(default_factory=dict)


class EnginesFile(Frozen):
    """Top-level shape of ``shared/engines.yaml``."""

    version: int
    engines: tuple[EngineProfile, ...]


class VadConfig(Frozen):
    """Silero VAD settings."""

    model: str
    model_sha256: str
    threshold: float = Field(gt=0, lt=1)
    min_speech_ms: int = Field(gt=0)
    min_silence_ms: int = Field(gt=0)
    pad_ms: int = Field(ge=0)


class LatencyConfig(Frozen):
    """Latency definitions (research R-3)."""

    provisional: str
    final: str
    report_percentiles: tuple[int, ...]


class FallbackConfig(Frozen):
    """On-device fallback settings."""

    ring_buffer_s: int = Field(gt=0)
    silence_timeout_ms: int = Field(gt=0)


class BatteryConfig(Frozen):
    """Battery-low warning thresholds."""

    min_remaining_minutes: int = Field(gt=0)
    min_percent: int = Field(gt=0)


class PipelineConfig(Frozen):
    """Contents of ``shared/pipeline.yaml``."""

    version: int
    vad: VadConfig
    latency: LatencyConfig
    fallback: FallbackConfig
    battery_warning: BatteryConfig
    speaker_heuristic: dict[str, float] | None = None


class TestClip(Frozen):
    """A consented test recording."""

    __test__ = False

    id: str
    situation: Literal["cafe", "group", "meeting", "lecture"]
    lang: Lang
    audio_path: str
    sha256: str
    duration_s: float = Field(gt=0)
    consent: Literal[True]
    consent_date: date
    speakers: int = Field(ge=1)
    mic: Literal["phone", "external", "table"]


class RefWord(Frozen):
    """A hand-corrected reference word."""

    text: str
    lang: Literal["he", "en"]
    needs_check: bool = False


class Interval(Frozen):
    """A time interval in milliseconds."""

    start_ms: int = Field(ge=0)
    end_ms: int = Field(ge=0)


class Reference(Frozen):
    """Reference transcript for a clip."""

    words: tuple[RefWord, ...]
    non_speech: tuple[Interval, ...] = ()
    turn_changes_ms: tuple[int, ...] = ()


class EvaluationResult(Frozen):
    """Metrics and provenance for one clip x engine x cleanup x VAD item."""

    clip_id: str
    engine_id: str
    cleanup: str
    vad: Literal["on", "off"]
    status: Literal["ok", "failed"]
    error: str | None = None
    wer: float | None = None
    cer: float | None = None
    wer_by_lang: dict[str, float] = Field(default_factory=dict)
    ttp_p50_ms: float | None = None
    ttp_p90_ms: float | None = None
    ttf_p50_ms: float | None = None
    ttf_p90_ms: float | None = None
    made_up_words: int | None = None
    speaker_change_recall: float | None = None
    cost_usd_per_hour: float | None = None
    clip_sha256: str
    engine_version: str
    shared_hashes: dict[str, str]
    harness_version: str
    ran_at: datetime
