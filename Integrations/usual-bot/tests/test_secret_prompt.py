"""request_secret hands a Bot's request to Hermes's own secret prompt, only in the app's chats, and the
value never comes back to the Bot."""

import contextlib
import json
import sys
import types
import unittest
from unittest import mock

from test_context import plugin

secret_prompt = plugin.secret_prompt
TYPED = "123456:typed-by-the-person"


class SecretPromptCase(unittest.TestCase):
    def setUp(self):
        self.asked = []
        self.answer = {"success": True, "stored_as": "TRADINGHUB_BOT_TOKEN", "validated": False, "skipped": False}
        self.hooks = []

        def capture(env_var, prompt, metadata=None):
            self.asked.append((env_var, prompt, metadata))
            if isinstance(self.answer, Exception):
                raise self.answer
            return self.answer

        skills_tool = types.ModuleType("tools.skills_tool")
        skills_tool._secret_capture_callback = capture
        skills_tool._turn_secret_capture = mock.Mock(get=mock.Mock(return_value=None))
        self.skills_tool = skills_tool

        @contextlib.contextmanager
        def human_input_request(kind, *, prompt="", **_):
            human = types.SimpleNamespace(outcome=None)
            self.hooks.append(("request", kind, prompt))
            yield human
            self.hooks.append(("resolved", kind, human.outcome))

        hooks = types.ModuleType("tools.human_input_hooks")
        hooks.human_input_request = human_input_request
        modules = {"tools": types.ModuleType("tools"), "tools.skills_tool": skills_tool,
                   "tools.human_input_hooks": hooks}
        patcher = mock.patch.dict(sys.modules, modules)
        patcher.start()
        self.addCleanup(patcher.stop)
        app_chat = mock.patch.object(plugin.store, "is_app_chat", side_effect=lambda sid, *_: sid == "app-chat")
        app_chat.start()
        self.addCleanup(app_chat.stop)

    def call(self, session="app-chat", **args):
        args = {"env_var": "TRADINGHUB_BOT_TOKEN", "prompt": "Token for @TradinghubBot"} | args
        return json.loads(secret_prompt.request(args, session_id=session))

    def test_asks_hermes_and_returns_no_value(self):
        result = self.call(help="From BotFather.")
        self.assertEqual(self.asked, [("TRADINGHUB_BOT_TOKEN", "Token for @TradinghubBot", {"help": "From BotFather."})])
        self.assertTrue(result["saved"])
        self.assertNotIn(TYPED, json.dumps(result))
        self.assertEqual(self.hooks, [("request", "secret", "Token for @TradinghubBot"),
                                      ("resolved", "secret", "provided")])

    def test_no_help_sends_no_metadata(self):
        self.call()
        self.assertIsNone(self.asked[0][2])

    def test_the_turns_own_prompt_wins(self):
        turn = mock.Mock(return_value=self.answer)
        self.skills_tool._turn_secret_capture.get.return_value = turn
        self.call()
        turn.assert_called_once()
        self.assertEqual(self.asked, [])

    def test_skipped(self):
        self.answer = {"success": True, "stored_as": "TRADINGHUB_BOT_TOKEN", "skipped": True}
        result = self.call()
        self.assertFalse(result["saved"])
        self.assertTrue(result["skipped"])
        self.assertEqual(self.hooks[-1], ("resolved", "secret", "skipped"))

    def test_only_in_the_apps_chats(self):
        result = self.call(session="telegram-chat")
        self.assertFalse(result["saved"])
        self.assertIn("only in chats Usual Bot opened", result["error"])
        self.assertEqual((self.asked, self.hooks), ([], []))

    def test_rejects_a_bad_name(self):
        for name in ("", "1ABC", "A-B", "A B", "A=B"):
            self.assertFalse(self.call(env_var=name)["saved"])
        self.assertEqual(self.asked, [])

    def test_a_hermes_without_the_prompt(self):
        del self.skills_tool._secret_capture_callback
        result = self.call()
        self.assertFalse(result["saved"])
        self.assertIn("can't show a secret prompt", result["error"])

    def test_a_failed_save_logs_no_value(self):
        self.answer = ValueError(f"bad value {TYPED}")
        with self.assertLogs(secret_prompt.log, "WARNING") as logs:
            result = self.call()
        self.assertFalse(result["saved"])
        self.assertNotIn(TYPED, "".join(logs.output) + json.dumps(result))
        self.assertEqual(self.hooks[-1], ("resolved", "secret", "error"))

    def test_registered_as_a_tool(self):
        ctx = mock.Mock()
        plugin.register(ctx)
        tool = ctx.register_tool.call_args.kwargs
        self.assertEqual((tool["name"], tool["schema"]["name"]), ("request_secret", "request_secret"))
        self.assertIs(tool["handler"], secret_prompt.request)


if __name__ == "__main__":
    unittest.main()
