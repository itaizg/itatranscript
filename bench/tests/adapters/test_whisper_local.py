import numpy as np

from itabench.engines.whisper_local import (
    RollingFinalizer,
    TimedWord,
    Transcript,
    WhisperLocalEngine,
)
from itabench.models import AudioFrame, ClosedEvent, FinalEvent, PartialEvent
from itabench.profiles import load_engines


def words(*texts: str) -> tuple[TimedWord, ...]:
    return tuple(TimedWord(t, i * 400, i * 400 + 300) for i, t in enumerate(texts))


def test_prefix_becomes_final_only_after_two_agreeing_hops() -> None:
    policy = RollingFinalizer(stable_hops=2)
    events, finalised = policy.update(words("hello", "wor"), "en", 0)
    assert [type(e) for e in events] == [PartialEvent]
    assert finalised == 0
    events, finalised = policy.update(words("hello", "world", "again"), "en", 0)
    finals = [e for e in events if isinstance(e, FinalEvent)]
    assert [f.text for f in finals] == ["hello"]
    assert finalised == 1
    assert [e.text for e in events if isinstance(e, PartialEvent)] == ["world again"]


def test_disagreeing_hops_never_finalize() -> None:
    policy = RollingFinalizer(stable_hops=2)
    policy.update(words("one", "two"), "en", 0)
    events, finalised = policy.update(words("won", "two"), "en", 0)
    assert finalised == 0
    assert not any(isinstance(e, FinalEvent) for e in events)


def test_segment_ids_are_unique_and_a_final_is_never_repeated() -> None:
    policy = RollingFinalizer(stable_hops=2)
    seen: list[str] = []
    for hop in (words("a", "b"), words("a", "b", "c"), words("c", "d"), words("c", "d", "e")):
        events, _ = policy.update(hop, "en", 0)
        seen += [e.segment_id for e in events if isinstance(e, FinalEvent)]
    assert len(seen) == len(set(seen))


def test_flush_finalizes_the_rest() -> None:
    policy = RollingFinalizer(stable_hops=2)
    policy.update(words("last", "words"), "he", 0)
    events, _ = policy.update(words("last", "words"), "he", 0, flush=True)
    finals = [e for e in events if isinstance(e, FinalEvent)]
    assert [f.text for f in finals] == ["last words"]
    assert finals[0].lang == "he"


class ScriptedTranscriber:
    """Returns a growing sentence, one more word per call."""

    def __init__(self) -> None:
        self.calls = 0
        self.window_sizes: list[int] = []

    def transcribe(self, audio: np.ndarray, language: str | None) -> Transcript:
        self.window_sizes.append(len(audio))
        self.calls += 1
        sentence = ("one", "two", "three", "four", "five", "six")[: self.calls + 1]
        return Transcript(words=words(*sentence), lang="en")


async def test_engine_emits_partials_then_finals_and_closes() -> None:
    transcriber = ScriptedTranscriber()
    engine = WhisperLocalEngine(transcriber)
    profile = load_engines()["whisper-ivrit-local"]
    await engine.open(profile, "en", {})
    for seq in range(150):  # 3 s of audio -> 3 hops
        await engine.push_audio(AudioFrame(seq=seq, t_ms=seq * 20, pcm=b"\x01\x00" * 320))
    await engine.finish()
    events = [e async for e in engine.events()]
    assert transcriber.calls == 4  # 3 hops + the flush
    assert isinstance(events[-1], ClosedEvent)
    assert any(isinstance(e, PartialEvent) for e in events)
    finals = [e for e in events if isinstance(e, FinalEvent)]
    assert finals
    assert len({f.segment_id for f in finals}) == len(finals)
    assert max(transcriber.window_sizes) <= 10 * 16000


async def test_cancel_still_ends_with_closed() -> None:
    engine = WhisperLocalEngine(ScriptedTranscriber())
    await engine.open(load_engines()["whisper-ivrit-local"], "he", {})
    await engine.cancel()
    assert [type(e) for e in [e async for e in engine.events()]] == [ClosedEvent]
