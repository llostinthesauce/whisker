import subprocess
from pathlib import Path
from typing import Optional


class AudioError(Exception):
    """Raised when uploaded audio cannot be inspected or converted."""


def probe_duration_seconds(ffprobe_path: str, audio_path: Path, timeout: int = 30) -> Optional[float]:
    cmd = [
        ffprobe_path,
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(audio_path),
    ]
    completed = subprocess.run(
        cmd,
        timeout=timeout,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise AudioError("Could not read audio duration")

    raw = completed.stdout.strip()
    if not raw or raw == "N/A":
        return None
    try:
        return float(raw)
    except ValueError:
        raise AudioError("Invalid audio duration")


def convert_to_wav(
    ffmpeg_path: str,
    input_path: Path,
    output_path: Path,
    timeout: int = 300,
) -> None:
    cmd = [
        ffmpeg_path,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(input_path),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-f",
        "wav",
        str(output_path),
    ]
    completed = subprocess.run(
        cmd,
        timeout=timeout,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise AudioError("Could not convert audio")
