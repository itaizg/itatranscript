"""Speaker-change recall against reference turn changes."""

from collections.abc import Sequence
from dataclasses import dataclass

from itabench.models import EngineEvent, SpeakerChangeEvent

TOLERANCE_MS = 1000


@dataclass(frozen=True)
class SpeakerScore:
    """Recall plus the number of changes that matched nothing."""

    recall: float | None
    false_alarms: int


def score_speaker_changes(
    events: Sequence[EngineEvent], turn_changes_ms: Sequence[int]
) -> SpeakerScore:
    """Match changes to reference turns one-to-one within +/-1 s."""
    detected = sorted(e.at_ms for e in events if isinstance(e, SpeakerChangeEvent))
    unused = list(detected)
    hits = 0
    for turn in sorted(turn_changes_ms):
        match = next((d for d in unused if abs(d - turn) <= TOLERANCE_MS), None)
        if match is not None:
            unused.remove(match)
            hits += 1
    recall = hits / len(turn_changes_ms) if turn_changes_ms else None
    return SpeakerScore(recall, len(unused))
