import re
import shutil
import subprocess
from pathlib import Path
from typing import Iterable, List, Sequence

from .base import TranscriptSegment, TranscriptionResult


_TIMESTAMP_RE = re.compile(r"^\s*\[[^\]]+\]\s*")
_NOISE_PREFIXES = (
    "whisper_",
    "ggml_",
    "main:",
    "system_info:",
    "print_timings:",
    "load time",
    "falling back",
)


class WhisperCppEngine:
    name = "whisper.cpp"

    def __init__(
        self,
        cli_path: str,
        model_path: Path,
        extra_args: Sequence[str],
        timeout_seconds: int,
    ) -> None:
        self.cli_path = cli_path
        self.model_path = model_path
        self.extra_args = tuple(extra_args)
        self.timeout_seconds = timeout_seconds
        self.model = model_path.stem

    def is_available(self) -> bool:
        return bool(shutil.which(self.cli_path)) and self.model_path.is_file()

    def transcribe(self, wav_path: Path, duration_seconds: float) -> TranscriptionResult:
        if not self.model_path.is_file():
            raise RuntimeError(f"Whisper model not found: {self.model_path}")
        if not shutil.which(self.cli_path):
            raise RuntimeError(f"whisper.cpp CLI not found: {self.cli_path}")

        cmd = [
            self.cli_path,
            "--model",
            str(self.model_path),
            *self.extra_args,
            str(wav_path),
        ]
        completed = subprocess.run(
            cmd,
            timeout=self.timeout_seconds,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            detail = _safe_error(completed.stderr or completed.stdout)
            raise RuntimeError(f"whisper.cpp failed: {detail}")

        text = parse_whisper_output(completed.stdout)
        return TranscriptionResult(text=text, segments=[], warnings=[])


def parse_whisper_output(stdout: str) -> str:
    lines = list(_transcript_lines(stdout.splitlines()))
    if not lines:
        return ""
    return " ".join(lines).strip()


def _transcript_lines(lines: Iterable[str]) -> Iterable[str]:
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        lowered = line.lower()
        if lowered.startswith(_NOISE_PREFIXES):
            continue
        if "processing '" in lowered and "samples" in lowered:
            continue
        line = _TIMESTAMP_RE.sub("", line).strip()
        if line:
            yield line


def _safe_error(output: str) -> str:
    lines: List[str] = []
    for line in output.splitlines():
        stripped = line.strip()
        if stripped:
            lines.append(stripped)
        if len(lines) >= 3:
            break
    return " | ".join(lines) or "unknown error"
