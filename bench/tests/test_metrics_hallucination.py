from itabench.metrics.hallucination import count_made_up_words
from itabench.models import FinalEvent, Interval


def _final(start: int, end: int, text: str) -> FinalEvent:
    return FinalEvent(
        t_ms=end, segment_id=f"s{start}", text=text, lang="en", start_ms=start, end_ms=end
    )


def test_only_finals_inside_non_speech_count() -> None:
    quiet = [Interval(start_ms=5000, end_ms=8000)]
    events = [_final(0, 1000, "real words"), _final(5500, 6000, "thank you")]
    assert count_made_up_words(events, quiet) == 2
    assert count_made_up_words(events[:1], quiet) == 0
