"""Replies to a hidden prompt (an inline widget's) don't notify."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import turns  # noqa: E402  (by path: the plugin's folder name isn't a package name)


class HiddenTurnTests(unittest.TestCase):
    def test_a_widgets_prompt_is_hidden(self):
        history = [
            {"role": "user", "content": "Show me disk use"},
            {"role": "assistant", "content": "Here it is."},
            {"role": "user", "content": "Clear old logs on db-1", "display_kind": "hidden"},
            {"role": "tool", "content": "ok"},
        ]
        self.assertTrue(turns.asked_hidden(history))

    def test_a_message_you_typed_isnt(self):
        history = [
            {"role": "user", "content": "Clear old logs", "display_kind": "hidden"},
            {"role": "assistant", "content": "Done."},
            {"role": "user", "content": "Thanks"},
        ]
        self.assertFalse(turns.asked_hidden(history))

    def test_another_kind_still_notifies(self):
        self.assertFalse(turns.asked_hidden([{"role": "user", "content": "x", "display_kind": "internal_notification"}]))

    def test_no_history_notifies(self):
        self.assertFalse(turns.asked_hidden(None))
        self.assertFalse(turns.asked_hidden([]))


if __name__ == "__main__":
    unittest.main()
