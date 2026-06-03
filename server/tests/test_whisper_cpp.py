import unittest

from server.engines.whisper_cpp import parse_whisper_output


class WhisperCppParseTests(unittest.TestCase):
    def test_parses_timestamped_transcript_lines(self):
        output = """
whisper_init_from_file_with_params_no_state: loading model
system_info: n_threads = 4
[00:00:00.000 --> 00:00:02.000] hello there
[00:00:02.000 --> 00:00:04.000] this is whisker
"""
        self.assertEqual(parse_whisper_output(output), "hello there this is whisker")

    def test_ignores_processing_banner(self):
        output = """
processing 'input.wav' (16000 samples, 1.0 sec), 4 threads
hello from no timestamp mode
"""
        self.assertEqual(parse_whisper_output(output), "hello from no timestamp mode")
