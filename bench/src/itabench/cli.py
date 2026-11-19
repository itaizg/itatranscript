"""Command-line entry point for the benchmark harness (``contracts/bench-cli.md``)."""

import asyncio
import logging
from collections.abc import Callable
from pathlib import Path
from typing import Annotated

import typer

from itabench.align import align_clip
from itabench.check import check_engine, load_env
from itabench.cleanup import CLEANUP_NAMES
from itabench.clock import Clock, SystemClock
from itabench.contract import EngineAdapter
from itabench.data import load_clip, load_reference
from itabench.engines.factory import build_engine
from itabench.models import EngineProfile, TestClip
from itabench.paths import REPO_ROOT
from itabench.profiles import (
    SHARED_DIR,
    PrivacyGateError,
    load_engines,
    load_pipeline,
    shared_hashes,
)
from itabench.report import build_report
from itabench.results_store import ResultsStore
from itabench.run import run_all
from itabench.score import load_results, score_all

BENCH_DIR = REPO_ROOT / "bench"
log = logging.getLogger("itabench")

app = typer.Typer(help="Benchmark live caption engines.", no_args_is_help=True)

DataDir = Annotated[Path, typer.Option(help="Folder with clips/ and refs/.")]
ResultsDir = Annotated[Path, typer.Option(help="Folder for results.")]

#: Test seams: the CLI tests swap these for instant clocks and fake engines.
CLOCK_FACTORY: Callable[[], Clock] = SystemClock
ENGINE_FACTORY: Callable[[EngineProfile, Clock, str], EngineAdapter] = build_engine


def _csv(value: str) -> list[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


def _load_clips(data_dir: Path, wanted: str) -> dict[str, TestClip]:
    metas = sorted((data_dir / "clips").glob("*.yaml"))
    ids = None if wanted == "all" else set(_csv(wanted))
    return {m.stem: load_clip(m) for m in metas if ids is None or m.stem in ids}


@app.callback()
def main(verbose: Annotated[bool, typer.Option("--verbose", "-v")] = False) -> None:
    """Benchmark live caption engines."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


@app.command()
def align(
    clip: str,
    data_dir: DataDir = BENCH_DIR / "data",
) -> None:
    """Build ``refs/<clip>.json`` from the hand-corrected ``refs/<clip>.txt``."""
    config = load_pipeline()
    reference = align_clip(
        data_dir / "refs" / f"{clip}.txt",
        data_dir / "clips" / f"{clip}.wav",
        config,
        SHARED_DIR / config.vad.model,
    )
    target = data_dir / "refs" / f"{clip}.json"
    target.write_text(reference.model_dump_json(indent=2), encoding="utf-8")
    flagged = sum(w.needs_check for w in reference.words)
    log.info("wrote %s (%d words, %d need a check)", target, len(reference.words), flagged)


@app.command()
def run(  # noqa: PLR0913
    engines: Annotated[str, typer.Option(help="Comma-separated engine ids, or 'all'.")] = "all",
    cleanup: Annotated[str, typer.Option(help=f"Any of: {', '.join(CLEANUP_NAMES)}.")] = "none",
    vad: Annotated[str, typer.Option(help="on, off or on,off.")] = "on,off",
    clips: Annotated[str, typer.Option(help="Comma-separated clip ids, or 'all'.")] = "all",
    data_dir: DataDir = BENCH_DIR / "data",
    results_dir: ResultsDir = BENCH_DIR / "results",
) -> None:
    """Stream each clip x engine x cleanup x VAD item at real-time pace."""
    profiles = load_engines()
    wanted = list(profiles) if engines == "all" else _csv(engines)
    unknown = [e for e in wanted if e not in profiles]
    if unknown:
        log.error("unknown engine(s): %s", ", ".join(unknown))
        raise typer.Exit(2)
    config = load_pipeline()
    counts = asyncio.run(
        run_all(
            profiles=[profiles[e] for e in wanted],
            clips=_load_clips(data_dir, clips).values(),
            cleanups=_csv(cleanup),
            vads=_csv(vad),
            config=config,
            model_path=SHARED_DIR / config.vad.model,
            store=ResultsStore(results_dir),
            clock_factory=CLOCK_FACTORY,
            factory=lambda profile, clock: ENGINE_FACTORY(profile, clock, "speech"),
            secrets=load_env(BENCH_DIR / ".env"),
        )
    )
    raise typer.Exit(counts.exit_code())


@app.command()
def score(
    data_dir: DataDir = BENCH_DIR / "data",
    results_dir: ResultsDir = BENCH_DIR / "results",
) -> None:
    """Turn the stored events into ``EvaluationResult`` files."""
    clips = _load_clips(data_dir, "all")
    references = {p.stem: load_reference(p) for p in sorted((data_dir / "refs").glob("*.json"))}
    results = score_all(
        store=ResultsStore(results_dir),
        clips=clips,
        references=references,
        profiles=load_engines(),
        config=load_pipeline(),
        shared_hashes=shared_hashes(),
    )
    log.info("scored %d item(s)", len(results))


@app.command()
def report(
    data_dir: DataDir = BENCH_DIR / "data",
    results_dir: ResultsDir = BENCH_DIR / "results",
) -> None:
    """Write ``results/report.md`` (data only: no recommendations)."""
    text = build_report(load_results(ResultsStore(results_dir)), _load_clips(data_dir, "all"))
    target = results_dir / "report.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    log.info("wrote %s", target)


@app.command("check-engine")
def check_engine_cmd(
    engine_id: str,
    record: Annotated[
        Path | None, typer.Option("--record", help="Save raw vendor messages here.")
    ] = None,
) -> None:
    """Live smoke test of one engine: conformance plus silence producing no text."""
    profiles = load_engines()
    if engine_id not in profiles:
        log.error("unknown engine: %s", engine_id)
        raise typer.Exit(2)
    if record is not None:
        log.error("--record is not supported by the %s adapter yet", profiles[engine_id].adapter)
        raise typer.Exit(2)
    work_dir = BENCH_DIR / "results" / "check"
    work_dir.mkdir(parents=True, exist_ok=True)
    try:
        problems = asyncio.run(
            check_engine(
                profiles[engine_id],
                CLOCK_FACTORY(),
                SHARED_DIR,
                work_dir,
                factory=ENGINE_FACTORY,
                secrets=load_env(BENCH_DIR / ".env"),
            )
        )
    except PrivacyGateError as exc:
        log.exception("privacy gate refused the engine")
        raise typer.Exit(1) from exc
    raise typer.Exit(1 if problems else 0)
