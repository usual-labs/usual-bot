"""Which gateway sent a notification: the ID the device gave it, sealed in, so a device with two
gateways can tell their `default` chats apart."""

import base64
import json
import re
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import relay  # noqa: E402  (by path: the plugin's folder name isn't a package name)

KEY = base64.b64encode(bytes(32)).decode()
DEVICE = {"send_key": "send", "seal_key": KEY}


def _opened(entry: dict) -> dict:
    """What was sealed, with `seal` swapped for plain JSON so this runs without `cryptography`."""
    return json.loads(entry["sealed"])


class GatewayTagTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(relay, "seal", lambda key, payload: json.dumps(payload))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_device_that_named_this_gateway_hears_its_name(self):
        device = DEVICE | {"gateway": "home"}
        entry = relay.push("phone", device, "message", {"title": "Hermes", "chat": "default"}, "default")
        self.assertEqual(_opened(entry)["gateway"], "home")
        self.assertEqual(_opened(relay.clear("phone", device, "default"))["gateway"], "home")

    def test_a_device_from_before_gets_what_it_always_did(self):
        entry = relay.push("phone", DEVICE, "message", {"title": "Hermes", "chat": "default"}, "default")
        self.assertNotIn("gateway", _opened(entry))
        self.assertEqual(entry["thread"], relay.thread(KEY, "default"))
        self.assertEqual(_opened(relay.clear("phone", DEVICE, "default")), {"kind": "read", "chat": "default"})

    def test_the_same_chat_on_two_gateways_groups_apart(self):
        home = relay.push("phone", DEVICE | {"gateway": "home"}, "message", {}, "default")["thread"]
        work = relay.push("phone", DEVICE | {"gateway": "work"}, "message", {}, "default")["thread"]
        self.assertNotEqual(home, work)
        self.assertNotEqual(home, relay.thread(KEY, "default"))


class VersionTests(unittest.TestCase):
    def test_every_file_says_the_same_version(self):
        code = re.search(r'^VERSION = "(.+)"$', (ROOT / "__init__.py").read_text(), re.MULTILINE).group(1)
        listed = re.search(r'^version: "(.+)"$', (ROOT / "plugin.yaml").read_text(), re.MULTILINE).group(1)
        manifest = json.loads((ROOT / "dashboard" / "manifest.json").read_text())["version"]
        self.assertEqual({code, listed, manifest}, {code})


if __name__ == "__main__":
    unittest.main()
