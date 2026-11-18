"""Which devices still show a notification about a chat, so reading it elsewhere takes it down."""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import store  # noqa: E402  (by path: the plugin's folder name isn't a package name)


class ToldTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        patcher = mock.patch.object(store, "_root", return_value=Path(folder.name))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_reading_on_one_device_clears_the_others_once(self):
        store.note_told(["mac", "phone"], "ada")
        self.assertEqual(store.take_told("ada", "mac"), ["phone"])
        # The app reports the open chat every few seconds; only the first report clears.
        self.assertEqual(store.take_told("ada", "mac"), [])

    def test_a_chat_nobody_was_told_about_clears_nothing(self):
        store.note_told(["phone"], "ada")
        self.assertEqual(store.take_told("room:design", "mac"), [])
        self.assertEqual(store.take_told("ada", "mac"), ["phone"])

    def test_the_reader_forgets_its_own_and_isnt_sent_one(self):
        store.note_told(["phone"], "ada")
        self.assertEqual(store.take_told("ada", "phone"), [])
        self.assertEqual(store.take_told("ada", "mac"), [])

    def test_a_new_notification_after_reading_is_cleared_again(self):
        store.note_told(["phone"], "ada")
        store.take_told("ada", "mac")
        store.note_told(["phone"], "ada")
        self.assertEqual(store.take_told("ada", "mac"), ["phone"])

    def test_only_the_newest_chats_are_remembered(self):
        for number in range(store.TOLD_LIMIT + 1):
            store.note_told(["phone"], f"chat{number}")
        self.assertEqual(store.take_told("chat0", "mac"), [])
        self.assertEqual(store.take_told(f"chat{store.TOLD_LIMIT}", "mac"), ["phone"])

    def test_a_removed_device_is_forgotten(self):
        store.put_device("phone", {"relay": "https://push.example.com", "send_key": "k", "seal_key": "s"})
        store.note_told(["phone"], "ada")
        store.remove_device("phone")
        self.assertEqual(store.take_told("ada", "mac"), [])


if __name__ == "__main__":
    unittest.main()
