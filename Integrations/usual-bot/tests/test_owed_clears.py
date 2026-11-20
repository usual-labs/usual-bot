"""A chat read on one device is taken down on the others by their next notification too, as iOS
can drop the silent push that should have done it."""

import base64
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def _load_plugin():
    # As a package, as Hermes loads it: the plugin's modules import one another relatively.
    spec = importlib.util.spec_from_file_location(
        "usual_bot_owed_clears", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
store, push, relay = plugin.store, plugin.push, plugin.relay
DEVICE = {"relay": "https://push.example.com", "send_key": "k", "seal_key": base64.b64encode(bytes(32)).decode()}


class OwedClearsTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        for patcher in (
            mock.patch.object(store, "_root", return_value=Path(folder.name)),
            mock.patch.object(relay, "seal", lambda key, payload: json.dumps(payload)),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        store.put_device("mac", DEVICE)
        store.put_device("phone", DEVICE)
        self.sent: list[dict] = []

    def deliver(self, chat: str, fate: str = "sent", preview: str = "hello") -> dict[str, dict]:
        """What each device's notification sealed."""
        def send(pushes, route="send"):
            self.sent = [entry for _, entry in pushes]
            return {entry["device"]: fate for entry in self.sent}

        with mock.patch.object(relay, "send", send):
            push.deliver("message", "{name}", preview, chat)
        return {entry["device"]: json.loads(entry["sealed"]) for entry in self.sent}

    def test_the_next_notification_carries_a_clear_the_silent_push_may_have_lost(self):
        self.deliver("ada")
        self.assertEqual(store.take_told("ada", "mac"), ["phone"])
        sealed = self.deliver("grace")
        self.assertEqual(sealed["phone"]["read"], ["ada"])
        self.assertNotIn("read", sealed["mac"])
        # Carried once.
        self.assertNotIn("read", self.deliver("grace")["phone"])

    def test_a_clear_waits_while_the_relay_doesnt_take_the_notification(self):
        self.deliver("ada")
        store.take_told("ada", "mac")
        self.deliver("grace", fate="failed")
        self.assertEqual(self.deliver("grace")["phone"]["read"], ["ada"])

    def test_a_new_notification_about_the_chat_takes_the_read_ones_down_first(self):
        self.deliver("ada")
        store.take_told("ada", "mac")
        store.note_told(["phone"], "grace")
        store.take_told("grace", "mac")
        self.assertEqual(self.deliver("ada")["phone"]["read"], ["ada", "grace"])

    def test_once_notified_again_about_a_chat_no_clear_is_owed_for_it(self):
        # Or a later notification would take down the new, unread one.
        self.deliver("ada")
        store.take_told("ada", "mac")
        store.note_told(["phone"], "ada")
        self.assertEqual(store.owed_clears("phone"), [])

    def test_reading_the_chat_on_the_device_itself_owes_it_nothing(self):
        self.deliver("ada")
        store.take_told("ada", "mac")
        store.note_told(["phone"], "ada")
        store.take_told("ada", "mac")
        self.assertEqual(store.owed_clears("phone"), ["ada"])
        store.take_told("ada", "phone")
        self.assertEqual(store.owed_clears("phone"), [])

    def test_only_what_fits_under_the_relays_limit_goes_and_the_rest_waits(self):
        chats = [f"local-{number:064x}" for number in range(40)]
        for chat in chats:
            store.note_told(["phone"], chat)
            store.take_told(chat, "mac")
        sealed = self.deliver("grace", preview="x" * 240)["phone"]
        self.assertLess(len(json.dumps(sealed | {"gateway": "g" * 64})), 2222)
        self.assertEqual(sealed["read"], list(reversed(chats))[: len(sealed["read"])])
        self.assertEqual(len(store.owed_clears("phone")), len(chats) - len(sealed["read"]))

    def test_a_removed_device_owes_nothing(self):
        self.deliver("ada")
        store.take_told("ada", "mac")
        store.remove_device("phone")
        self.assertEqual(store.owed_clears("phone"), [])


if __name__ == "__main__":
    unittest.main()
