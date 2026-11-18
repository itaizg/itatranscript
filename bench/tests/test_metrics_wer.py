from itabench.metrics.normalize import normalize_tokens
from itabench.metrics.wer import score_text
from itabench.models import RefWord


def test_niqqud_stripped() -> None:
    assert normalize_tokens("שָׁלוֹם") == normalize_tokens("שלום")


def test_final_letters_folded() -> None:
    assert normalize_tokens("סוף") == normalize_tokens("סופ")


def test_geresh_unified_and_punctuation_dropped() -> None:
    assert normalize_tokens("ג׳ירפה, כן!") == ["ג'ירפה", "כנ"]
    assert normalize_tokens("Hello, World.") == ["hello", "world"]


def test_digits_and_words_match() -> None:
    assert normalize_tokens("three") == normalize_tokens("3")
    assert normalize_tokens("שלוש") == ["3"]


def test_by_language_split_of_mixed_reference() -> None:
    ref = [RefWord(text="שלום", lang="he"), RefWord(text="meeting", lang="en")]
    rates = score_text(ref, "שלום metting")
    assert rates.wer_by_lang["he"] == 0.0
    assert rates.wer_by_lang["en"] == 1.0
    assert rates.wer == 0.5


def test_hebrew_cer_is_character_level() -> None:
    ref = [RefWord(text="שלומות", lang="he")]
    rates = score_text(ref, "שלומתת")
    assert rates.wer == 1.0
    assert 0 < rates.cer < 1


def test_empty_hypothesis_is_full_error() -> None:
    assert score_text([RefWord(text="hello", lang="en")], "").wer == 1.0
