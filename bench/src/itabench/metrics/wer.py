"""Word and character error rates, overall and by language."""

from collections.abc import Sequence
from dataclasses import dataclass, field

import jiwer

from itabench.metrics.normalize import is_hebrew, normalize_tokens
from itabench.models import RefWord


@dataclass(frozen=True)
class ErrorRates:
    """WER/CER for one item."""

    wer: float
    cer: float
    wer_by_lang: dict[str, float] = field(default_factory=dict)


def _wer(ref: list[str], hyp: list[str]) -> float:
    if not ref:
        return 0.0 if not hyp else 1.0
    return float(jiwer.wer(" ".join(ref), " ".join(hyp) if hyp else ""))


def _cer(ref: list[str], hyp: list[str]) -> float:
    if not ref:
        return 0.0 if not hyp else 1.0
    return float(jiwer.cer(" ".join(ref), " ".join(hyp)))


def score_text(ref_words: Sequence[RefWord], hypothesis: str) -> ErrorRates:
    """Score a hypothesis against tagged reference words.

    The whole item is scored together. For the by-language split, hypothesis
    tokens are assigned by script (Hebrew letters -> ``he``, else ``en``).
    CER is reported on the Hebrew part when there is one, else on the whole item.
    """
    ref_tokens: list[tuple[str, str]] = []
    for word in ref_words:
        ref_tokens.extend((tok, word.lang) for tok in normalize_tokens(word.text))
    ref_all = [t for t, _ in ref_tokens]
    hyp_all = normalize_tokens(hypothesis)
    by_lang: dict[str, float] = {}
    cer = _cer(ref_all, hyp_all)
    for lang in ("he", "en"):
        ref_l = [t for t, lg in ref_tokens if lg == lang]
        if not ref_l:
            continue
        hyp_l = [t for t in hyp_all if is_hebrew(t) == (lang == "he")]
        by_lang[lang] = _wer(ref_l, hyp_l)
        if lang == "he":
            cer = _cer(ref_l, hyp_l)
    return ErrorRates(wer=_wer(ref_all, hyp_all), cer=cer, wer_by_lang=by_lang)
