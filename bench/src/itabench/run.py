"""``itabench run``: stream every clip x engine x cleanup x VAD item and store events."""

import json
import logging
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from itabench.cleanup import get_cleanup
from itabench.clock import Clock, SystemClock
from itabench.contract import EngineAdapter
from itabench.engines.factory import build_engine
from itabench.engines.fake import dump_event
from itabench.models import AudioFrame, EngineProfile, PipelineConfig, SpeechSpan, TestClip
from itabench.profiles import PrivacyGateError, assert_openable
from itabench.results_store import ResultsStore
from itabench.speech_gate import SpeechGate
from itabench.streaming import (
    FRAME_BYTES,
    FRAME_MS,
    TAIL_SILENCE_MS,
    read_wav_pcm,
    stream_timed,
)

log = logging.getLogger(__name__)

EngineFactory = Callable[[EngineProfile, Clock], EngineAdapter]


@dataclass(frozen=True)
class RunCounts:
    """Outcome of a run (XII): every item is accounted for."""

    processed: int = 0
    succeeded: int = 0
    skipped: int = 0
    failed: int = 0

    def exit_code(self) -> int:
        """Non-zero when anything failed, or when nothing ran at all."""
        if self.failed or (self.processed and self.skipped == self.processed):
            return 1
        return 0


def gate_frames(pcm: bytes, gate: SpeechGate) -> tuple[list[AudioFrame], list[SpeechSpan], int]:
    """Run PCM (plus the trailing silence) through the gate.

    Returns the frames the engine will see, the VAD spans, and the stream end (ms).
    """
    pcm += b"\0" * (TAIL_SILENCE_MS // FRAME_MS * FRAME_BYTES)
    pcm += b"\0" * (-len(pcm) % FRAME_BYTES)
    passed: list[AudioFrame] = []
    count = len(pcm) // FRAME_BYTES
    for seq in range(count):
        frame = AudioFrame(
            seq=seq, t_ms=seq * FRAME_MS, pcm=pcm[seq * FRAME_BYTES : (seq + 1) * FRAME_BYTES]
        )
        passed.extend(gate.push(frame))
    gate.finish()
    return passed, list(gate.spans), (count - 1) * FRAME_MS


async def run_item(  # noqa: PLR0913
    *,
    profile: EngineProfile,
    clip: TestClip,
    cleanup: str,
    vad: str,
    config: PipelineConfig,
    model_path: Path,
    store: ResultsStore,
    clock: Clock,
    factory: EngineFactory,
    secrets: Mapping[str, str] | None = None,
) -> None:
    """Process one item and write its events and spans."""
    cleaned = get_cleanup(cleanup)(
        np.frombuffer(read_wav_pcm(Path(clip.audio_path)), dtype=np.int16)
    )
    gate = SpeechGate(config, model_path, enabled=vad == "on")
    frames, spans, end_ms = gate_frames(cleaned.astype(np.int16).tobytes(), gate)
    engine = factory(profile, clock)
    language_mode = "auto" if clip.lang == "mixed" else clip.lang
    events = await stream_timed(
        engine,
        profile,
        frames,
        clock,
        end_ms=end_ms,
        language_mode=language_mode,
        secrets=secrets,
    )
    store.write(
        profile.id,
        cleanup,
        vad,
        clip.id,
        "events.jsonl",
        "".join(dump_event(e) + "\n" for e in events),
    )
    store.write(
        profile.id,
        cleanup,
        vad,
        clip.id,
        "spans.jsonl",
        "".join(s.model_dump_json() + "\n" for s in spans),
    )
    info = {
        "engine_version": str(getattr(engine, "version", "unknown")),
        "ran_at": datetime.now(UTC).isoformat(),
    }
    store.write(profile.id, cleanup, vad, clip.id, "run.jsonl", json.dumps(info) + "\n")


async def run_all(  # noqa: PLR0913
    *,
    profiles: Iterable[EngineProfile],
    clips: Iterable[TestClip],
    cleanups: Iterable[str],
    vads: Iterable[str],
    config: PipelineConfig,
    model_path: Path,
    store: ResultsStore,
    clock_factory: Callable[[], Clock] = SystemClock,
    factory: EngineFactory = build_engine,
    secrets: Mapping[str, str] | None = None,
) -> RunCounts:
    """Run every combination; one failing item never stops the others."""
    processed = succeeded = skipped = failed = 0
    clip_list, cleanup_list, vad_list = list(clips), list(cleanups), list(vads)
    for profile in profiles:
        try:
            assert_openable(profile)
        except PrivacyGateError as exc:
            count = len(clip_list) * len(cleanup_list) * len(vad_list)
            log.warning("skipping %s (%d items): %s", profile.id, count, exc)
            processed += count
            skipped += count
            continue
        for cleanup in cleanup_list:
            for vad in vad_list:
                for clip in clip_list:
                    processed += 1
                    try:
                        await run_item(
                            profile=profile,
                            clip=clip,
                            cleanup=cleanup,
                            vad=vad,
                            config=config,
                            model_path=model_path,
                            store=store,
                            clock=clock_factory(),
                            factory=factory,
                            secrets=secrets,
                        )
                    except Exception:  # noqa: BLE001 - the one catch-all at the item boundary
                        failed += 1
                        log.exception("item failed: %s/%s/%s/%s", profile.id, cleanup, vad, clip.id)
                    else:
                        succeeded += 1
    counts = RunCounts(processed, succeeded, skipped, failed)
    log.info(
        "run finished: processed=%d succeeded=%d skipped=%d failed=%d",
        counts.processed,
        counts.succeeded,
        counts.skipped,
        counts.failed,
    )
    return counts
