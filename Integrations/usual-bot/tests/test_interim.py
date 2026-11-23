"""What a Bot says on the way to its reply ("On it, looking now") notifies like the reply itself."""

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def _load_plugin():
    # As a package, as Hermes loads it: the plugin's modules import one another relatively.
    spec = importlib.util.spec_from_file_location(
        "usual_bot_interim", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
push = plugin.push
TYPED = [{"role": "user", "content": "Find me a cake for Friday"}]


class InterimTests(unittest.TestCase):
    def setUp(self):
        self.pushed: list[tuple[str, str]] = []
        for patcher in (
            mock.patch.object(push, "_push_unless_hidden", lambda kind, title, text, chat, interim=False: self.pushed.append((text, interim))),
            mock.patch.object(push, "_profile", return_value="hermes"),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def start(self, turn_id, history=TYPED, platform="desktop"):
        plugin._before_turn(
            session_id="s", platform=platform, conversation_history=history, user_message="", turn_id=turn_id
        )

    def test_mid_turn_words_and_the_reply_both_notify(self):
        self.start("t1")
        push.on_interim(text="On it. Looking for bakeries.", surface="desktop", turn_id="t1")
        push.on_reply(assistant_response="Here are the best ones.", platform="desktop", conversation_history=TYPED)
        self.assertEqual(
            self.pushed, [("On it. Looking for bakeries.", True), ("Here are the best ones.", False)]
        )

    def test_a_turn_that_wasnt_seen_starting_is_quiet(self):
        # A side question's fork runs without `pre_llm_call` and shares the chat's surface.
        push.on_interim(text="Thinking about it", surface="desktop", turn_id="fork")
        push.on_interim(text="No turn at all", surface="desktop", turn_id="")
        self.assertEqual(self.pushed, [])

    def test_a_turn_another_bot_started_is_quiet(self):
        self.start("t2", [{"role": "user", "content": "Message from 🤖 CMO (@cmo): hi", "display_kind": "internal_notification"}])
        push.on_interim(text="Checking", surface="desktop", turn_id="t2")
        self.assertEqual(self.pushed, [])

    def test_hermess_own_hidden_prompt_is_quiet(self):
        self.start("t3", [{"role": "user", "content": "Continue the goal", "display_kind": "hidden"}])
        push.on_interim(text="Next step", surface="desktop", turn_id="t3")
        self.assertEqual(self.pushed, [])

    def test_a_routine_is_quiet(self):
        self.start("t4", platform="cron")
        push.on_interim(text="Running the report", surface="cron", turn_id="t4")
        self.assertEqual(self.pushed, [])

    def test_a_silent_marker_mid_turn_is_quiet(self):
        self.start("t5")
        push.on_interim(text="[SILENT]", surface="desktop", turn_id="t5")
        self.assertEqual(self.pushed, [])

    def test_only_the_newest_turns_are_remembered(self):
        for number in range(push._LOUD_TURNS_LIMIT + 1):
            self.start(f"turn{number}")
        push.on_interim(text="Old", surface="desktop", turn_id="turn0")
        push.on_interim(text="New", surface="desktop", turn_id=f"turn{push._LOUD_TURNS_LIMIT}")
        self.assertEqual(self.pushed, [("New", True)])


if __name__ == "__main__":
    unittest.main()
