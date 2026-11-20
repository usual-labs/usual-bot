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


class BotTurnTests(unittest.TestCase):
    """A reply to another Bot's message goes back to that Bot; the push is the sender's report."""

    ASK = "Message from 🤖 CMO (@cmo): Make the Work Analyst a routine on my profile."

    def test_a_bots_message_is_a_bot_turn(self):
        history = [{"role": "user", "content": self.ASK, "display_kind": "internal_notification"},
                   {"role": "tool", "content": "ok"}]
        self.assertTrue(turns.asked_by_bot(history))

    def test_a_routine_or_your_message_isnt(self):
        routine = '[Cronjob "brief" output — sent]\n\nHello'
        self.assertFalse(turns.asked_by_bot([{"role": "user", "content": routine, "display_kind": "internal_notification"}]))
        self.assertFalse(turns.asked_by_bot([{"role": "user", "content": self.ASK}]))
        self.assertFalse(turns.asked_by_bot(None))

    def test_only_the_newest_message_counts(self):
        history = [{"role": "user", "content": self.ASK, "display_kind": "internal_notification"},
                   {"role": "assistant", "content": "Done."}, {"role": "user", "content": "Thanks"}]
        self.assertFalse(turns.asked_by_bot(history))


if __name__ == "__main__":
    unittest.main()


class SilentReplyTests(unittest.TestCase):
    """A Bot answering `[SILENT]` chose not to reply: nothing to notify."""

    def test_a_bare_marker_says_nothing(self):
        for marker in ("[SILENT]", "NO_REPLY", " no_reply. ", "*NO_REPLY*"):
            self.assertEqual(turns.said(marker), "", marker)

    def test_prose_is_kept(self):
        self.assertEqual(turns.said("The status is NO_REPLY needed."), "The status is NO_REPLY needed.")

    def test_a_closing_marker_goes(self):
        self.assertEqual(turns.said("Done.\n\nNO_REPLY"), "Done.")
