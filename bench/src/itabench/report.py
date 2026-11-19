"""``itabench report``: data tables only. No recommendations, no thresholds (XI)."""

from collections import defaultdict
from collections.abc import Mapping, Sequence
from statistics import mean

from itabench.models import EvaluationResult, TestClip

NORMALIZATION_RULES = """\
Scores use the shared normalization (research R-4): lowercase; punctuation and niqqud
removed; geresh/gershayim unified; final Hebrew letters folded for comparison only;
digits and number words mapped to one form. Mixed clips are scored as a whole and also
split by language tag. CER is computed on the Hebrew part when a clip has one."""

LANGUAGES = (("he", "Hebrew"), ("en", "English"), ("mixed", "Mixed Hebrew/English"))
_COLUMNS = (
    "Engine | Situation | Cleanup | VAD | Clips | WER | CER | WER he | WER en | "
    "Prov p50 ms | Prov p90 ms | Final p50 ms | Final p90 ms | Made-up words | "
    "Speaker recall | $/h"
)


def _avg(values: Sequence[float | None], digits: int = 3) -> str:
    present = [v for v in values if v is not None]
    return f"{mean(present):.{digits}f}" if present else "-"


def _lang_wer(results: Sequence[EvaluationResult], lang: str) -> str:
    return _avg([r.wer_by_lang.get(lang) for r in results])


def _row(key: tuple[str, str, str, str], results: Sequence[EvaluationResult]) -> str:
    engine, situation, cleanup, vad = key
    ok = [r for r in results if r.status == "ok"]
    cost = [r.cost_usd_per_hour for r in ok]
    cells = [
        engine,
        situation,
        cleanup,
        vad,
        str(len(ok)),
        _avg([r.wer for r in ok]),
        _avg([r.cer for r in ok]),
        _lang_wer(ok, "he"),
        _lang_wer(ok, "en"),
        _avg([r.ttp_p50_ms for r in ok], 0),
        _avg([r.ttp_p90_ms for r in ok], 0),
        _avg([r.ttf_p50_ms for r in ok], 0),
        _avg([r.ttf_p90_ms for r in ok], 0),
        _avg([None if r.made_up_words is None else float(r.made_up_words) for r in ok], 1),
        _avg([r.speaker_change_recall for r in ok], 2),
        _avg(cost, 2),
    ]
    return "| " + " | ".join(cells) + " |"


def _sort_key(key: tuple[str, str, str, str]) -> tuple[str, str, int, str, str]:
    engine, situation, cleanup, vad = key
    return (engine, situation, 0 if cleanup == "none" else 1, cleanup, vad)


def build_report(results: Sequence[EvaluationResult], clips: Mapping[str, TestClip]) -> str:
    """Render ``report.md`` from scored results."""
    lines = ["# Benchmark report", "", "## Normalization rules", "", NORMALIZATION_RULES, ""]
    lines += [
        "Lower is better for WER, CER, latency and made-up words. Each cleanup / VAD variant",
        "sits next to the baseline (`none`) for the same engine and situation.",
        "",
    ]
    ok = [r for r in results if r.status == "ok" and r.clip_id in clips]
    for lang, title in LANGUAGES:
        lines += [f"## {title}", ""]
        groups: dict[tuple[str, str, str, str], list[EvaluationResult]] = defaultdict(list)
        for r in ok:
            clip = clips[r.clip_id]
            if clip.lang == lang:
                groups[(r.engine_id, clip.situation, r.cleanup, r.vad)].append(r)
        if not groups:
            lines += ["No clips scored for this language.", ""]
            continue
        lines += [f"| {_COLUMNS} |", "|" + "---|" * len(_COLUMNS.split("|"))]
        lines += [_row(k, groups[k]) for k in sorted(groups, key=_sort_key)]
        lines.append("")
    failed = [r for r in results if r.status == "failed"]
    lines += [f"Failed items: {len(failed)}", "", "## Provenance", ""]
    lines += ["| Engine | Version | Harness | Clips (sha256 prefix) |", "|---|---|---|---|"]
    seen: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    shared: dict[str, str] = {}
    for r in results:
        seen[(r.engine_id, r.engine_version, r.harness_version)].add(r.clip_sha256[:10])
        shared.update(r.shared_hashes)
    lines += [
        f"| {e} | {v} | {h} | {', '.join(sorted(c))} |" for (e, v, h), c in sorted(seen.items())
    ]
    lines += ["", "Shared files (sha256):", ""]
    lines += [f"- `{name}`: `{digest}`" for name, digest in sorted(shared.items())]
    return "\n".join(lines) + "\n"
