import threading
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Protocol

# Single shared lock for all MLX-based engines. MLX inference is not safe to
# run concurrently on the same Metal device, even across different model classes.
MLX_INFERENCE_LOCK = threading.Lock()


@dataclass(frozen=True)
class TranscriptSegment:
    start: Optional[float]
    end: Optional[float]
    text: Optional[str]


@dataclass(frozen=True)
class TranscriptionResult:
    text: str
    segments: List[TranscriptSegment]
    warnings: List[str]


class AsrEngine(Protocol):
    name: str
    model: str

    def is_available(self) -> bool:
        ...

    def transcribe(self, wav_path: Path, duration_seconds: float) -> TranscriptionResult:
        ...
