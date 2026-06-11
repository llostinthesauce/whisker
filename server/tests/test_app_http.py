import os
import unittest
from pathlib import Path
from typing import List, Optional
from unittest import mock

# server.app initialises CONFIG at module level and requires WHISKER_AUTH_TOKEN.
# Set a valid token before importing so the module can be collected.
os.environ.setdefault("WHISKER_AUTH_TOKEN", "a" * 32)

from fastapi.testclient import TestClient  # noqa: E402

from server import app as app_module  # noqa: E402
from server.audio import AudioError  # noqa: E402
from server.engines.base import TranscriptSegment, TranscriptionResult  # noqa: E402


TOKEN = os.environ["WHISKER_AUTH_TOKEN"]
AUTH = {"Authorization": f"Bearer {TOKEN}"}


class _StubEngine:
    name = "stub-engine"
    model = "stub-model"

    def __init__(
        self,
        text: str = "hello world",
        segments: Optional[List[TranscriptSegment]] = None,
        error: Optional[Exception] = None,
    ) -> None:
        self.text = text
        self.segments = segments or []
        self.error = error

    def is_available(self) -> bool:
        return True

    def transcribe(self, wav_path: Path, duration_seconds: float) -> TranscriptionResult:
        if self.error is not None:
            raise self.error
        return TranscriptionResult(text=self.text, segments=self.segments, warnings=[])


def _upload(client: TestClient, headers=None, data=None):
    return client.post(
        "/v1/transcribe",
        headers=AUTH if headers is None else headers,
        data={"cleanup_mode": "raw", **(data or {})},
        files={"file": ("input.caf", b"fake-audio-bytes", "application/octet-stream")},
    )


class _PatchedAppTest(unittest.TestCase):
    """Runs each test with ffprobe/ffmpeg patched out and a stub engine."""

    engine = _StubEngine()

    def setUp(self) -> None:
        self.client = TestClient(app_module.app)
        patches = [
            mock.patch.object(app_module, "probe_duration_seconds", return_value=5.0),
            mock.patch.object(app_module, "convert_to_wav", return_value=None),
            mock.patch.object(app_module, "engine_for", return_value=self.engine),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)


class AuthHttpTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app_module.app)

    def test_health_without_token_is_rejected(self):
        for path in ("/health", "/v1/health"):
            self.assertEqual(self.client.get(path).status_code, 401)

    def test_health_with_wrong_token_is_rejected(self):
        response = self.client.get(
            "/v1/health", headers={"Authorization": "Bearer " + "b" * 32}
        )
        self.assertEqual(response.status_code, 401)

    def test_status_endpoints_require_token(self):
        self.assertEqual(self.client.get("/status").status_code, 401)
        self.assertEqual(self.client.get("/v1/status").status_code, 401)

    def test_transcribe_without_token_is_rejected(self):
        self.assertEqual(_upload(self.client, headers={}).status_code, 401)


class HealthHttpTests(_PatchedAppTest):
    def test_health_reports_models_and_limits(self):
        response = self.client.get("/v1/health", headers=AUTH)

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["ok"])
        self.assertEqual(
            [profile["id"] for profile in payload["models"]],
            [profile.id for profile in app_module.CONFIG.model_profiles],
        )
        self.assertEqual(
            payload["max_duration_seconds"], app_module.CONFIG.max_duration_seconds
        )

    def test_status_json_returns_payload(self):
        response = self.client.get("/v1/status", headers=AUTH)
        self.assertEqual(response.status_code, 200)
        self.assertIn("server", response.json())


class TranscribeHttpTests(_PatchedAppTest):
    def test_unknown_model_id_returns_400(self):
        response = _upload(self.client, data={"model_id": "no-such-profile"})
        self.assertEqual(response.status_code, 400)

    def test_content_length_over_limit_returns_413(self):
        response = _upload(
            self.client,
            headers={**AUTH, "Content-Length": str(app_module.CONFIG.max_upload_bytes + 1)},
        )
        self.assertEqual(response.status_code, 413)

    def test_duration_over_limit_returns_413(self):
        with mock.patch.object(
            app_module,
            "probe_duration_seconds",
            return_value=app_module.CONFIG.max_duration_seconds + 1,
        ):
            self.assertEqual(_upload(self.client).status_code, 413)

    def test_unreadable_audio_returns_415(self):
        with mock.patch.object(
            app_module,
            "probe_duration_seconds",
            side_effect=AudioError("Could not read audio duration"),
        ):
            self.assertEqual(_upload(self.client).status_code, 415)

    def test_engine_failure_returns_503(self):
        with mock.patch.object(
            app_module,
            "engine_for",
            return_value=_StubEngine(error=RuntimeError("engine down")),
        ):
            self.assertEqual(_upload(self.client).status_code, 503)

    def test_empty_transcript_returns_422(self):
        with mock.patch.object(
            app_module, "engine_for", return_value=_StubEngine(text="   ")
        ):
            self.assertEqual(_upload(self.client).status_code, 422)

    def test_success_returns_transcript_and_engine_segments(self):
        segments = [TranscriptSegment(start=0.0, end=2.5, text="hello world")]
        with mock.patch.object(
            app_module,
            "engine_for",
            return_value=_StubEngine(text="hello world", segments=segments),
        ):
            response = _upload(self.client)

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["text"], "hello world")
        # The engine's segments must reach the response; they were previously
        # computed and then discarded as a hardcoded [].
        self.assertEqual(
            payload["segments"],
            [{"start": 0.0, "end": 2.5, "text": "hello world"}],
        )

    def test_cleaned_text_returned_when_requested(self):
        response = _upload(
            self.client,
            data={"cleanup_mode": "message", "return_cleaned": "true"},
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["text"], "hello world")
        self.assertEqual(payload["cleaned_text"], "Hello world")


if __name__ == "__main__":
    unittest.main()
