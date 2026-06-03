import asyncio
import os
import threading
import unittest

# server.app initialises CONFIG at module level and requires WHISKER_AUTH_TOKEN.
# Set a valid token before importing so the module can be collected.
os.environ.setdefault("WHISKER_AUTH_TOKEN", "a" * 32)

from server import app as app_module  # noqa: E402


class StreamingConcurrencyTests(unittest.TestCase):
    def test_app_uses_anyio_thread_offload(self):
        """The transcribe handler must offload the blocking engine call to a worker
        thread; pin that app.py exposes anyio and that run_sync actually runs the
        callable off the calling thread."""
        self.assertTrue(
            hasattr(app_module, "anyio"),
            "server.app must import anyio for thread offload",
        )

        calling_thread = threading.current_thread().name
        captured = {}

        def work():
            captured["thread"] = threading.current_thread().name
            return "done"

        result = asyncio.run(app_module.anyio.to_thread.run_sync(work))
        self.assertEqual(result, "done")
        self.assertNotEqual(
            captured["thread"],
            calling_thread,
            "run_sync must execute off the calling thread",
        )
