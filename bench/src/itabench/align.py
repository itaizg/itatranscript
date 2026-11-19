"""``itabench align``: hand-corrected tagged text -> ``Reference`` draft."""

import re
import wave
from collections.abc import Iterator
from pathlib import Path
from typing import Literal

from itabench.models import Interval, PipelineConfig, Reference, RefWord
from itabench.run import gate_frames
from itabench.speech_gate import SpeechGate
from itabench.streaming import read_wav_pcm

MIN_NON_SPEECH_MS = 1000
_LINE = re.compile(r"^(he|en)\s*[:|]\s*(.*)$")
_HEBREW = re.compile("[א-ת]")
_LATIN = re.compile("[A-Za-z]")


class ReferenceTextError(ValueError):
    """A reference line is not tagged ``he:`` or ``en:``."""


def _tag_word(token: str, line_lang: str) -> tuple[str, bool]:
    """Pick a word's language from its script; flag it when unsure."""
    has_he, has_en = bool(_HEBREW.search(token)), bool(_LATIN.search(token))
    if has_he and has_en:
        return line_lang, True
    if has_he:
        return "he", False
    if has_en:
        return "en", False
    return line_lang, any(ch.isdigit() for ch in token)


def parse_reference_text(text: str) -> tuple[RefWord, ...]:
    """Parse ``he: ...`` / ``en: ...`` lines into tagged words.

    A word's language follows its script, so mixed sentences keep both languages.
    Words with digits or mixed scripts are flagged ``needs_check``.
    """
    words: list[RefWord] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip():
            continue
        match = _LINE.match(raw.strip())
        if match is None:
            msg = f"line {number}: expected 'he: ...' or 'en: ...', got {raw!r}"
            raise ReferenceTextError(msg)
        line_lang = match.group(1)
        for token in match.group(2).split():
            lang, unsure = _tag_word(token, line_lang)
            tagged: Literal["he", "en"] = "he" if lang == "he" else "en"
            words.append(RefWord(text=token, lang=tagged, needs_check=unsure))
    return tuple(words)


def _gaps(spans: list[tuple[int, int]], duration_ms: int) -> Iterator[Interval]:
    cursor = 0
    for onset, offset in [*spans, (duration_ms, duration_ms)]:
        if onset - cursor >= MIN_NON_SPEECH_MS:
            yield Interval(start_ms=cursor, end_ms=onset)
        cursor = max(cursor, offset)


def align_clip(
    text_path: Path, wav_path: Path, config: PipelineConfig, model_path: Path
) -> Reference:
    """Build the reference: tagged words plus VAD non-speech intervals >= 1 s."""
    words = parse_reference_text(text_path.read_text(encoding="utf-8"))
    pcm = read_wav_pcm(wav_path)
    with wave.open(str(wav_path), "rb") as wav:
        duration_ms = wav.getnframes() * 1000 // wav.getframerate()
    gate = SpeechGate(config, model_path, enabled=False)
    _, spans, _ = gate_frames(pcm, gate)
    pairs = [(s.onset_ms, s.offset_ms if s.offset_ms is not None else duration_ms) for s in spans]
    return Reference(words=words, non_speech=tuple(_gaps(pairs, duration_ms)), turn_changes_ms=())
