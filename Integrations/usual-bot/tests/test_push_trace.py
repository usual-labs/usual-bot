"""What the gateway adds to follow one notification from the gateway to a device."""

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
    spec = importlib.util.spec_from_file_location(
        "usual_bot_push_trace", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
store, push, relay = plugin.store, plugin.push, plugin.relay
DEVICE = {"relay": "https://push.example.com", "send_key": "k", "seal_key": base64.b64encode(bytes(32)).decode()}


class PushTraceTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        for patcher in (
            mock.patch.object(store, "_root", return_value=Path(folder.name)),
            mock.patch.object(relay, "seal", lambda key, payload: json.dumps(payload)),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        store.put_device("phone", DEVICE)

    def test_a_notification_says_when_it_left(self):
        sent = []

        def send(pushes, route="send"):
            sent.extend(entry for _, entry in pushes)
            return {entry["device"]: "sent" for entry in sent}

        before = time.time()
        with mock.patch.object(relay, "send", send):
            push.deliver("message", "{name}", "hello", "ada")
        sealed = json.loads(sent[0]["sealed"])
        self.assertGreaterEqual(sealed["sent_at"], round(before, 3))
        self.assertLessEqual(sealed["sent_at"], time.time())

    def test_tags_match_the_apps(self):
        # `Trace.tag("ada")` in HermesKit gives the same, so the logs line up.
        self.assertEqual(push.tag("ada"), "fdee430d")


if __name__ == "__main__":
    unittest.main()
