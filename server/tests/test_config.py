from pathlib import Path
import json
import unittest

from server.config import ServerConfig


class ConfigTests(unittest.TestCase):
    def test_requires_token_for_runtime_config(self):
        with self.assertRaises(RuntimeError):
            ServerConfig.from_env({}, require_token=True)

    def test_rejects_short_auth_token(self):
        with self.assertRaises(ValueError):
            ServerConfig.from_env(
                {"WHISKER_AUTH_TOKEN": "short-token"},
                require_token=True,
            )

    def test_accepts_long_auth_token(self):
        config = ServerConfig.from_env(
            {"WHISKER_AUTH_TOKEN": "a" * 32},
            require_token=True,
        )

        self.assertEqual(config.auth_token, "a" * 32)

    def test_builds_development_config_without_token(self):
        config = ServerConfig.from_env({}, require_token=False)
        self.assertEqual(config.bind_host, "127.0.0.1")
        self.assertEqual(config.port, 8787)
        self.assertEqual(config.engine, "parakeet_mlx")
        self.assertEqual(config.default_model_id, "balanced")
        self.assertEqual(config.max_duration_seconds, 300.0)
        self.assertEqual([profile.id for profile in config.model_profiles], ["fast", "balanced"])

    def test_accepts_tailscale_bind_host(self):
        config = ServerConfig.from_env(
            {"WHISKER_BIND_HOST": "tailscale-host.example"},
            require_token=False,
        )
        self.assertEqual(config.bind_host, "tailscale-host.example")

    def test_builds_parakeet_config(self):
        config = ServerConfig.from_env(
            {
                "WHISKER_ENGINE": "parakeet_mlx",
                "WHISKER_PARAKEET_MODEL": "sonic-speech/parakeet-tdt-0.6b-v3-int8",
                "WHISKER_PARAKEET_CACHE_DIR": "~/Library/Caches/WhiskerRemote/parakeet",
            },
            require_token=False,
        )
        self.assertEqual(config.engine, "parakeet_mlx")
        self.assertEqual(config.parakeet_model, "sonic-speech/parakeet-tdt-0.6b-v3-int8")
        self.assertEqual(
            config.parakeet_cache_dir,
            Path.home() / "Library/Caches/WhiskerRemote/parakeet",
        )

    def test_accepts_model_profile_overrides(self):
        config = ServerConfig.from_env(
            {
                "WHISKER_FAST_MODEL": "local-fast",
                "WHISKER_PARAKEET_MODEL": "local-balanced",
                "WHISKER_DEFAULT_MODEL_ID": "fast",
            },
            require_token=False,
        )

        self.assertEqual(config.default_model_id, "fast")
        self.assertEqual(config.model_profile_for("fast").model, "local-fast")
        self.assertEqual(config.model_profile_for("balanced").model, "local-balanced")

    def test_accepts_extra_model_profiles(self):
        extra_profiles = [
            {
                "id": "parakeet-v2",
                "label": "Parakeet 0.6B v2",
                "engine": "parakeet_mlx",
                "model": "mlx-community/parakeet-tdt-0.6b-v2",
                "speed": "medium",
                "description": "Benchmark candidate.",
            },
            {
                "id": "whisper-turbo",
                "label": "Whisper Large v3 Turbo",
                "engine": "whisper_cpp",
                "model": "ggml-large-v3-turbo.bin",
                "speed": "medium",
                "description": "Benchmark candidate.",
            },
        ]

        config = ServerConfig.from_env(
            {"WHISKER_EXTRA_MODEL_PROFILES": json.dumps(extra_profiles)},
            require_token=False,
        )

        self.assertEqual(
            [profile.id for profile in config.model_profiles],
            ["fast", "balanced", "parakeet-v2", "whisper-turbo"],
        )
        self.assertEqual(config.model_profile_for("parakeet-v2").engine, "parakeet_mlx")
        self.assertEqual(config.model_profile_for("whisper-turbo").engine, "whisper_cpp")

    def test_rejects_duplicate_extra_model_profile_id(self):
        extra_profiles = [
            {
                "id": "balanced",
                "label": "Duplicate",
                "engine": "parakeet_mlx",
                "model": "local-model",
                "speed": "medium",
                "description": "Invalid duplicate.",
            }
        ]

        with self.assertRaises(ValueError):
            ServerConfig.from_env(
                {"WHISKER_EXTRA_MODEL_PROFILES": json.dumps(extra_profiles)},
                require_token=False,
            )

    def test_rejects_unknown_default_model(self):
        with self.assertRaises(ValueError):
            ServerConfig.from_env({"WHISKER_DEFAULT_MODEL_ID": "missing"}, require_token=False)

    def test_whisper_engine_uses_whisper_model_profile(self):
        config = ServerConfig.from_env(
            {
                "WHISKER_ENGINE": "whisper_cpp",
                "WHISKER_WHISPER_MODEL": "~/Library/Application Support/WhiskerRemote/models/ggml-small.en.bin",
            },
            require_token=False,
        )

        self.assertEqual(config.engine, "whisper_cpp")
        self.assertEqual([profile.id for profile in config.model_profiles], ["balanced"])
        self.assertEqual(config.model_profile_for(None).engine, "whisper_cpp")
        self.assertEqual(config.model_profile_for(None).model, "ggml-small.en.bin")

    def test_whisper_profile_can_resolve_model_beside_global_model(self):
        config = ServerConfig.from_env(
            {
                "WHISKER_WHISPER_MODEL": "/models/ggml-large-v3-turbo.bin",
                "WHISKER_EXTRA_MODEL_PROFILES": json.dumps(
                    [
                        {
                            "id": "distil-v3",
                            "label": "Distil Large v3",
                            "engine": "whisper_cpp",
                            "model": "ggml-distil-large-v3.bin",
                            "speed": "medium",
                            "description": "Benchmark candidate.",
                        }
                    ]
                ),
            },
            require_token=False,
        )

        self.assertEqual(
            config.whisper_model_path_for(config.model_profile_for("distil-v3")),
            Path("/models/ggml-distil-large-v3.bin"),
        )

    def test_whisper_profile_can_resolve_explicit_model_path(self):
        config = ServerConfig.from_env(
            {
                "WHISKER_WHISPER_MODEL": "/models/ggml-large-v3-turbo.bin",
                "WHISKER_EXTRA_MODEL_PROFILES": json.dumps(
                    [
                        {
                            "id": "distil-v35",
                            "label": "Distil Large v3.5",
                            "engine": "whisper_cpp",
                            "model": "/alt/ggml-distil-large-v3.5.bin",
                            "speed": "medium",
                            "description": "Benchmark candidate.",
                        }
                    ]
                ),
            },
            require_token=False,
        )

        self.assertEqual(
            config.whisper_model_path_for(config.model_profile_for("distil-v35")),
            Path("/alt/ggml-distil-large-v3.5.bin"),
        )
