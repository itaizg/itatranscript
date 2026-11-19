import sys
import types
from pathlib import Path

import numpy as np
import pytest

from itabench.cleanup import CleanupUnavailableError, fit_length, get_cleanup
from itabench.streaming import read_wav_pcm


@pytest.fixture
def speech(shared: Path) -> np.ndarray:
    return np.frombuffer(read_wav_pcm(shared / "fixtures/speech-short.wav"), dtype=np.int16)


def test_none_returns_same_audio(speech: np.ndarray) -> None:
    out = get_cleanup("none")(speech)
    assert np.array_equal(out, speech)


def test_unknown_cleanup_rejected() -> None:
    with pytest.raises(ValueError, match="unknown cleanup"):
        get_cleanup("magic")


def test_fit_length_trims_and_pads() -> None:
    x = np.arange(5, dtype=np.int16)
    assert len(fit_length(x, 3)) == 3
    assert fit_length(x, 8).tolist() == [0, 1, 2, 3, 4, 0, 0, 0]


def test_rnnoise_keeps_length(speech: np.ndarray) -> None:
    pytest.importorskip("pyrnnoise")
    out = get_cleanup("rnnoise")(speech)
    assert out.dtype == np.int16
    assert len(out) == len(speech)


def test_rnnoise_wrapper_with_stub_backend(
    speech: np.ndarray, monkeypatch: pytest.MonkeyPatch
) -> None:
    class StubRNNoise:
        def __init__(self, sample_rate: int) -> None:
            assert sample_rate == 16000

        def denoise_chunk(self, chunk: np.ndarray, partial: bool = False):  # noqa: ANN202
            for i in range(0, len(chunk) - 100, 480):
                yield 0.0, chunk[None, i : i + 480]

    monkeypatch.setitem(sys.modules, "pyrnnoise", types.SimpleNamespace(RNNoise=StubRNNoise))
    out = get_cleanup("rnnoise")(speech)
    assert len(out) == len(speech)


def test_deepfilternet_wrapper_with_stub_backend(
    speech: np.ndarray, monkeypatch: pytest.MonkeyPatch
) -> None:
    class Tensor:
        def __init__(self, arr: np.ndarray) -> None:
            self.arr = arr

        def __getitem__(self, index: slice | tuple[slice, ...]) -> "Tensor":
            return Tensor(self.arr[index])

        def numpy(self) -> np.ndarray:
            return self.arr

    stubs = {
        "soxr": types.SimpleNamespace(
            resample=lambda x, a, b: np.interp(
                np.linspace(0, len(x) - 1, int(len(x) * b / a)), np.arange(len(x)), x
            ).astype(np.float32)
        ),
        "torch": types.SimpleNamespace(from_numpy=Tensor),
        "df": types.ModuleType("df"),
        "df.enhance": types.SimpleNamespace(
            init_df=lambda: (None, None, None), enhance=lambda m, s, t: t
        ),
    }
    for name, module in stubs.items():
        monkeypatch.setitem(sys.modules, name, module)
    out = get_cleanup("deepfilternet")(speech)
    assert out.dtype == np.int16
    assert len(out) == len(speech)


def test_missing_dependency_is_reported(
    speech: np.ndarray, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setitem(sys.modules, "pyrnnoise", None)
    with pytest.raises(CleanupUnavailableError):
        get_cleanup("rnnoise")(speech)


def test_voiceproc_requires_built_helper(speech: np.ndarray) -> None:
    from itabench.cleanup import voiceproc

    if (voiceproc.TOOL_DIR / ".build/release/apple-speech").exists():
        pytest.skip("helper is built; covered by T036 verify")
    with pytest.raises(CleanupUnavailableError):
        get_cleanup("voiceproc")(speech)
