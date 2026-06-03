import threading
import time
import unittest
from pathlib import Path

from server.engines.parakeet_mlx import ParakeetMlxEngine


class _FakeModel:
    """Records the maximum number of threads inside transcribe at once."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.active = 0
        self.max_active = 0

    def transcribe(self, _path: str):
        with self._lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
        time.sleep(0.05)  # hold the "inference" so overlap would be observable
        with self._lock:
            self.active -= 1
        return type("_Result", (), {"text": "ok", "sentences": []})()


class ParakeetConcurrencyTest(unittest.TestCase):
    def test_concurrent_transcribe_calls_are_serialized(self):
        engine = ParakeetMlxEngine(model_name="org/model")
        # Inject a fake model and bypass availability so no real parakeet_mlx /
        # model download is needed; _load_model returns the injected instance.
        engine._model = _FakeModel()
        engine.is_available = lambda: True  # type: ignore[method-assign]

        threads = [
            threading.Thread(target=engine.transcribe, args=(Path("/tmp/x.wav"), 1.0))
            for _ in range(5)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(
            engine._model.max_active,
            1,
            "parakeet inference must be serialized; concurrent entry detected",
        )


if __name__ == "__main__":
    unittest.main()
