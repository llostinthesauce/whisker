import unittest

from server.config import ModelProfile, ServerConfig
from server.status import StatusMetrics, build_status_payload, render_status_html


class StatusTests(unittest.TestCase):
    def test_status_payload_tracks_metrics_without_transcript_text(self):
        config = ServerConfig.from_env({}, require_token=False)
        metrics = StatusMetrics(started_at=100.0)
        metrics.record_success(
            now=125.0,
            model_id="balanced",
            engine="parakeet_mlx",
            model="mlx-community/parakeet-tdt-0.6b-v3",
            duration_seconds=12.5,
            processing_seconds=0.42,
        )

        payload = build_status_payload(
            config=config,
            default_engine_name="parakeet_mlx",
            default_engine_model="mlx-community/parakeet-tdt-0.6b-v3",
            default_engine_available=True,
            metrics=metrics,
            now=130.0,
        )

        self.assertEqual(payload["requests"]["total"], 1)
        self.assertEqual(payload["requests"]["succeeded"], 1)
        self.assertEqual(payload["requests"]["last_model_id"], "balanced")
        self.assertNotIn("text", str(payload).lower())
        self.assertNotIn("transcript", str(payload).lower())

    def test_status_html_escapes_dynamic_values(self):
        config = ServerConfig.from_env({}, require_token=False)
        custom_profile = ModelProfile(
            id="balanced",
            label="<Balanced>",
            engine="parakeet_mlx",
            model="model<script>",
            speed="medium",
            description="Current default.",
        )
        config = ServerConfig(
            **{
                **config.__dict__,
                "server_name": "<server>",
                "model_profiles": (custom_profile,),
            }
        )

        payload = build_status_payload(
            config=config,
            default_engine_name="parakeet_mlx",
            default_engine_model="model<script>",
            default_engine_available=True,
            metrics=StatusMetrics(started_at=100.0),
            now=100.0,
        )
        html = render_status_html(payload)

        self.assertIn("&lt;server&gt;", html)
        self.assertIn("model&lt;script&gt;", html)
        self.assertNotIn("<server>", html)
        self.assertNotIn("model<script>", html)
