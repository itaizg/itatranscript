from datetime import UTC, datetime
from pathlib import Path

from conftest import make_clip

from itabench.models import EvaluationResult
from itabench.report import build_report


def _result(clip_id: str, cleanup: str = "none", wer: float = 0.2) -> EvaluationResult:
    return EvaluationResult(
        clip_id=clip_id,
        engine_id="fake",
        cleanup=cleanup,
        vad="on",
        status="ok",
        wer=wer,
        cer=0.1,
        wer_by_lang={"he": 0.3, "en": 0.1},
        ttp_p50_ms=400,
        ttp_p90_ms=800,
        ttf_p50_ms=500,
        ttf_p90_ms=900,
        made_up_words=1,
        speaker_change_recall=0.5,
        cost_usd_per_hour=0,
        clip_sha256="a" * 64,
        engine_version="fake-1",
        shared_hashes={"pipeline.yaml": "b" * 64},
        harness_version="0.1.0",
        ran_at=datetime(2026, 1, 1, tzinfo=UTC),
    )


def test_report_separates_languages_shows_variants_and_never_recommends(
    shared: Path, tmp_path: Path
) -> None:
    clips = {
        "he1": make_clip(tmp_path / "d1", shared, "he1", "he"),
        "en1": make_clip(tmp_path / "d2", shared, "en1", "en"),
        "mx1": make_clip(tmp_path / "d3", shared, "mx1", "mixed"),
    }
    results = [_result("he1"), _result("he1", "rnnoise", 0.15), _result("en1"), _result("mx1")]
    text = build_report(results, clips)
    for heading in ("## Hebrew", "## English", "## Mixed Hebrew/English", "## Provenance"):
        assert heading in text
    assert text.index("## Normalization rules") < text.index("## Hebrew")
    hebrew = text.split("## Hebrew")[1].split("## English")[0]
    assert hebrew.index("| none |") < hebrew.index("| rnnoise |")
    assert "recommend" not in text.lower()
    assert "threshold" not in text.lower()
    assert "fake-1" in text
    assert "`pipeline.yaml`" in text


def test_language_with_no_clips_says_so() -> None:
    assert "No clips scored for this language." in build_report([], {})
