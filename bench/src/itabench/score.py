"""``itabench score``: turn stored events into ``EvaluationResult`` files."""

import json
import logging
import math
from collections.abc import Mapping
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

from itabench.engines.fake import load_events
from itabench.metrics.hallucination import count_made_up_words
from itabench.metrics.latency import compute_latency
from itabench.metrics.speakers import score_speaker_changes
from itabench.metrics.wer import score_text
from itabench.models import (
    EngineProfile,
    EvaluationResult,
    FinalEvent,
    PipelineConfig,
    Reference,
    SpeechSpan,
    TestClip,
)
from itabench.results_store import ResultsStore

log = logging.getLogger(__name__)


def harness_version() -> str:
    """Installed ``itabench`` version."""
    try:
        return version("itabench")
    except PackageNotFoundError:
        return "unknown"


def _num(value: float) -> float | None:
    return None if math.isnan(value) else value


def _read_spans(path: Path) -> list[SpeechSpan]:
    if not path.exists():
        return []
    return [
        SpeechSpan.model_validate_json(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def _read_run_info(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return dict(json.loads(path.read_text(encoding="utf-8").splitlines()[0]))


def score_item(  # noqa: PLR0913
    *,
    events_path: Path,
    clip: TestClip,
    reference: Reference,
    profile: EngineProfile,
    cleanup: str,
    vad: str,
    config: PipelineConfig,
    shared_hashes: Mapping[str, str],
) -> EvaluationResult:
    """Compute every metric for one stored item, with full provenance."""
    events = load_events(events_path)
    spans = _read_spans(events_path.with_name(events_path.name.replace("events", "spans")))
    info = _read_run_info(events_path.with_name(events_path.name.replace("events", "run")))
    finals = sorted((e for e in events if isinstance(e, FinalEvent)), key=lambda e: e.start_ms)
    rates = score_text(reference.words, " ".join(e.text for e in finals))
    latency = compute_latency(events, spans, config)
    speakers = score_speaker_changes(events, reference.turn_changes_ms)
    return EvaluationResult(
        clip_id=clip.id,
        engine_id=profile.id,
        cleanup=cleanup,
        vad="on" if vad == "on" else "off",
        status="ok",
        wer=rates.wer,
        cer=rates.cer,
        wer_by_lang=rates.wer_by_lang,
        ttp_p50_ms=_num(latency.provisional_pct.get(50, math.nan)),
        ttp_p90_ms=_num(latency.provisional_pct.get(90, math.nan)),
        ttf_p50_ms=_num(latency.final_pct.get(50, math.nan)),
        ttf_p90_ms=_num(latency.final_pct.get(90, math.nan)),
        made_up_words=count_made_up_words(events, reference.non_speech),
        speaker_change_recall=speakers.recall,
        cost_usd_per_hour=profile.cost_usd_per_hour,
        clip_sha256=clip.sha256,
        engine_version=info.get("engine_version", "unknown"),
        shared_hashes=dict(shared_hashes),
        harness_version=harness_version(),
        ran_at=datetime.fromisoformat(info["ran_at"]) if "ran_at" in info else datetime.now(UTC),
    )


def score_all(  # noqa: PLR0913
    *,
    store: ResultsStore,
    clips: Mapping[str, TestClip],
    references: Mapping[str, Reference],
    profiles: Mapping[str, EngineProfile],
    config: PipelineConfig,
    shared_hashes: Mapping[str, str],
) -> list[EvaluationResult]:
    """Score every stored events log and write ``<clip>.json`` next to it."""
    results: list[EvaluationResult] = []
    for events_path in store.files("events.jsonl"):
        vad_dir = events_path.parent
        cleanup, vad, engine = vad_dir.parent.name, vad_dir.name, vad_dir.parent.parent.name
        clip_id = events_path.name.removesuffix(".events.jsonl")
        clip, reference, profile = clips.get(clip_id), references.get(clip_id), profiles.get(engine)
        if clip is None or profile is None:
            log.warning("skipping %s: unknown clip or engine", events_path)
            continue
        if reference is None:
            log.error("no reference for clip %s", clip_id)
            continue
        try:
            result = score_item(
                events_path=events_path,
                clip=clip,
                reference=reference,
                profile=profile,
                cleanup=cleanup,
                vad=vad,
                config=config,
                shared_hashes=shared_hashes,
            )
        except Exception:  # noqa: BLE001 - one bad item must not stop scoring
            log.exception("scoring failed: %s", events_path)
            continue
        store.write(engine, cleanup, vad, clip_id, "json", result.model_dump_json(indent=2))
        results.append(result)
    return results


def load_results(store: ResultsStore) -> list[EvaluationResult]:
    """Read every stored ``EvaluationResult``."""
    return [
        EvaluationResult.model_validate_json(p.read_text(encoding="utf-8"))
        for p in store.files("json")
    ]
