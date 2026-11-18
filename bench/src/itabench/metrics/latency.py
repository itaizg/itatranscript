"""The shared latency definition (research R-3), read from ``PipelineConfig``."""

import math
from collections.abc import Sequence
from dataclasses import dataclass

from itabench.models import EngineEvent, FinalEvent, PartialEvent, PipelineConfig, SpeechSpan


@dataclass(frozen=True)
class LatencyStats:
    """Per-utterance latencies and their percentiles (nearest-rank)."""

    provisional_ms: tuple[int, ...]
    final_ms: tuple[int, ...]
    provisional_pct: dict[int, float]
    final_pct: dict[int, float]


def percentile(values: Sequence[int], pct: int) -> float:
    """Nearest-rank percentile; ``nan`` for no values."""
    if not values:
        return math.nan
    ordered = sorted(values)
    rank = max(1, math.ceil(pct / 100 * len(ordered)))
    return float(ordered[rank - 1])


def compute_latency(
    events: Sequence[EngineEvent], spans: Sequence[SpeechSpan], config: PipelineConfig
) -> LatencyStats:
    """Time to provisional and to final, per VAD utterance.

    Events are matched to an utterance by arrival time: from its onset up to the next
    utterance's onset. Time to provisional = first partial arrival - onset. Time to
    final = last final arrival - offset.
    """
    ttp: list[int] = []
    ttf: list[int] = []
    ordered = sorted(spans, key=lambda s: s.onset_ms)
    for i, span in enumerate(ordered):
        end = ordered[i + 1].onset_ms if i + 1 < len(ordered) else math.inf
        window = [e for e in events if span.onset_ms <= e.t_ms < end]
        partials = [e.t_ms for e in window if isinstance(e, PartialEvent)]
        finals = [e.t_ms for e in window if isinstance(e, FinalEvent)]
        if partials:
            ttp.append(min(partials) - span.onset_ms)
        if finals and span.offset_ms is not None:
            ttf.append(max(finals) - span.offset_ms)
    pcts = config.latency.report_percentiles
    return LatencyStats(
        tuple(ttp),
        tuple(ttf),
        {p: percentile(ttp, p) for p in pcts},
        {p: percentile(ttf, p) for p in pcts},
    )
