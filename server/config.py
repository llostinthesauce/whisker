import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional, Tuple


MIN_AUTH_TOKEN_LENGTH = 32


def _expand_path(value: str) -> Path:
    return Path(value).expanduser()


def _env_int(env: Mapping[str, str], key: str, default: int, minimum: int = 1) -> int:
    raw = env.get(key, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        raise ValueError(f"{key} must be an integer")
    if value < minimum:
        raise ValueError(f"{key} must be >= {minimum}")
    return value


def _env_float(env: Mapping[str, str], key: str, default: float, minimum: float = 0.1) -> float:
    raw = env.get(key, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        raise ValueError(f"{key} must be a number")
    if value < minimum:
        raise ValueError(f"{key} must be >= {minimum}")
    return value


def _env_bool(env: Mapping[str, str], key: str, default: bool = False) -> bool:
    raw = env.get(key, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def _validate_auth_token(token: str, *, require_token: bool) -> None:
    if require_token and not token:
        raise RuntimeError("WHISKER_AUTH_TOKEN is required")
    if token and len(token) < MIN_AUTH_TOKEN_LENGTH:
        raise ValueError(
            f"WHISKER_AUTH_TOKEN must be at least {MIN_AUTH_TOKEN_LENGTH} characters"
        )


def _profile_field(item: Mapping[str, Any], key: str, env_name: str, index: int) -> str:
    value = str(item.get(key, "")).strip()
    if not value:
        raise ValueError(f"{env_name}[{index}].{key} is required")
    return value


@dataclass(frozen=True)
class ModelProfile:
    id: str
    label: str
    engine: str
    model: str
    speed: str
    description: str


def _model_profiles_from_json(raw: str, env_name: str) -> Tuple[ModelProfile, ...]:
    value = raw.strip()
    if not value:
        return ()
    try:
        data = json.loads(value)
    except json.JSONDecodeError as error:
        raise ValueError(f"{env_name} must be valid JSON") from error
    if not isinstance(data, list):
        raise ValueError(f"{env_name} must be a JSON array")

    profiles = []
    for index, item in enumerate(data):
        if not isinstance(item, dict):
            raise ValueError(f"{env_name}[{index}] must be an object")
        engine = _profile_field(item, "engine", env_name, index)
        if engine not in {"parakeet_mlx", "whisper_cpp", "qwen3-asr-06b", "qwen3-asr-17b"}:
            raise ValueError(
                f"{env_name}[{index}].engine must be one of: parakeet_mlx, whisper_cpp, qwen3-asr-06b, qwen3-asr-17b"
            )
        profiles.append(
            ModelProfile(
                id=_profile_field(item, "id", env_name, index),
                label=_profile_field(item, "label", env_name, index),
                engine=engine,
                model=_profile_field(item, "model", env_name, index),
                speed=_profile_field(item, "speed", env_name, index),
                description=_profile_field(item, "description", env_name, index),
            )
        )
    return tuple(profiles)


def _validate_model_profiles(model_profiles: Tuple[ModelProfile, ...]) -> None:
    if not model_profiles:
        raise ValueError("At least one model profile is required")
    seen = set()
    for profile in model_profiles:
        if profile.id in seen:
            raise ValueError("Model profile ids must be unique")
        seen.add(profile.id)


@dataclass(frozen=True)
class ServerConfig:
    server_name: str
    version: str
    bind_host: str
    port: int
    auth_token: str
    max_upload_bytes: int
    max_duration_seconds: float
    request_timeout_seconds: int
    work_dir: Path
    ffmpeg_path: str
    ffprobe_path: str
    engine: str
    whisper_cli_path: str
    whisper_model_path: Path
    whisper_extra_args: Tuple[str, ...]
    parakeet_model: str
    parakeet_cache_dir: Optional[Path]
    default_model_id: str
    model_profiles: Tuple[ModelProfile, ...]
    cleanup_modes: Tuple[str, ...]
    debug: bool

    @classmethod
    def from_env(
        cls,
        env: Optional[Mapping[str, str]] = None,
        require_token: bool = True,
    ) -> "ServerConfig":
        source = os.environ if env is None else env
        token = source.get("WHISKER_AUTH_TOKEN", "").strip()
        _validate_auth_token(token, require_token=require_token)

        home_model = (
            "~/Library/Application Support/WhiskerRemote/models/ggml-base.en.bin"
        )
        modes = tuple(
            mode.strip()
            for mode in source.get(
                "WHISKER_CLEANUP_MODES",
                "raw,light,message,email,notes,bullets",
            ).split(",")
            if mode.strip()
        )
        extra_args = tuple(
            arg.strip()
            for arg in source.get(
                "WHISKER_WHISPER_ARGS",
                "--no-timestamps --language en",
            ).split()
            if arg.strip()
        )

        engine = source.get("WHISKER_ENGINE", "parakeet_mlx").strip().lower() or "parakeet_mlx"
        if engine not in {"parakeet_mlx", "whisper_cpp", "qwen3-asr-06b", "qwen3-asr-17b"}:
            raise ValueError("WHISKER_ENGINE must be one of: parakeet_mlx, whisper_cpp, qwen3-asr-06b, qwen3-asr-17b")

        whisper_model_path = _expand_path(source.get("WHISKER_WHISPER_MODEL", home_model))
        parakeet_model = source.get(
            "WHISKER_PARAKEET_MODEL",
            "mlx-community/parakeet-tdt-0.6b-v3",
        ).strip() or "mlx-community/parakeet-tdt-0.6b-v3"
        fast_model = source.get(
            "WHISKER_FAST_MODEL",
            "mlx-community/parakeet-tdt_ctc-110m",
        ).strip() or "mlx-community/parakeet-tdt_ctc-110m"
        if engine == "parakeet_mlx":
            base_model_profiles = (
                ModelProfile(
                    id="fast",
                    label="Fast",
                    engine="parakeet_mlx",
                    model=fast_model,
                    speed="fast",
                    description="Small 110M Parakeet CTC model for near-instant short dictation.",
                ),
                ModelProfile(
                    id="balanced",
                    label="Balanced",
                    engine="parakeet_mlx",
                    model=parakeet_model,
                    speed="medium",
                    description="Current default Parakeet TDT 0.6B v3 model with strong quality and speed.",
                ),
            )
        else:
            base_model_profiles = (
                ModelProfile(
                    id="balanced",
                    label="Whisper.cpp",
                    engine="whisper_cpp",
                    model=whisper_model_path.name,
                    speed="medium",
                    description="whisper.cpp model configured by WHISKER_WHISPER_MODEL.",
                ),
            )
        model_profiles_override = source.get("WHISKER_MODEL_PROFILES", "").strip()
        if model_profiles_override:
            model_profiles = _model_profiles_from_json(
                model_profiles_override,
                "WHISKER_MODEL_PROFILES",
            )
        else:
            model_profiles = (
                *base_model_profiles,
                *_model_profiles_from_json(
                    source.get("WHISKER_EXTRA_MODEL_PROFILES", ""),
                    "WHISKER_EXTRA_MODEL_PROFILES",
                ),
            )
        _validate_model_profiles(model_profiles)
        default_model_id = source.get("WHISKER_DEFAULT_MODEL_ID", "balanced").strip() or "balanced"
        if default_model_id not in {profile.id for profile in model_profiles}:
            raise ValueError("WHISKER_DEFAULT_MODEL_ID must match a configured model profile id")

        return cls(
            server_name=source.get("WHISKER_SERVER_NAME", "whisker-server").strip()
            or "whisker-server",
            version="0.1.0",
            bind_host=source.get("WHISKER_BIND_HOST", "127.0.0.1").strip()
            or "127.0.0.1",
            port=_env_int(source, "WHISKER_PORT", 8787),
            auth_token=token,
            # 80 MiB: a full 5-minute (WHISKER_MAX_DURATION_SECONDS /
            # RecordingLimits.maxDurationSeconds) CAF at 48 kHz float32 mono is
            # ~57.6 MB, so the whole-file fallback must fit with headroom.
            max_upload_bytes=_env_int(
                source,
                "WHISKER_MAX_UPLOAD_BYTES",
                80 * 1024 * 1024,
            ),
            max_duration_seconds=_env_float(
                source,
                "WHISKER_MAX_DURATION_SECONDS",
                300.0,
            ),
            request_timeout_seconds=_env_int(
                source,
                "WHISKER_REQUEST_TIMEOUT_SECONDS",
                300,
            ),
            work_dir=_expand_path(
                source.get("WHISKER_WORK_DIR", "~/Library/Caches/WhiskerRemote")
            ),
            ffmpeg_path=source.get("WHISKER_FFMPEG", "ffmpeg").strip() or "ffmpeg",
            ffprobe_path=source.get("WHISKER_FFPROBE", "ffprobe").strip()
            or "ffprobe",
            engine=engine,
            whisper_cli_path=source.get("WHISKER_WHISPER_CLI", "whisper-cli").strip()
            or "whisper-cli",
            whisper_model_path=whisper_model_path,
            whisper_extra_args=extra_args,
            parakeet_model=parakeet_model,
            parakeet_cache_dir=(
                _expand_path(source["WHISKER_PARAKEET_CACHE_DIR"])
                if source.get("WHISKER_PARAKEET_CACHE_DIR", "").strip()
                else None
            ),
            default_model_id=default_model_id,
            model_profiles=model_profiles,
            cleanup_modes=modes or ("raw", "light"),
            debug=_env_bool(source, "WHISKER_DEBUG", False),
        )

    def model_profile_for(self, model_id: Optional[str]) -> ModelProfile:
        selected_id = (model_id or self.default_model_id).strip() or self.default_model_id
        for profile in self.model_profiles:
            if profile.id == selected_id:
                return profile
        raise KeyError(selected_id)

    def whisper_model_path_for(self, profile: ModelProfile) -> Path:
        profile_model = profile.model.strip()
        if not profile_model or profile_model == self.whisper_model_path.name:
            return self.whisper_model_path
        candidate = _expand_path(profile_model)
        if candidate.is_absolute() or candidate.parent != Path("."):
            return candidate
        return self.whisper_model_path.parent / candidate
