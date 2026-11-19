"""Text normalization before WER/CER (research R-4). Harness-only rules."""

import re
import unicodedata

_NIQQUD = re.compile("[֑-ׇֽֿׁׂׅׄ]")
_FINALS = str.maketrans("ךםןףץ", "כמנפצ")
_GERESH = str.maketrans({"׳": "'", "״": '"', "’": "'", "”": '"'})
_PUNCT = re.compile(r"[^\w'\"\s]|_", re.UNICODE)
_INNER_QUOTE = re.compile(r"(?<![^\W\d_])['\"]|['\"](?![^\W\d_])")

#: Small number lexicon: spoken words map to digits, so "3" equals "three".
NUMBER_WORDS: dict[str, str] = {
    **{
        w: str(i)
        for i, w in enumerate(
            ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        )
    },
    **{
        w: str(i)
        for i, w in enumerate(
            ["אפס", "אחד", "שניים", "שלוש", "ארבע", "חמש", "שש", "שבע", "שמונה", "תשע", "עשר"]
        )
    },
    "אחת": "1",
    "שתיים": "2",
    "שתי": "2",
    "שלושה": "3",
    "ארבעה": "4",
    "חמישה": "5",
    "שישה": "6",
    "שבעה": "7",
    "תשעה": "9",
    "עשרה": "10",
}
_NUMBER_WORDS_FOLDED = {w.translate(_FINALS): d for w, d in NUMBER_WORDS.items()}


def is_hebrew(token: str) -> bool:
    """Return True if the token contains a Hebrew letter."""
    return any("א" <= ch <= "ת" for ch in token)


def normalize_tokens(text: str) -> list[str]:
    """Normalize text into comparison tokens.

    Lowercases, strips niqqud and punctuation, unifies geresh/gershayim, folds final
    letters (comparison only) and maps number words to digits.
    """
    text = unicodedata.normalize("NFKC", text).translate(_GERESH).lower()
    text = _NIQQUD.sub("", text)
    text = text.replace("־", " ").replace("-", " ")
    text = _PUNCT.sub(" ", text)
    text = text.translate(_FINALS)
    tokens = [_INNER_QUOTE.sub("", t) for t in text.split()]
    return [_NUMBER_WORDS_FOLDED.get(t, t) for t in tokens if t]
