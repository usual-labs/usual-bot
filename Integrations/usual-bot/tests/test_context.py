"""A Bot is told about Usual Bot once per chat the app opened, and nowhere else."""

import importlib.util
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def _load_plugin():
    # As a package, as Hermes loads it: the plugin's modules import one another relatively.
    spec = importlib.util.spec_from_file_location(
        "usual_bot_under_test", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
store = plugin.store
context = plugin.context


class ContextTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        patcher = mock.patch.object(store, "_root", return_value=Path(folder.name))
        patcher.start()
        self.addCleanup(patcher.stop)

    def turn(self, session="s1", history=None, platform="tui", parent=""):
        history = history if history is not None else [{"role": "user", "content": "hi"}]
        return plugin._before_turn(
            session_id=session, parent_session_id=parent, platform=platform, conversation_history=history,
            user_message="hi", is_first_turn=True, model="m", task_id="t", turn_id="u", sender_id="")

    def test_a_chat_the_app_opened_is_told(self):
        store.note_chat("s1")
        self.assertEqual(self.turn(), {"context": context.TEXT})

    def test_other_chats_arent(self):
        store.note_chat("s1")
        self.assertIsNone(self.turn(session="s2"))

    def test_only_once_while_the_history_has_it(self):
        store.note_chat("s1")
        # Hermes keeps what it sent as the message's `api_content` and gives it back on later turns.
        told = [
            {"role": "user", "content": "hi", "api_content": "hi\n\n" + context.TEXT},
            {"role": "assistant", "content": "Hello."},
            {"role": "user", "content": "and now?"},
        ]
        self.assertIsNone(self.turn(history=told))

    def test_again_once_compression_drops_it(self):
        store.note_chat("s1")
        compressed = [{"role": "user", "content": "[summary of earlier turns]"}, {"role": "user", "content": "next"}]
        self.assertEqual(self.turn(history=compressed), {"context": context.TEXT})

    def test_a_message_with_images_carries_it_as_a_part(self):
        store.note_chat("s1")
        told = [{"role": "user", "content": [{"type": "image_url"}, {"type": "text", "text": context.TEXT}]}]
        self.assertIsNone(self.turn(history=told))

    def test_a_chat_compression_moved_to_a_new_session_is_still_the_apps(self):
        store.note_chat("old")
        self.assertIsNotNone(self.turn(session="new", parent="old"))
        # Remembered under its new ID, so it stays the app's once the old one is forgotten.
        self.assertIn("new", store._read("chats.json"))

    def test_helpers_routines_and_rooms_arent_told(self):
        store.note_chat("s1")
        for platform in ("subagent", "cron", "bot_room"):
            self.assertIsNone(self.turn(session="child", parent="s1", platform=platform), platform)
        self.assertNotIn("child", store._read("chats.json"))

    def test_a_chat_unused_for_30_days_is_forgotten(self):
        store.note_chat("s1")
        later = time.time() + store.CHAT_LIFETIME + 1
        with mock.patch.object(store.time, "time", return_value=later):
            self.assertIsNone(self.turn())

    def test_using_it_keeps_it(self):
        store.note_chat("s1")
        day = time.time() + 2 * 24 * 3600
        with mock.patch.object(store.time, "time", return_value=day):
            self.turn()
        with mock.patch.object(store.time, "time", return_value=day + store.CHAT_LIFETIME - 60):
            self.assertIsNotNone(self.turn())

    def test_a_broken_store_never_stops_the_turn(self):
        with mock.patch.object(store, "_read", side_effect=OSError("disk")):
            self.assertIsNone(self.turn())

    def test_the_text_says_who_and_what_shows(self):
        for words in ("Usual Bot", "isn't Hermes's official app", "Nous Research", "MEDIA:", "::preview",
                      "also send it on a MEDIA: line"):
            self.assertIn(words, context.TEXT)
        self.assertLess(len(context.TEXT), 2000)


if __name__ == "__main__":
    unittest.main()
