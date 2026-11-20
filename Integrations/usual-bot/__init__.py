"""usual-bot: what Usual Bot needs from your gateway, in one plugin.

  push.py                   tells your devices what Bots do, through Usual's push relay
  flags.py                  the Chrome flags a Bot's headless real-profile browser launches with
  context.py                tells a Bot, in the app's chats only, that it's talking through Usual Bot
  secret_prompt.py          request_secret: a Bot asks for a credential and Hermes saves it, unseen
  dashboard/                the routes the app calls: devices, the chats it opened, the browser feed

Hooks never stop a turn: anything going wrong here is logged and the turn goes on without it.
"""

from __future__ import annotations

import logging

from . import context, flags, push, secret_prompt, store

log = logging.getLogger(__name__)

# As in plugin.yaml. The app reads it to offer an update.
VERSION = "0.8.0"

# Where a person talks to the agent. Leaves out helpers ("subagent"), routines ("cron") and rooms
# ("bot_room"), whose sessions continue no chat of the app's. A gateway's own chats can say "local".
_CHAT_PLATFORMS = {"tui", "desktop", "dashboard", "local"}


def _before_tool(tool_name: str = "", **_) -> None:
    """Before a browser tool runs (and so before the Bot's browser can launch), bring the flags up to
    date. Never blocks the tool: Hermes treats a raising hook as a veto."""
    if not str(tool_name).startswith("browser"):
        return None
    try:
        flags.sync()
    except Exception as exc:  # noqa: BLE001 - a flag problem must never stop the Bot browsing
        log.warning("usual-bot: could not update the browser flags: %s", exc)
    return None


def _before_turn(
    session_id="", parent_session_id="", platform="", conversation_history=None, user_message="", **_
):
    """The chat context, in a chat the app opened that doesn't have it yet. Routines' results and
    other Bots' messages posted into that chat get it too: they're turns in it. A turn another Bot
    started also gets a line saying who its reply goes to, every time."""
    try:
        if platform not in _CHAT_PLATFORMS:
            return None
        sender = context.bot_sender(user_message)
        told = context.told(conversation_history)
        if (told and sender is None) or not store.is_app_chat(str(session_id or ""), str(parent_session_id or "")):
            return None
        parts = ([] if told else [context.TEXT]) + ([context.bot_turn(*sender)] if sender else [])
        return {"context": "\n\n".join(parts)}
    except Exception as exc:  # noqa: BLE001 - the turn goes on without it
        log.warning("usual-bot: couldn't add the chat context: %s", type(exc).__name__)
        return None


def register(ctx) -> None:
    ctx.register_hook("post_llm_call", push.on_reply)
    ctx.register_hook("on_human_input_request", push.on_request)
    ctx.register_hook("on_room_member_activity", push.on_room_activity)
    ctx.register_hook("pre_tool_call", _before_tool)
    ctx.register_hook("pre_llm_call", _before_turn)
    ctx.register_tool(
        name=secret_prompt.NAME, toolset="usual_bot", schema=secret_prompt.SCHEMA,
        handler=secret_prompt.request, description="Ask for a secret in a masked field", emoji="🔑",
    )
