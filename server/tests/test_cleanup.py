import unittest

from server.cleanup.rules import clean_text, normalize_whitespace


class CleanupTests(unittest.TestCase):
    def test_normalizes_spaces_without_collapsing_paragraphs(self):
        self.assertEqual(
            normalize_whitespace(" hello   there\n\n\nsecond\tline "),
            "hello there\n\nsecond line",
        )

    def test_raw_returns_input_unchanged(self):
        self.assertEqual(clean_text("  keep   spacing ", "raw"), "  keep   spacing ")

    def test_message_capitalizes_first_letter_after_light_cleanup(self):
        self.assertEqual(clean_text(" hello   there ", "message"), "Hello there")

    def test_bullets_split_sentences(self):
        self.assertEqual(
            clean_text("first thing. second thing? final thing!", "bullets"),
            "- First thing.\n- Second thing?\n- Final thing!",
        )

    def test_notes_split_sentences_onto_lines(self):
        # Mirrored by Tests/RuleBasedCleanerTests.swift: the on-device cleaner
        # is a port of these rules and must stay byte-identical.
        self.assertEqual(
            clean_text("First thing. second thing third thing?", "notes"),
            "First thing.\nSecond thing third thing?",
        )
