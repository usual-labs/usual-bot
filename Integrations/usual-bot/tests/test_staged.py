"""A notification goes to the device you're using, or used last, first; the others hear a little
later, unless you've read that chat by then."""

import base64
import importlib.util
import json
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
        "usual_bot_staged", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
store, push, relay = plugin.store, plugin.push, plugin.relay
DEVICE = {"relay": "https://push.example.com", "send_key": "k", "seal_key": base64.b64encode(bytes(32)).decode()}


class StagedTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.now = 1_000_000.0
        self.rounds: list[list[str]] = []
        self.meanwhile = lambda: None

        def send(pushes, route="send"):
            self.rounds.append(sorted(entry["device"] for _, entry in pushes))
            return {entry["device"]: "sent" for _, entry in pushes}

        def sleep(seconds):
            self.now += seconds
            self.rounds.append([f"waited {seconds}"])
            self.meanwhile()

        for patcher in (
            mock.patch.object(store, "_root", return_value=Path(folder.name)),
            mock.patch.object(relay, "seal", lambda key, payload: json.dumps(payload)),
            mock.patch.object(relay, "send", send),
            mock.patch.object(push.time, "sleep", sleep),
            mock.patch.object(time, "time", lambda: self.now),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        for device_id in ("mac", "phone", "ipad"):
            store.put_device(device_id, DEVICE)

    def later(self, seconds: float) -> None:
        self.now += seconds

    def deliver(self, chat: str = "ada") -> list[list[str]]:
        push.deliver("message", "{name}", "hello", chat)
        return self.rounds

    def test_with_no_device_seen_in_use_every_device_hears_at_once(self):
        # Apps from before this never say, so nothing changes for them.
        self.assertEqual(self.deliver(), [["ipad", "mac", "phone"]])

    def test_the_device_youre_using_hears_first_and_the_others_later(self):
        store.set_open("phone", None, active=True)
        self.assertEqual(self.deliver(), [["phone"], [f"waited {push.LATER}"], ["ipad", "mac"]])

    def test_with_none_in_use_the_one_used_last_hears_first(self):
        store.set_open("phone", None, active=True)
        self.later(60)
        store.set_open("mac", None, active=True)
        self.later(600)
        self.assertEqual(self.deliver(), [["mac"], [f"waited {push.LATER}"], ["ipad", "phone"]])

    def test_a_device_left_open_but_idle_doesnt_count_as_used(self):
        store.set_open("phone", None, active=True)
        self.later(60)
        store.set_open("mac", None, active=False)
        self.assertEqual(self.deliver()[0], ["phone"])

    def test_reading_the_chat_while_the_others_wait_keeps_them_quiet(self):
        store.set_open("phone", None, active=True)
        self.meanwhile = lambda: store.set_open("phone", "ada", active=True)
        self.assertEqual(self.deliver(), [["phone"], [f"waited {push.LATER}"]])

    def test_reading_another_chat_meanwhile_doesnt(self):
        store.set_open("phone", None, active=True)
        self.meanwhile = lambda: store.set_open("phone", "grace", active=True)
        self.assertEqual(self.deliver()[-1], ["ipad", "mac"])

    def test_a_chat_read_before_the_message_still_notifies(self):
        store.set_open("phone", "ada", active=True)
        self.later(60)
        store.set_open("phone", None, active=True)
        self.assertEqual(self.deliver()[-1], ["ipad", "mac"])

    def test_an_older_app_with_a_chat_open_counts_as_in_use(self):
        store.set_open("mac", "grace")
        self.assertEqual(self.deliver()[0], ["mac"])

    def test_a_device_muting_the_chat_isnt_first_even_in_use(self):
        store.put_device("phone", {"muted": ["ada"]})
        store.set_open("phone", None, active=True)
        store.set_open("mac", None, active=True)
        self.assertEqual(self.deliver(), [["mac"], [f"waited {push.LATER}"], ["ipad"]])

    def test_a_device_removed_while_the_others_wait_isnt_sent_to(self):
        store.set_open("phone", None, active=True)
        self.meanwhile = lambda: store.remove_device("ipad")
        self.assertEqual(self.deliver()[-1], ["mac"])


if __name__ == "__main__":
    unittest.main()
