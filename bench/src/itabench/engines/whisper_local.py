"""Local faster-whisper (ivrit.ai checkpoint, used as-is) with a rolling window.

Every ``hop_ms`` of audio the last ``window_s`` seconds are transcribed. The text after the
already-final words is sent as a partial. Words become final once they are the same prefix
in ``stable_hops`` consecutive transcriptions.
"""

import asyncio
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Protocol

import numpy as np

from itabench.contract import register
from itabench.metrics.normalize import normalize_tokens
from itabench.models import (
    AudioFrame,
    ClosedEvent,
    EngineEvent,
    EngineProfile,
    FinalEvent,
    PartialEvent,
    Word,
)

FRAME_MS = 20
FRAME_BYTES = 640
SAMPLE_RATE = 16000


@dataclass(frozen=True)
class TimedWord:
    """A transcribed word with times relative to the start of the audio window (ms)."""

    text: str
    start_ms: int
    end_ms: int


@dataclass(frozen=True)
class Transcript:
    """The transcriber's result for one window."""

    words: tuple[TimedWord, ...]
    lang: str


class Transcriber(Protocol):
    """Speech to timed words. Real: faster-whisper. Tests: a stub."""

    def transcribe(self, audio: np.ndarray, language: str | None) -> Transcript:
        """Transcribe 16 kHz mono float32 audio."""
        ...


def stable_prefix_len(previous: list[str], current: list[str]) -> int:
    """Length of the common word prefix of two normalized word lists."""
    n = 0
    for a, b in zip(previous, current, strict=False):
        if a != b:
            break
        n += 1
    return n


class RollingFinalizer:
    """The finalization policy, kept free of audio and I/O so it is easy to test."""

    def __init__(self, stable_hops: int = 2) -> None:
        """Create a policy that needs ``stable_hops`` agreeing transcriptions."""
        self._stable_hops = stable_hops
        self._history: list[list[str]] = []
        self._finalised_words = 0  # words of the current window already emitted as final
        self._segment = 0

    @property
    def segment_id(self) -> str:
        """Id of the segment currently being built."""
        return f"w{self._segment}"

    def update(
        self, words: tuple[TimedWord, ...], lang: str, base_ms: int, *, flush: bool = False
    ) -> tuple[list[PartialEvent | FinalEvent], int]:
        """Feed one hop's words (window-relative times).

        Returns the events plus how many window words are now final, so the caller can
        trim the window. ``flush`` finalizes everything left (end of stream).
        """
        tokens = [" ".join(normalize_tokens(w.text)) for w in words]
        self._history = [*self._history, tokens][-self._stable_hops :]
        if flush:
            stable = len(words)
        elif len(self._history) < self._stable_hops:
            stable = 0
        else:
            stable = min(
                stable_prefix_len(self._history[0], self._history[i])
                for i in range(1, len(self._history))
            )
        events: list[PartialEvent | FinalEvent] = []
        if stable > 0:
            chunk = words[:stable]
            events.append(self._final(chunk, lang, base_ms))
            self._segment += 1
            self._history = []
        rest = words[stable:]
        if rest and not flush:
            events.append(
                PartialEvent(
                    t_ms=0,
                    segment_id=self.segment_id,
                    text=" ".join(w.text for w in rest),
                    lang="he" if lang == "he" else "en",
                    start_ms=base_ms + rest[0].start_ms,
                    end_ms=base_ms + rest[-1].end_ms,
                )
            )
        return events, stable

    def _final(self, chunk: tuple[TimedWord, ...], lang: str, base_ms: int) -> FinalEvent:
        label = "he" if lang == "he" else "en"
        return FinalEvent(
            t_ms=0,
            segment_id=self.segment_id,
            text=" ".join(w.text for w in chunk),
            lang=label,
            start_ms=base_ms + chunk[0].start_ms,
            end_ms=base_ms + chunk[-1].end_ms,
            words=tuple(
                Word(
                    text=w.text,
                    start_ms=base_ms + w.start_ms,
                    end_ms=base_ms + w.end_ms,
                    lang=label,
                )
                for w in chunk
            ),
        )


class FasterWhisperTranscriber:
    """The real transcriber (optional ``local`` extra); loads the model on first use."""

    def __init__(self, model: str, compute_type: str) -> None:
        """Remember the pinned checkpoint; nothing is downloaded until first use."""
        self._model_id = model
        self._compute_type = compute_type
        self._model: Any = None

    def transcribe(self, audio: np.ndarray, language: str | None) -> Transcript:
        """Transcribe one window with word timestamps."""
        if self._model is None:
            from faster_whisper import WhisperModel  # noqa: PLC0415

            self._model = WhisperModel(
                self._model_id, device="cpu", compute_type=self._compute_type
            )
        segments, info = self._model.transcribe(
            audio, language=language, word_timestamps=True, vad_filter=False
        )
        words = tuple(
            TimedWord(w.word.strip(), int(w.start * 1000), int(w.end * 1000))
            for seg in segments
            for w in (seg.words or ())
            if w.word.strip()
        )
        return Transcript(words=words, lang=str(info.language))


class WhisperLocalEngine:
    """Adapter: buffers audio by time and transcribes a rolling window every hop."""

    version = "faster-whisper (ivrit.ai checkpoint, as-is)"

    def __init__(self, transcriber: Transcriber | None = None) -> None:
        """Create the engine; the real transcriber is built from the profile on ``open``."""
        self._transcriber = transcriber
        self._queue: asyncio.Queue[EngineEvent] = asyncio.Queue()
        self._frames: dict[int, bytes] = {}
        self._window_start_ms = 0
        self._window_ms = 10_000
        self._hop_ms = 1000
        self._next_hop_ms = 1000
        self._language: str | None = None
        self._policy = RollingFinalizer()
        self._cancelled = False
        self._last_ms = 0

    async def open(
        self, profile: EngineProfile, language_mode: str, secrets: dict[str, str]
    ) -> None:
        """Read the pinned options and prepare the policy."""
        del secrets
        opts = profile.options
        self._window_ms = int(opts.get("window_s", 10)) * 1000
        self._hop_ms = int(opts.get("hop_ms", 1000))
        self._next_hop_ms = self._hop_ms
        self._policy = RollingFinalizer(int(opts.get("stable_hops", 2)))
        self._language = language_mode if language_mode in ("he", "en") else None
        if self._transcriber is None:
            self._transcriber = FasterWhisperTranscriber(
                str(opts["model"]), str(opts.get("compute_type", "int8"))
            )

    def _window_audio(self, end_ms: int) -> np.ndarray:
        start = max(self._window_start_ms, end_ms - self._window_ms)
        self._window_start_ms = start
        chunks = [self._frames.get(t, b"\0" * FRAME_BYTES) for t in range(start, end_ms, FRAME_MS)]
        raw = b"".join(chunks)
        return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0

    async def _hop(self, end_ms: int, *, flush: bool = False) -> None:
        assert self._transcriber is not None
        audio = self._window_audio(end_ms)
        base = self._window_start_ms
        transcript = await asyncio.to_thread(self._transcriber.transcribe, audio, self._language)
        events, finalised = self._policy.update(
            transcript.words, transcript.lang, base, flush=flush
        )
        for event in events:
            await self._queue.put(event)
        if finalised:
            self._window_start_ms = base + transcript.words[finalised - 1].end_ms

    async def push_audio(self, frame: AudioFrame) -> None:
        """Store the frame; transcribe whenever a hop of audio has passed."""
        self._frames[frame.t_ms - frame.t_ms % FRAME_MS] = frame.pcm
        self._last_ms = frame.t_ms + FRAME_MS
        while self._last_ms >= self._next_hop_ms and not self._cancelled:
            await self._hop(self._next_hop_ms)
            self._next_hop_ms += self._hop_ms

    async def finish(self) -> None:
        """Finalize whatever is left, then emit ``closed``."""
        if not self._cancelled and self._frames:
            await self._hop(self._last_ms, flush=True)
        await self._queue.put(ClosedEvent(t_ms=0))

    async def cancel(self) -> None:
        """Stop now; ``events()`` ends with ``closed``."""
        self._cancelled = True
        await self._queue.put(ClosedEvent(t_ms=0))

    async def events(self) -> AsyncIterator[EngineEvent]:
        """Yield events until ``closed``."""
        while True:
            event = await self._queue.get()
            yield event
            if isinstance(event, ClosedEvent):
                return


register("whisper_local", WhisperLocalEngine)
