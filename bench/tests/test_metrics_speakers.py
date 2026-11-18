from itabench.metrics.speakers import score_speaker_changes
from itabench.models import SpeakerChangeEvent


def _change(at: int) -> SpeakerChangeEvent:
    return SpeakerChangeEvent(t_ms=at, at_ms=at)


def test_hit_miss_and_false_alarm() -> None:
    score = score_speaker_changes([_change(2300), _change(9000)], [2000, 5000])
    assert score.recall == 0.5
    assert score.false_alarms == 1


def test_no_reference_turns_gives_no_recall() -> None:
    assert score_speaker_changes([], []).recall is None
