"""request_secret: a Bot asks for a credential, the person types it into a masked card, and Hermes saves
it in the profile's .env. The value never reaches the Bot or the chat.

Hermes sends its `secret` prompt only while loading a skill that declares a missing credential. This
tool hands any request to that same prompt, so Usual Bot shows its usual card and Hermes saves the
answer as it does for skills. It works only in the chats Usual Bot opened: Hermes lists a plugin's tools
in every app, and elsewhere a prompt may have nothing to show it.
"""

from __future__ import annotations

import contextlib
import json
import logging
import re

from . import store

log = logging.getLogger(__name__)

NAME = "request_secret"

# As Hermes's own check on a skill's variable names (tools/skills_tool_setup.py).
_ENV_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

SCHEMA = {
    "name": NAME,
    "description": (
        "Ask the person for a secret, such as an API key, a bot token or a password, through a masked "
        "field in Usual Bot. Hermes saves it as an environment variable in this profile's .env, where "
        "skills and tools that need it read it. You never see the value, and the person never has to paste "
        "it in the chat. Use this whenever you need a credential, instead of asking for it in a message; if "
        "the person pastes one anyway, suggest they replace it this way. Never print the saved value. "
        "Works only in chats Usual Bot opened."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "env_var": {
                "type": "string",
                "description": "Environment variable to save it as, e.g. TRADINGHUB_BOT_TOKEN. Upper case "
                "with underscores. Saving to a name that's already set replaces its value.",
            },
            "prompt": {
                "type": "string",
                "description": "Short heading for the field, in the person's language, e.g. "
                "\"Token for @TradinghubBot\".",
            },
            "help": {
                "type": "string",
                "description": "Optional: one sentence on what it is or where to get it, e.g. "
                "\"The token BotFather gave you for the Tradinghub Telegram bot.\"",
            },
        },
        "required": ["env_var", "prompt"],
        "additionalProperties": False,
    },
}


def _result(**fields) -> str:
    return json.dumps(fields)


def _capture_callback():
    """The prompt Hermes's skills use: the turn's own when one is bound, else the process's. Neither is a
    public Hermes API, so a missing one means "can't ask here", never a crash."""
    try:
        from tools import skills_tool
    except Exception:  # noqa: BLE001 - another Hermes layout
        return None
    turn = getattr(skills_tool, "_turn_secret_capture", None)
    callback = turn.get() if turn is not None else None
    return callback or getattr(skills_tool, "_secret_capture_callback", None)


@contextlib.contextmanager
def _waiting_for_person(prompt: str):
    """As Hermes's sudo prompt: hooks hear a person is needed (so push reaches a closed app) and how
    it ended, and the time spent typing doesn't count against the tool's deadline. Yields a setter
    for the outcome. Either part missing from this Hermes is left out."""
    with contextlib.ExitStack() as stack:
        human = None
        try:
            from tools.human_input_hooks import human_input_request
            human = stack.enter_context(human_input_request("secret", prompt=prompt))
        except Exception:  # noqa: BLE001 - another Hermes layout
            pass
        try:
            from tools.approval_human_wait import human_wait_window
            stack.enter_context(human_wait_window())
        except Exception:  # noqa: BLE001 - another Hermes layout
            pass

        def outcome(value: str) -> None:
            if human is not None:
                human.outcome = value

        yield outcome


def request(args: dict, session_id: str = "", **_) -> str:
    env_var = str(args.get("env_var") or "").strip()
    prompt = str(args.get("prompt") or "").strip()
    help_text = str(args.get("help") or "").strip()
    if not _ENV_NAME.match(env_var):
        return _result(saved=False, error=f"{env_var!r} isn't a valid environment variable name.")
    if not store.is_app_chat(str(session_id or "")):
        return _result(
            saved=False,
            error="request_secret works only in chats Usual Bot opened. Ask the person to add "
            f"{env_var} to this profile's .env in the Hermes app or on the gateway. Don't ask for the "
            "value in the chat.",
        )
    callback = _capture_callback()
    if callback is None:
        return _result(
            saved=False,
            error="This gateway's Hermes can't show a secret prompt. Ask the person to update Usual Bot's "
            f"plugin, or to add {env_var} to this profile's .env themselves.",
        )
    prompt = prompt or f"Enter value for {env_var}"
    with _waiting_for_person(prompt) as ended:
        try:
            outcome = callback(env_var, prompt, {"help": help_text} if help_text else None)
        except Exception as exc:  # noqa: BLE001 - the error could carry the value, so only its type is logged
            log.warning("usual-bot: couldn't save a secret: %s", type(exc).__name__)
            outcome = None
        saved = isinstance(outcome, dict) and outcome.get("success")
        ended(("skipped" if outcome.get("skipped") else "provided") if saved else "error")
    if not saved:
        return _result(saved=False, env_var=env_var, error="Hermes couldn't save it. Ask the person to try again.")
    if outcome.get("skipped"):
        return _result(saved=False, env_var=env_var, skipped=True, message="The person skipped it, or the prompt timed out.")
    return _result(saved=True, env_var=env_var, message=f"Saved in this profile's .env as {env_var}.")
