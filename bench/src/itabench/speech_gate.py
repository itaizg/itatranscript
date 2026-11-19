"""Streaming Silero VAD gate: drops silence, keeps padded speech, records spans."""

from collections import deque
from pathlib import Path

import numpy as np
import onnxruntime as ort

from itabench.models import AudioFrame, PipelineConfig, SpeechSpan

CHUNK = 512  # samples per Silero step at 16 kHz (32 ms)
CONTEXT = 64
SAMPLE_RATE = 16000
FRAME_MS = 20


class SpeechGate:
    """Runs the shared VAD over 20 ms frames.

    Spans are always tracked (latency needs them). With ``enabled=False`` every
    frame passes through; otherwise only speech plus padding does.
    """

    def __init__(self, config: PipelineConfig, model_path: Path, *, enabled: bool = True) -> None:
        """Load the ONNX model and reset state."""
        self._cfg = config.vad
        self._enabled = enabled
        options = ort.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 1
        self._session = ort.InferenceSession(str(model_path), sess_options=options)
        self.spans: list[SpeechSpan] = []
        self._state = np.zeros((2, 1, 128), dtype=np.float32)
        self._context = np.zeros((1, CONTEXT), dtype=np.float32)
        self._samples = np.zeros(0, dtype=np.float32)
        self._probs_end_ms = 0
        self._speech_run_ms = 0
        self._silence_run_ms = 0
        self._run_start_ms = 0
        self._in_speech = False
        self._onset_ms = 0
        self._last_speech_end_ms = 0
        self._tail_until_ms = -1
        self._pre: deque[AudioFrame] = deque(maxlen=max(1, self._cfg.pad_ms // FRAME_MS))

    def _speech_prob(self, chunk: np.ndarray) -> float:
        x = np.concatenate([self._context, chunk[None, :]], axis=1)
        out, state = self._session.run(
            None,
            {
                "input": x,
                "state": self._state,
                "sr": np.array(SAMPLE_RATE, dtype=np.int64),
            },
        )
        self._state = np.asarray(state, dtype=np.float32)
        self._context = x[:, -CONTEXT:]
        return float(np.asarray(out).reshape(-1)[0])

    def _step(self, prob: float) -> None:
        chunk_ms = CHUNK * 1000 // SAMPLE_RATE
        start = self._probs_end_ms
        end = start + chunk_ms
        self._probs_end_ms = end
        if prob >= self._cfg.threshold:
            if self._speech_run_ms == 0:
                self._run_start_ms = start
            self._speech_run_ms += chunk_ms
            self._silence_run_ms = 0
            if not self._in_speech and self._speech_run_ms >= self._cfg.min_speech_ms:
                self._in_speech = True
                self._onset_ms = self._run_start_ms
                self._tail_until_ms = -1
            if self._in_speech:
                self._last_speech_end_ms = end
        else:
            self._speech_run_ms = 0
            self._silence_run_ms += chunk_ms
            if self._in_speech and self._silence_run_ms >= self._cfg.min_silence_ms:
                self._close_span()

    def _close_span(self) -> None:
        self._in_speech = False
        self.spans.append(SpeechSpan(onset_ms=self._onset_ms, offset_ms=self._last_speech_end_ms))
        self._tail_until_ms = self._last_speech_end_ms + self._cfg.pad_ms

    def push(self, frame: AudioFrame) -> tuple[AudioFrame, ...]:
        """Feed one frame and return the frames to pass on to the engine."""
        pcm = np.frombuffer(frame.pcm, dtype=np.int16).astype(np.float32) / 32768.0
        self._samples = np.concatenate([self._samples, pcm])
        was_in_speech = self._in_speech
        while len(self._samples) >= CHUNK:
            chunk, self._samples = self._samples[:CHUNK], self._samples[CHUNK:]
            self._step(self._speech_prob(chunk))
        if not self._enabled:
            return (frame,)
        if self._in_speech:
            out: list[AudioFrame] = []
            if not was_in_speech:
                out.extend(self._pre)
                self._pre.clear()
            out.append(frame)
            return tuple(out)
        if frame.t_ms < self._tail_until_ms:
            return (frame,)
        self._pre.append(frame)
        return ()

    def finish(self) -> None:
        """Close a span left open at the end of the stream."""
        if self._in_speech:
            self._close_span()
