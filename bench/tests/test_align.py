import wave
from pathlib import Path

import pytest

from itabench.align import ReferenceTextError, align_clip, parse_reference_text
from itabench.profiles import load_pipeline


def test_words_follow_their_script_and_flag_uncertain_ones() -> None:
    words = parse_reference_text("he: שלום world 3\nen: hello עולם abc1\n")
    assert [(w.text, w.lang, w.needs_check) for w in words] == [
        ("שלום", "he", False),
        ("world", "en", False),
        ("3", "he", True),
        ("hello", "en", False),
        ("עולם", "he", False),
        ("abc1", "en", False),
    ]


def test_untagged_line_is_rejected() -> None:
    with pytest.raises(ReferenceTextError, match="line 2"):
        parse_reference_text("en: ok\nno tag here\n")


def test_non_speech_gap_before_speech(shared: Path, tmp_path: Path) -> None:
    config = load_pipeline()
    wav = tmp_path / "clip.wav"
    with (
        wave.open(str(shared / "fixtures/silence-5s.wav"), "rb") as a,
        wave.open(str(shared / "fixtures/speech-short.wav"), "rb") as b,
        wave.open(str(wav), "wb") as out,
    ):
        out.setparams(a.getparams())
        out.writeframes(a.readframes(a.getnframes()) + b.readframes(b.getnframes()))
    text = tmp_path / "clip.txt"
    text.write_text("en: hello world\n", encoding="utf-8")
    ref = align_clip(text, wav, config, shared / config.vad.model)
    assert [w.text for w in ref.words] == ["hello", "world"]
    assert ref.turn_changes_ms == ()
    first = ref.non_speech[0]
    assert first.start_ms == 0
    assert 4500 <= first.end_ms <= 5500
