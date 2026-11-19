import json
from pathlib import Path

from itabench.engines.fake import load_events
from itabench.metrics.latency import compute_latency
from itabench.models import SpeechSpan
from itabench.profiles import load_pipeline


def test_latency_matches_hand_computed_fixture(shared: Path) -> None:
    fx = shared / "fixtures"
    events = load_events(fx / "latency-basic.events.jsonl")
    spans = [
        SpeechSpan(**s) for s in json.loads((fx / "latency-basic.spans.json").read_text())["spans"]
    ]
    expected = json.loads((fx / "latency-basic.expected.json").read_text())
    stats = compute_latency(events, spans, load_pipeline(shared / "pipeline.yaml"))
    assert list(stats.provisional_ms) == expected["provisional_ms"]["values"]
    assert list(stats.final_ms) == expected["final_ms"]["values"]
    assert stats.provisional_pct == {
        50: expected["provisional_ms"]["p50"],
        90: expected["provisional_ms"]["p90"],
    }
    assert stats.final_pct == {50: expected["final_ms"]["p50"], 90: expected["final_ms"]["p90"]}
