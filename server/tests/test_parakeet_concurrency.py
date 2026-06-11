import threading
import time
import unittest
from pathlib import Path
from typing import Optional

from server.engines.parakeet_mlx import ParakeetMlxEngine


class _ActivityCounter:
    """Shared counter so overlap can be observed across multiple fake models."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.active = 0
        self.max_active = 0

    def enter(self) -> None:
        with self._lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)

    def exit(self) -> None:
        with self._lock:
            self.active -= 1


class _FakeModel:
    """Records the maximum number of threads inside transcribe at once."""

    def __init__(self, counter: Optional[_ActivityCounter] = None) -> None:
        self.counter = counter or _ActivityCounter()

    @property
    def max_active(self) -> int:
        return self.counter.max_active

    def transcribe(self, _path: str):
        self.counter.enter()
        time.sleep(0.05)  # hold the "inference" so overlap would be observable
        self.counter.exit()
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

    def test_inference_is_serialized_across_different_model_profiles(self):
        """The server holds one engine per profile (fast/balanced). The lock must
        be shared across instances so two different MLX models never run
        inference concurrently on the same Metal device."""
        counter = _ActivityCounter()
        engines = [
            ParakeetMlxEngine(model_name="org/fast-model"),
            ParakeetMlxEngine(model_name="org/balanced-model"),
        ]
        for engine in engines:
            engine._model = _FakeModel(counter)
            engine.is_available = lambda: True  # type: ignore[method-assign]

        threads = [
            threading.Thread(target=engine.transcribe, args=(Path("/tmp/x.wav"), 1.0))
            for engine in engines
            for _ in range(3)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(
            counter.max_active,
            1,
            "cross-model parakeet inference must be serialized; concurrent entry detected",
        )


if __name__ == "__main__":
    unittest.main()
