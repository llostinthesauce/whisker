import os
from pathlib import Path
from typing import Any, Optional

from .base import MLX_INFERENCE_LOCK, TranscriptSegment, TranscriptionResult


class Qwen3ASR06BEngine:
    """Qwen3-ASR 0.6B 4-bit MLX ASR engine."""

    name = "qwen3-asr-06b"
    model_name = "mlx-community/Qwen3-ASR-0.6B-4bit"

    def __init__(
        self,
        cache_dir: Optional[Path] = None,
        ffmpeg_path: Optional[str] = None,
    ) -> None:
        self.cache_dir = cache_dir
        self.ffmpeg_path = ffmpeg_path
        self.model = self.model_name.rsplit("/", 1)[-1]
        self._model: Any = None

    def is_available(self) -> bool:
        try:
            from mlx_audio.stt.utils import load_model  # noqa: F401

            return True
        except ImportError:
            return False

    def transcribe(self, wav_path: Path, duration_seconds: float) -> TranscriptionResult:
        if not self.is_available():
            raise RuntimeError("mlx-audio is not installed")

        with MLX_INFERENCE_LOCK:
            self._ensure_ffmpeg_on_path()
            model = self._load_model()
            from mlx_audio.stt.generate import generate_transcription

            result = generate_transcription(
                model=model,
                audio=str(wav_path),
                output_path=str(wav_path.parent / "qwen_transcript"),
                format="txt",
                verbose=False,
            )

        text = str(getattr(result, "text", "") or "").strip()
        raw_segments = getattr(result, "segments", None) or []
        if raw_segments and isinstance(raw_segments[0], dict):
            segments = [
                TranscriptSegment(
                    start=seg.get("start"),
                    end=seg.get("end"),
                    text=seg.get("text"),
                )
                for seg in raw_segments
            ]
        else:
            segments = [TranscriptSegment(start=None, end=None, text=text)]
        return TranscriptionResult(text=text, segments=segments, warnings=[])

    def _ensure_ffmpeg_on_path(self) -> None:
        if not self.ffmpeg_path:
            return
        directory = str(Path(self.ffmpeg_path).expanduser().parent)
        if not directory or directory == ".":
            return
        path_parts = os.environ.get("PATH", "").split(os.pathsep)
        if directory not in path_parts:
            os.environ["PATH"] = os.pathsep.join([directory, *path_parts])

    def _load_model(self) -> Any:
        if self._model is None:
            from mlx_audio.stt.utils import load_model

            kwargs: dict[str, Any] = {}
            if self.cache_dir is not None:
                kwargs["cache_dir"] = str(self.cache_dir)
            self._model = load_model(self.model_name, **kwargs)
        return self._model
