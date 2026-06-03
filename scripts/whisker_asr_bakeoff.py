#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


BASE_CLIPS = {
    "short_message": (
        "Text Wayne that I am running five minutes late, and I will call when I am close."
    ),
    "medium_project": (
        "Draft a quick project update. The local route is healthy again, the server is capped at five minutes, "
        "and I want balanced accuracy without waiting around for a slow model. Please keep punctuation, names, and numbers readable."
    ),
    "long_note": (
        "Here is a longer dictation test for Whisker. First, confirm that the transcript keeps names, numbers, "
        "and punctuation in reasonable shape. Second, compare how quickly each speech model returns usable text. "
        "Third, pay attention to whether the model drops words, repeats phrases, or ignores sentence boundaries. "
        "This should feel similar to a real note captured from the iPhone while walking around the house. "
        "The decision is not only which model has the lowest latency, but which one has the best tradeoff for messages, "
        "notes, and hands-free keyboard dictation."
    ),
}

BASE_CLIPS["two_minute_note"] = " ".join(
    [
        BASE_CLIPS["long_note"],
        "Now add a second paragraph with more practical content.",
        "Schedule a reminder for Tuesday at 9 AM, mention the number forty seven, and include the phrase local network fallback.",
        "The model should avoid repeating itself, should not invent extra tasks, and should preserve the rough sentence structure.",
    ]
    * 3
)

DEFAULT_BAKEOFF_MODELS = "fast,balanced"


def bakeoff_extra_profiles(whisper_model: str) -> List[Dict[str, str]]:
    return [
        {
            "id": "parakeet-v2",
            "label": "Parakeet 0.6B v2",
            "engine": "parakeet_mlx",
            "model": "mlx-community/parakeet-tdt-0.6b-v2",
            "speed": "medium",
            "description": "Benchmark candidate Parakeet TDT 0.6B v2 model.",
        },
        {
            "id": "parakeet-v2-sonic",
            "label": "Parakeet 0.6B v2 Sonic",
            "engine": "parakeet_mlx",
            "model": "sonic-speech/parakeet-tdt-0.6b-v2",
            "speed": "medium",
            "description": "Fallback benchmark candidate for Parakeet TDT 0.6B v2.",
        },
        {
            "id": "whisper-turbo-q5",
            "label": "Whisper Large v3 Turbo Q5",
            "engine": "whisper_cpp",
            "model": "ggml-large-v3-turbo-q5_0.bin",
            "speed": "medium",
            "description": "whisper.cpp large-v3-turbo q5_0 benchmark candidate.",
        },
        {
            "id": "whisper-turbo",
            "label": "Whisper Large v3 Turbo F16",
            "engine": "whisper_cpp",
            "model": whisper_model,
            "speed": "medium",
            "description": "whisper.cpp large-v3-turbo benchmark candidate.",
        },
        {
            "id": "distil-v3",
            "label": "Distil Whisper Large v3",
            "engine": "whisper_cpp",
            "model": "ggml-distil-large-v3.bin",
            "speed": "medium",
            "description": "whisper.cpp distil-large-v3 benchmark candidate.",
        },
        {
            "id": "distil-v35",
            "label": "Distil Whisper Large v3.5",
            "engine": "whisper_cpp",
            "model": "ggml-distil-large-v3.5.bin",
            "speed": "medium",
            "description": "whisper.cpp distil-large-v3.5 benchmark candidate.",
        },
    ]


def run(cmd: Sequence[str], timeout: int, env: Optional[Mapping[str, str]] = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(cmd),
        timeout=timeout,
        check=False,
        capture_output=True,
        text=True,
        env=dict(env) if env is not None else None,
    )


def checked(cmd: Sequence[str], timeout: int, label: str) -> subprocess.CompletedProcess:
    result = run(cmd, timeout)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{label} failed: {detail}")
    return result


def require_file(path: str, label: str) -> None:
    if not Path(path).exists():
        raise RuntimeError(f"{label} not found at {path}")


def append_status(out_dir: Path, line: str) -> None:
    stamp = dt.datetime.now(dt.timezone.utc).isoformat()
    with (out_dir / "STATUS.md").open("a") as handle:
        handle.write(f"- {stamp} {line}\n")


def write_initial_status(out_dir: Path, args: argparse.Namespace) -> None:
    (out_dir / "STATUS.md").write_text(
        "\n".join(
            [
                "# Whisker ASR Bakeoff Status",
                "",
                "Resume phases:",
                "1. Generate deterministic say-based clean WAV clips.",
                "2. Add pink-noise variants for all non-two-minute clips.",
                "3. Optionally start a temporary Whisker server with benchmark profiles.",
                "4. POST every requested model/clip/variant to /v1/transcribe with cleanup_mode=raw.",
                "5. Write results.jsonl, summary.json, raw response JSON, and this status file.",
                "",
                f"Requested models: {args.models}",
                f"Base URL: {args.base_url}",
                f"Iterations: {args.iterations}",
                "",
            ]
        )
    )


def duration_seconds(ffprobe: str, path: Path) -> float:
    result = checked(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        timeout=60,
        label=f"ffprobe {path.name}",
    )
    return float(result.stdout.strip())


def make_clean_clip(out_dir: Path, ffmpeg: str, text: str, name: str) -> Path:
    aiff = out_dir / "sources" / f"{name}.aiff"
    wav = out_dir / "clips" / f"{name}-clean.wav"
    aiff.parent.mkdir(parents=True, exist_ok=True)
    wav.parent.mkdir(parents=True, exist_ok=True)
    checked(["/usr/bin/say", "-o", str(aiff), text], timeout=300, label=f"say {name}")
    checked(
        [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(aiff),
            "-ar",
            "16000",
            "-ac",
            "1",
            str(wav),
        ],
        timeout=300,
        label=f"ffmpeg clean {name}",
    )
    return wav


def make_noisy_variant(ffmpeg: str, ffprobe: str, clean_path: Path, clip_name: str, out_dir: Path) -> Path:
    noisy = out_dir / "clips" / f"{clip_name}-pink_noise.wav"
    duration = duration_seconds(ffprobe, clean_path)
    checked(
        [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(clean_path),
            "-filter_complex",
            f"anoisesrc=color=pink:amplitude=0.018:d={duration}[n];[0:a][n]amix=inputs=2:duration=first:normalize=0",
            "-ar",
            "16000",
            "-ac",
            "1",
            str(noisy),
        ],
        timeout=300,
        label=f"ffmpeg noisy {clip_name}",
    )
    return noisy


def build_clips(out_dir: Path, ffmpeg: str, ffprobe: str) -> List[Dict[str, Any]]:
    clips = []
    for clip_name, reference in BASE_CLIPS.items():
        clean_path = make_clean_clip(out_dir, ffmpeg, reference, clip_name)
        clips.append(
            {
                "clip": clip_name,
                "variant": "clean",
                "path": clean_path,
                "reference": reference,
            }
        )
        if clip_name != "two_minute_note":
            noisy_path = make_noisy_variant(ffmpeg, ffprobe, clean_path, clip_name, out_dir)
            clips.append(
                {
                    "clip": clip_name,
                    "variant": "pink_noise",
                    "path": noisy_path,
                    "reference": reference,
                }
            )
    return clips


def normalize_words(text: str) -> List[str]:
    text = text.lower().replace("-", " ")
    text = re.sub(r"[^a-z0-9']+", " ", text)
    return [word for word in text.split() if word]


def edit_distance(a: Sequence[str], b: Sequence[str]) -> int:
    previous = list(range(len(b) + 1))
    for i, token_a in enumerate(a, 1):
        current = [i]
        for j, token_b in enumerate(b, 1):
            current.append(
                min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (0 if token_a == token_b else 1),
                )
            )
        previous = current
    return previous[-1]


def word_error_rate(reference: str, hypothesis: str) -> Optional[float]:
    ref_words = normalize_words(reference)
    hyp_words = normalize_words(hypothesis)
    if not ref_words:
        return None
    return edit_distance(ref_words, hyp_words) / len(ref_words)


def score_text(reference: str, hypothesis: str) -> Dict[str, Optional[float]]:
    punctuation_chars = ".?!,:;"
    ref_punc = sum(1 for char in reference if char in punctuation_chars)
    hyp_punc = sum(1 for char in hypothesis if char in punctuation_chars)
    ref_upper_words = sum(1 for word in reference.split() if any(char.isupper() for char in word))
    hyp_upper_words = sum(1 for word in hypothesis.split() if any(char.isupper() for char in word))
    return {
        "wer": word_error_rate(reference, hypothesis),
        "ref_words": float(len(normalize_words(reference))),
        "hyp_words": float(len(normalize_words(hypothesis))),
        "punctuation_ratio": (hyp_punc / ref_punc) if ref_punc else None,
        "uppercase_word_ratio": (hyp_upper_words / ref_upper_words) if ref_upper_words else None,
    }


def parse_json_output(raw: str) -> Dict[str, Any]:
    try:
        data = json.loads(raw or "{}")
    except json.JSONDecodeError:
        return {"raw": raw}
    return data if isinstance(data, dict) else {"raw": data}


def fetch_health(base_url: str, token: str, max_time: int) -> Dict[str, Any]:
    result = run(
        [
            "/usr/bin/curl",
            "-sS",
            "--max-time",
            str(max_time),
            "-H",
            f"Authorization: Bearer {token}",
            f"{base_url.rstrip('/')}/v1/health",
        ],
        timeout=max_time + 5,
    )
    if result.returncode != 0:
        raise RuntimeError(f"health check failed: {result.stderr.strip() or result.stdout.strip()}")
    health = parse_json_output(result.stdout)
    if health.get("ok") is not True:
        raise RuntimeError(f"health check returned non-ok response: {result.stdout[:500]}")
    return health


def post_transcription(
    base_url: str,
    token: str,
    clip: Mapping[str, Any],
    model_id: str,
    iteration: int,
    max_time: int,
    out_dir: Path,
) -> Dict[str, Any]:
    response_path = out_dir / f"{model_id}-{clip['clip']}-{clip['variant']}-{iteration}.json"
    curl = run(
        [
            "/usr/bin/curl",
            "-sS",
            "--max-time",
            str(max_time),
            "-o",
            str(response_path),
            "-w",
            '{"http_code":%{http_code},"time_total":%{time_total}}',
            "-H",
            f"Authorization: Bearer {token}",
            "-F",
            f"file=@{clip['path']}",
            "-F",
            "cleanup_mode=raw",
            "-F",
            f"model_id={model_id}",
            "-F",
            "return_cleaned=false",
            f"{base_url.rstrip('/')}/v1/transcribe",
        ],
        timeout=max_time + 30,
    )
    record: Dict[str, Any] = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "model_id": model_id,
        "clip": clip["clip"],
        "variant": clip["variant"],
        "iteration": iteration,
        "reference": clip["reference"],
        "audio_path": str(clip["path"]),
        "curl_returncode": curl.returncode,
        "curl_stderr": curl.stderr.strip(),
    }
    record.update(parse_json_output(curl.stdout))
    if response_path.exists():
        raw = response_path.read_text()
        try:
            response = json.loads(raw)
        except json.JSONDecodeError:
            record["raw_response"] = raw[:1000]
        else:
            text = str(response.get("text") or "")
            record.update(
                {
                    "response": response,
                    "text": text,
                    "text_preview": text[:260],
                    "duration_seconds": response.get("duration_seconds"),
                    "processing_seconds": response.get("processing_seconds"),
                    "server_engine": response.get("engine"),
                    "server_model": response.get("model"),
                }
            )
            record.update(score_text(str(clip["reference"]), text))
    return record


def median(values: Iterable[Any]) -> Optional[float]:
    numbers = [value for value in values if isinstance(value, (int, float))]
    return float(statistics.median(numbers)) if numbers else None


def percentile(values: Iterable[Any], percent: float) -> Optional[float]:
    numbers = sorted(value for value in values if isinstance(value, (int, float)))
    if not numbers:
        return None
    if len(numbers) == 1:
        return float(numbers[0])
    rank = (len(numbers) - 1) * percent
    lower = int(rank)
    upper = min(lower + 1, len(numbers) - 1)
    weight = rank - lower
    return float(numbers[lower] * (1 - weight) + numbers[upper] * weight)


def summarize_group(records: List[Mapping[str, Any]], key_fields: Sequence[str]) -> List[Dict[str, Any]]:
    grouped: Dict[Tuple[Any, ...], Dict[str, Any]] = {}
    for record in records:
        key = tuple(record.get(field) for field in key_fields)
        bucket = grouped.setdefault(
            key,
            {
                "records": [],
                "processing_seconds": [],
                "time_total": [],
                "rtf": [],
                "wer": [],
                "punctuation_ratio": [],
                "uppercase_word_ratio": [],
            },
        )
        bucket["records"].append(record)
        if record.get("http_code") == 200:
            duration = record.get("duration_seconds")
            processing = record.get("processing_seconds")
            bucket["processing_seconds"].append(processing)
            bucket["time_total"].append(record.get("time_total"))
            bucket["wer"].append(record.get("wer"))
            bucket["punctuation_ratio"].append(record.get("punctuation_ratio"))
            bucket["uppercase_word_ratio"].append(record.get("uppercase_word_ratio"))
            if isinstance(duration, (int, float)) and duration > 0 and isinstance(processing, (int, float)):
                bucket["rtf"].append(processing / duration)

    rows = []
    for key, bucket in grouped.items():
        sample = bucket["records"][0]
        row: Dict[str, Any] = {field: value for field, value in zip(key_fields, key)}
        row.update(
            {
                "runs": len(bucket["records"]),
                "successful_runs": sum(1 for record in bucket["records"] if record.get("http_code") == 200),
                "failed_runs": sum(1 for record in bucket["records"] if record.get("http_code") != 200),
                "server_engine": sample.get("server_engine"),
                "server_model": sample.get("server_model"),
                "median_processing_seconds": median(bucket["processing_seconds"]),
                "p95_processing_seconds": percentile(bucket["processing_seconds"], 0.95),
                "median_wall_seconds": median(bucket["time_total"]),
                "median_rtf": median(bucket["rtf"]),
                "median_wer": median(bucket["wer"]),
                "median_punctuation_ratio": median(bucket["punctuation_ratio"]),
                "median_uppercase_word_ratio": median(bucket["uppercase_word_ratio"]),
                "text_preview": sample.get("text_preview", ""),
            }
        )
        rows.append(row)
    return sorted(rows, key=lambda row: tuple(str(row.get(field, "")) for field in key_fields))


def summarize(records: List[Mapping[str, Any]], health: Mapping[str, Any], args: argparse.Namespace) -> Dict[str, Any]:
    measured = [record for record in records if record.get("iteration") != 0]
    return {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "base_url": args.base_url,
        "requested_models": split_csv(args.models),
        "health": health,
        "aggregate_by_model": summarize_group(measured, ["model_id"]),
        "by_model_clip_variant": summarize_group(measured, ["model_id", "clip", "variant"]),
    }


def split_csv(value: str) -> List[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def validate_requested_models(health: Mapping[str, Any], models: Sequence[str], skip_missing: bool) -> List[str]:
    available = {
        str(profile.get("id"))
        for profile in health.get("models", [])
        if isinstance(profile, dict) and profile.get("id")
    }
    missing = [model for model in models if model not in available]
    if missing and not skip_missing:
        raise RuntimeError(
            "Requested models are not exposed by /v1/health: "
            + ", ".join(missing)
            + ". Use --skip-missing or start/configure a server with those profiles."
        )
    return [model for model in models if model in available]


def start_server(args: argparse.Namespace, out_dir: Path, token: str) -> subprocess.Popen:
    env = os.environ.copy()
    env["WHISKER_AUTH_TOKEN"] = token
    env["WHISKER_BIND_HOST"] = "127.0.0.1"
    env["WHISKER_PORT"] = str(args.temp_server_port)
    env["WHISKER_MAX_DURATION_SECONDS"] = str(args.max_duration_seconds)
    env["WHISKER_REQUEST_TIMEOUT_SECONDS"] = str(args.request_timeout_seconds)
    env["WHISKER_WHISPER_MODEL"] = env.get("WHISKER_WHISPER_MODEL", args.whisper_model)
    if args.profile_set == "bakeoff":
        env["WHISKER_EXTRA_MODEL_PROFILES"] = json.dumps(
            bakeoff_extra_profiles(env.get("WHISKER_WHISPER_MODEL", args.whisper_model))
        )

    server_log = (out_dir / "server.log").open("w")
    cmd = [
        sys.executable,
        "-m",
        "uvicorn",
        "server.app:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(args.temp_server_port),
    ]
    append_status(out_dir, f"Starting temporary server: {' '.join(cmd)}")
    process = subprocess.Popen(
        cmd,
        cwd=args.server_root,
        env=env,
        stdout=server_log,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return process


def wait_for_server(base_url: str, token: str, out_dir: Path, timeout_seconds: int) -> Dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    last_error = ""
    while time.monotonic() < deadline:
        try:
            return fetch_health(base_url, token, max_time=5)
        except Exception as error:
            last_error = str(error)
            time.sleep(1)
    raise RuntimeError(f"temporary server did not become healthy: {last_error}")


def terminate_server(process: Optional[subprocess.Popen], out_dir: Path) -> None:
    if process is None or process.poll() is not None:
        return
    append_status(out_dir, "Stopping temporary server")
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Whisker local ASR model bakeoff via /v1/transcribe.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8787")
    parser.add_argument("--models", default=DEFAULT_BAKEOFF_MODELS)
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--max-time", type=int, default=360)
    parser.add_argument("--ffmpeg", default=os.environ.get("WHISKER_FFMPEG", "/opt/homebrew/bin/ffmpeg"))
    parser.add_argument("--ffprobe", default=os.environ.get("WHISKER_FFPROBE", "/opt/homebrew/bin/ffprobe"))
    parser.add_argument("--out-root", default="benchmark-results")
    parser.add_argument("--skip-missing", action="store_true")
    parser.add_argument("--start-server", action="store_true")
    parser.add_argument("--temp-server-port", type=int, default=8797)
    parser.add_argument("--server-root", default=str(Path.cwd()))
    parser.add_argument("--profile-set", choices=["current", "bakeoff"], default="bakeoff")
    parser.add_argument("--whisper-model", default="models/ggml-large-v3-turbo.bin")
    parser.add_argument("--max-duration-seconds", type=float, default=300.0)
    parser.add_argument("--request-timeout-seconds", type=int, default=300)
    parser.add_argument("--server-start-timeout", type=int, default=90)
    args = parser.parse_args()

    token = os.environ.get("WHISKER_AUTH_TOKEN", "").strip()
    if not token:
        raise RuntimeError("WHISKER_AUTH_TOKEN is required")
    for path, label in [("/usr/bin/say", "say"), (args.ffmpeg, "ffmpeg"), (args.ffprobe, "ffprobe")]:
        require_file(path, label)

    if args.start_server:
        args.base_url = f"http://127.0.0.1:{args.temp_server_port}"

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.out_root) / f"asr-bakeoff-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    write_initial_status(out_dir, args)

    server_process: Optional[subprocess.Popen] = None
    records: List[Dict[str, Any]] = []
    try:
        append_status(out_dir, "Generating clean and pink-noise clips")
        clips = build_clips(out_dir, args.ffmpeg, args.ffprobe)
        append_status(out_dir, f"Generated {len(clips)} clip variants")

        if args.start_server:
            server_process = start_server(args, out_dir, token)
            health = wait_for_server(args.base_url, token, out_dir, args.server_start_timeout)
        else:
            append_status(out_dir, "Checking existing server health")
            health = fetch_health(args.base_url, token, max_time=15)
        (out_dir / "health.json").write_text(json.dumps(health, indent=2, sort_keys=True) + "\n")

        models = validate_requested_models(health, split_csv(args.models), args.skip_missing)
        if not models:
            raise RuntimeError("No requested models are available to benchmark")
        append_status(out_dir, "Benchmarking models: " + ", ".join(models))

        results_path = out_dir / "results.jsonl"
        with results_path.open("w") as handle:
            for model_id in models:
                warmup = post_transcription(args.base_url, token, clips[0], model_id, 0, args.max_time, out_dir)
                records.append(warmup)
                handle.write(json.dumps(warmup, sort_keys=True) + "\n")
                handle.flush()
                if warmup.get("http_code") != 200:
                    append_status(out_dir, f"Skipping {model_id}; warmup returned http_code={warmup.get('http_code')}")
                    continue
                for clip in clips:
                    for iteration in range(1, args.iterations + 1):
                        record = post_transcription(
                            args.base_url,
                            token,
                            clip,
                            model_id,
                            iteration,
                            args.max_time,
                            out_dir,
                        )
                        records.append(record)
                        handle.write(json.dumps(record, sort_keys=True) + "\n")
                        handle.flush()
                append_status(out_dir, f"Finished model {model_id}")

        summary = summarize(records, health, args)
        summary_path = out_dir / "summary.json"
        summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        append_status(out_dir, "Wrote results and summary")
        print(
            json.dumps(
                {
                    "out_dir": str(out_dir),
                    "results": str(results_path),
                    "summary": str(summary_path),
                    "aggregate_by_model": summary["aggregate_by_model"],
                },
                indent=2,
                sort_keys=True,
            )
        )
    finally:
        terminate_server(server_process, out_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
