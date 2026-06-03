import os
import unittest
from pathlib import Path

from server.engines.parakeet_mlx import ParakeetMlxEngine


class FakeSentence:
    text = "Hello world."
    start = 0.1
    end = 1.2


class FakeResult:
    text = " Hello world. "
    sentences = [FakeSentence()]


class FakeModel:
    def transcribe(self, path):
        self.path = path
        return FakeResult()


class AvailableParakeetMlxEngine(ParakeetMlxEngine):
    def is_available(self):
        return True


class ParakeetMlxEngineTests(unittest.TestCase):
    def test_model_label_uses_last_repo_component(self):
        engine = ParakeetMlxEngine("mlx-community/parakeet-tdt-0.6b-v3")
        self.assertEqual(engine.name, "parakeet-mlx")
        self.assertEqual(engine.model, "parakeet-tdt-0.6b-v3")

    def test_transcribe_maps_text_and_sentence_segments(self):
        engine = AvailableParakeetMlxEngine("mlx-community/parakeet-tdt-0.6b-v3")
        fake_model = FakeModel()
        engine._model = fake_model

        result = engine.transcribe(Path("/tmp/input.wav"), duration_seconds=1.0)

        self.assertEqual(fake_model.path, "/tmp/input.wav")
        self.assertEqual(result.text, "Hello world.")
        self.assertEqual(len(result.segments), 1)
        self.assertEqual(result.segments[0].start, 0.1)
        self.assertEqual(result.segments[0].end, 1.2)
        self.assertEqual(result.segments[0].text, "Hello world.")

    def test_transcribe_adds_configured_ffmpeg_directory_to_path(self):
        original_path = os.environ.get("PATH", "")
        try:
            os.environ["PATH"] = "/usr/bin"
            engine = AvailableParakeetMlxEngine(
                "mlx-community/parakeet-tdt-0.6b-v3",
                ffmpeg_path="/opt/homebrew/bin/ffmpeg",
            )
            engine._model = FakeModel()

            engine.transcribe(Path("/tmp/input.wav"), duration_seconds=1.0)

            self.assertTrue(os.environ["PATH"].startswith("/opt/homebrew/bin:"))
        finally:
            os.environ["PATH"] = original_path
