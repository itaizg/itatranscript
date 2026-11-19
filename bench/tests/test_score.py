import json
from pathlib import Path

from conftest import make_clip

from itabench.clock import FakeClock
from itabench.engines.fake import FakeEngine, load_events
from itabench.models import Interval, Reference, RefWord
from itabench.profiles import load_engines, load_pipeline, shared_hashes
from itabench.results_store import ResultsStore
from itabench.run import run_all
from itabench.score import load_results, score_all

REFERENCE = Reference(
    words=(RefWord(text="hello", lang="en"), RefWord(text="world", lang="en")),
    non_speech=(Interval(start_ms=9000, end_ms=11000),),
    turn_changes_ms=(),
)


async def _run_and_score(shared: Path, tmp_path: Path) -> list:  # noqa: ANN401
    config = load_pipeline()
    clip = make_clip(tmp_path / "data", shared)
    store = ResultsStore(tmp_path / "results")
    clock = FakeClock()
    log = load_events(shared / "fixtures/partial-then-final.events.jsonl")
    profiles = load_engines()
    await clock.drive(
        run_all(
            profiles=[profiles["fake"]],
            clips=[clip],
            cleanups=["none"],
            vads=["on"],
            config=config,
            model_path=shared / config.vad.model,
            store=store,
            clock_factory=lambda: clock,
            factory=lambda _profile, c: FakeEngine(log, c),
        )
    )
    results = score_all(
        store=store,
        clips={clip.id: clip},
        references={clip.id: REFERENCE},
        profiles=profiles,
        config=config,
        shared_hashes=shared_hashes(),
    )
    assert load_results(store) == results
    return results


async def test_fake_engine_scores_perfectly_with_full_provenance(
    shared: Path, tmp_path: Path
) -> None:
    (result,) = await _run_and_score(shared, tmp_path)
    assert (result.status, result.wer, result.cer, result.made_up_words) == ("ok", 0.0, 0.0, 0)
    assert result.speaker_change_recall is None
    assert result.cost_usd_per_hour == 0
    assert result.engine_version == "fake-1"
    assert len(result.clip_sha256) == 64
    assert set(result.shared_hashes) == {
        "engines.yaml",
        "pipeline.yaml",
        "engine-events.schema.json",
    }
    assert result.harness_version
    assert result.ran_at is not None


async def test_score_writes_json_next_to_events(shared: Path, tmp_path: Path) -> None:
    await _run_and_score(shared, tmp_path)
    path = tmp_path / "results/fake/none/on/c1.json"
    assert json.loads(path.read_text())["clip_id"] == "c1"
