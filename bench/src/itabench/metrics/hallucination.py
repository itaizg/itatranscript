"""Made-up words: text an engine produces where nobody spoke."""

from collections.abc import Sequence

from itabench.metrics.normalize import normalize_tokens
from itabench.models import EngineEvent, FinalEvent, Interval


def count_made_up_words(events: Sequence[EngineEvent], non_speech: Sequence[Interval]) -> int:
    """Count words in finals whose midpoint falls inside a non-speech interval."""
    total = 0
    for event in events:
        if not isinstance(event, FinalEvent):
            continue
        mid = (event.start_ms + event.end_ms) / 2
        if any(i.start_ms <= mid <= i.end_ms for i in non_speech):
            total += len(normalize_tokens(event.text))
    return total
