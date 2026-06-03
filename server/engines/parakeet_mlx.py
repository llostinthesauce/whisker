import importlib.util
import os
import threading
from pathlib import Path
from typing import Any, Optional

from .base import TranscriptSegment, TranscriptionResult


class ParakeetMlxEngine:
    name = "parakeet-mlx"

    def __init__(
        self,
        model_name: str,
        cache_dir: Optional[Path] = None,
        ffmpeg_path: Optional[str] = None,
    ) -> None:
        self.model_name = model_name
        self.cache_dir = cache_dir
        self.ffmpeg_path = ffmpeg_path
        self.model = model_name.rsplit("/", 1)[-1]
        self._model: Any = None
        # Serializes lazy load + inference. The cached MLX model is shared across
        # the server's worker threads (streaming dictation uploads segments
        # concurrently), and MLX inference is not safe to enter concurrently on a
        # single model instance.
        self._lock = threading.Lock()

    def is_available(self) -> bool:
        return importlib.util.find_spec("parakeet_mlx") is not None

    def transcribe(self, wav_path: Path, duration_seconds: float) -> TranscriptionResult:
        if not self.is_available():
            raise RuntimeError("parakeet-mlx is not installed")

        with self._lock:
            self._ensure_ffmpeg_on_path()
            model = self._load_model()
            result = model.transcribe(str(wav_path))
        text = str(getattr(result, "text", "") or "").strip()
        segments = [
            TranscriptSegment(
                start=getattr(sentence, "start", None),
                end=getattr(sentence, "end", None),
                text=getattr(sentence, "text", None),
            )
            for sentence in getattr(result, "sentences", []) or []
        ]
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
            from parakeet_mlx import from_pretrained

            kwargs: dict[str, Any] = {}
            if self.cache_dir is not None:
                kwargs["cache_dir"] = str(self.cache_dir)
            self._model = from_pretrained(self.model_name, **kwargs)
        return self._model
