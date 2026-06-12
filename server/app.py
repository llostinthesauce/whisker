import functools
import logging
import tempfile
import time
import uuid
from pathlib import Path
from typing import Optional

import anyio

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import HTMLResponse

from .audio import AudioError, convert_to_wav, probe_duration_seconds
from .auth import AuthError, require_bearer
from .cleanup.rules import clean_text
from .config import ModelProfile, ServerConfig
from .engines.base import AsrEngine
from .engines.parakeet_mlx import ParakeetMlxEngine
from .engines.qwen3_asr_06b import Qwen3ASR06BEngine
from .engines.qwen3_asr_17b import Qwen3ASR17BEngine
from .engines.whisper_cpp import WhisperCppEngine
from .schemas import (
    HealthResponse,
    ModelProfileResponse,
    TranscriptSegment,
    TranscriptionResponse,
)
from .status import StatusMetrics, build_status_payload, render_status_html


logger = logging.getLogger("whisker.remote")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

CONFIG = ServerConfig.from_env(require_token=True)
app = FastAPI(
    title="Whisker Remote Transcription",
    version=CONFIG.version,
    debug=CONFIG.debug,
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)
STATUS_METRICS = StatusMetrics()


def build_engine(config: ServerConfig, profile: ModelProfile) -> AsrEngine:
    if profile.engine == "whisper_cpp":
        return WhisperCppEngine(
            cli_path=config.whisper_cli_path,
            model_path=config.whisper_model_path_for(profile),
            extra_args=config.whisper_extra_args,
            timeout_seconds=config.request_timeout_seconds,
        )
    if profile.engine == "parakeet_mlx":
        return ParakeetMlxEngine(
            model_name=profile.model,
            cache_dir=config.parakeet_cache_dir,
            ffmpeg_path=config.ffmpeg_path,
        )
    if profile.engine == "qwen3-asr-06b":
        return Qwen3ASR06BEngine(
            cache_dir=config.parakeet_cache_dir,
            ffmpeg_path=config.ffmpeg_path,
        )
    if profile.engine == "qwen3-asr-17b":
        return Qwen3ASR17BEngine(
            cache_dir=config.parakeet_cache_dir,
            ffmpeg_path=config.ffmpeg_path,
        )
    raise RuntimeError(f"Unsupported engine for model profile {profile.id}: {profile.engine}")


_ENGINES: dict[str, AsrEngine] = {}


def engine_for(profile: ModelProfile) -> AsrEngine:
    if profile.id not in _ENGINES:
        _ENGINES[profile.id] = build_engine(CONFIG, profile)
    return _ENGINES[profile.id]


def authorize(authorization: Optional[str] = Header(default=None)) -> None:
    try:
        require_bearer(authorization, CONFIG.auth_token)
    except AuthError:
        raise HTTPException(status_code=401, detail="Unauthorized")


@app.get("/health", response_model=HealthResponse, dependencies=[Depends(authorize)])
@app.get("/v1/health", response_model=HealthResponse, dependencies=[Depends(authorize)])
async def health() -> HealthResponse:
    default_profile = CONFIG.model_profile_for(CONFIG.default_model_id)
    default_engine = engine_for(default_profile)
    return HealthResponse(
        ok=default_engine.is_available(),
        server=CONFIG.server_name,
        version=CONFIG.version,
        engine=default_engine.name,
        model=default_engine.model,
        default_model_id=CONFIG.default_model_id,
        models=[
            ModelProfileResponse(
                id=profile.id,
                label=profile.label,
                engine=profile.engine,
                model=profile.model,
                speed=profile.speed,
                description=profile.description,
            )
            for profile in CONFIG.model_profiles
        ],
        cleanup=list(CONFIG.cleanup_modes),
        max_duration_seconds=CONFIG.max_duration_seconds,
    )


def _status_payload() -> dict:
    default_profile = CONFIG.model_profile_for(CONFIG.default_model_id)
    default_engine = engine_for(default_profile)
    return build_status_payload(
        config=CONFIG,
        default_engine_name=default_engine.name,
        default_engine_model=default_engine.model,
        default_engine_available=default_engine.is_available(),
        metrics=STATUS_METRICS,
    )


@app.get("/v1/status", dependencies=[Depends(authorize)])
async def status_json() -> dict:
    return _status_payload()


@app.get("/status", response_class=HTMLResponse, dependencies=[Depends(authorize)])
async def status_page() -> HTMLResponse:
    return HTMLResponse(render_status_html(_status_payload()))


@app.post("/v1/transcribe", response_model=TranscriptionResponse, dependencies=[Depends(authorize)])
async def transcribe(
    file: UploadFile = File(...),
    cleanup_mode: str = Form("raw"),
    model_id: Optional[str] = Form(None),
    return_cleaned: bool = Form(False),
    content_length: Optional[str] = Header(default=None),
) -> TranscriptionResponse:
    request_id = str(uuid.uuid4())
    start = time.monotonic()
    profile: Optional[ModelProfile] = None
    engine: Optional[AsrEngine] = None
    duration: Optional[float] = None

    try:
        _check_content_length(content_length)
        try:
            profile = CONFIG.model_profile_for(model_id)
        except KeyError:
            raise HTTPException(status_code=400, detail="Unknown model_id")
        engine = engine_for(profile)
        with tempfile.TemporaryDirectory(dir=str(_work_dir())) as directory:
            temp_dir = Path(directory)
            input_path = temp_dir / "input.audio"
            wav_path = temp_dir / "input.wav"
            await _save_upload(file, input_path)

            # ffprobe/ffmpeg are synchronous subprocess calls with timeouts up
            # to request_timeout_seconds; run them on worker threads so they
            # never block the event loop (concurrent streaming-segment uploads
            # and /health depend on it staying free).
            duration = await anyio.to_thread.run_sync(
                functools.partial(
                    probe_duration_seconds,
                    CONFIG.ffprobe_path,
                    input_path,
                    timeout=min(CONFIG.request_timeout_seconds, 60),
                )
            )
            if duration is not None and duration > CONFIG.max_duration_seconds:
                raise HTTPException(status_code=413, detail="Audio duration exceeds limit")

            await anyio.to_thread.run_sync(
                functools.partial(
                    convert_to_wav,
                    CONFIG.ffmpeg_path,
                    input_path,
                    wav_path,
                    timeout=CONFIG.request_timeout_seconds,
                )
            )
            result = await anyio.to_thread.run_sync(engine.transcribe, wav_path, duration or 0.0)
    except HTTPException as error:
        STATUS_METRICS.record_failure(
            status_code=error.status_code,
            model_id=profile.id if profile else model_id,
            engine=engine.name if engine else None,
            model=engine.model if engine else None,
        )
        raise
    except AudioError as error:
        logger.info("request=%s status=415 audio_error=%s", request_id, error)
        STATUS_METRICS.record_failure(
            status_code=415,
            model_id=profile.id if profile else model_id,
            engine=engine.name if engine else None,
            model=engine.model if engine else None,
        )
        raise HTTPException(status_code=415, detail="Unsupported audio")
    except RuntimeError as error:
        logger.info("request=%s status=503 engine_error=%s", request_id, error)
        STATUS_METRICS.record_failure(
            status_code=503,
            model_id=profile.id if profile else model_id,
            engine=engine.name if engine else None,
            model=engine.model if engine else None,
        )
        raise HTTPException(status_code=503, detail="ASR engine unavailable")

    text = result.text.strip()
    if not text:
        logger.info("request=%s status=422 empty_transcript=true", request_id)
        STATUS_METRICS.record_failure(
            status_code=422,
            model_id=profile.id,
            engine=engine.name,
            model=engine.model,
        )
        raise HTTPException(status_code=422, detail="Empty transcript")

    selected_cleanup = cleanup_mode.strip().lower() or "raw"
    cleaned_text = None
    if return_cleaned and selected_cleanup != "raw":
        cleaned_text = clean_text(text, selected_cleanup)

    processing_seconds = time.monotonic() - start
    logger.info(
        "request=%s status=200 engine=%s model=%s duration=%.3f processing=%.3f",
        request_id,
        engine.name,
        engine.model,
        duration or 0.0,
        processing_seconds,
    )
    STATUS_METRICS.record_success(
        model_id=profile.id,
        engine=engine.name,
        model=engine.model,
        duration_seconds=duration or 0.0,
        processing_seconds=processing_seconds,
    )
    return TranscriptionResponse(
        id=request_id,
        text=text,
        cleaned_text=cleaned_text,
        duration_seconds=duration or 0.0,
        engine=engine.name,
        model=engine.model,
        model_id=profile.id,
        processing_seconds=processing_seconds,
        segments=[
            TranscriptSegment(start=segment.start, end=segment.end, text=segment.text)
            for segment in result.segments
        ],
        warnings=result.warnings,
    )


def _work_dir() -> Path:
    CONFIG.work_dir.mkdir(parents=True, exist_ok=True)
    return CONFIG.work_dir


def _check_content_length(content_length: Optional[str]) -> None:
    if not content_length:
        return
    try:
        length = int(content_length)
    except ValueError:
        return
    if length > CONFIG.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Upload exceeds limit")


async def _save_upload(file: UploadFile, destination: Path) -> None:
    bytes_written = 0
    with destination.open("wb") as handle:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            bytes_written += len(chunk)
            if bytes_written > CONFIG.max_upload_bytes:
                raise HTTPException(status_code=413, detail="Upload exceeds limit")
            handle.write(chunk)
