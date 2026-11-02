"""Tells you what agents do through ntfy or Pushover, even when Usual Bot isn't running.

Hooks only watch: anything going wrong here is logged and never touches an agent's turn.
"""

from __future__ import annotations

import logging
import threading
import time
import urllib.parse
from pathlib import Path

from . import services, store

logger = logging.getLogger(__name__)

# Where a person talks to the agent. Leaves out helpers ("subagent"), routines and other platforms.
_CHAT_PLATFORMS = {"tui", "desktop", "dashboard"}
_ROOM_PLATFORM = "bot_room"
# A room's activity reports on a queue of its own, so it can land just after the reply's hook.
_ROOM_ACTIVITY_DELAY = 1.5
_PREVIEW_LIMIT = 240
_HIDDEN = {"message": "New message. Open Usual Bot to read it.", "needs_you": "Open Usual Bot to answer."}


def _profile() -> str:
    from hermes_constants import get_hermes_home

    home = Path(get_hermes_home())
    return home.name if home.parent.name == "profiles" else "default"


def _shorten(text: str) -> str:
    line = " ".join(text.split())
    return line if len(line) <= _PREVIEW_LIMIT else line[: _PREVIEW_LIMIT - 1] + "…"


def _deliver(kind: str, title: str, preview: str, chat: str, speaker: str | None = None) -> None:
    settings = store.settings()
    if not services.is_ready(settings) or not settings.get(kind, True) or store.is_focused():
        return
    if speaker:
        preview = f"{settings['names'].get(speaker, speaker)}: {preview}"
    body = _shorten(preview) if settings.get("previews", True) else _HIDDEN[kind]
    link = "usualbot://chat/" + urllib.parse.quote(chat, safe="")
    try:
        services.send(settings, title.format(name=settings["names"].get(chat, chat)), body, link, kind == "needs_you")
    except Exception as error:  # Named only: a service's error can quote the message.
        logger.warning("usual-push: couldn't send through %s: %s", settings["service"], type(error).__name__)


def _push(kind: str, title: str, preview: str, chat: str) -> None:
    threading.Thread(target=_deliver, args=(kind, title, preview, chat), daemon=True).start()


def _deliver_room_reply(profile: str, text: str) -> None:
    """The reply's hook doesn't say which room, but that member's activity just did."""
    time.sleep(_ROOM_ACTIVITY_DELAY)
    if room := store.room_of(profile):
        _deliver("message", "{name}", text, f"room:{room}", speaker=profile)


def _on_reply(assistant_response="", platform="", **_) -> None:
    if not assistant_response.strip():
        return
    if platform in _CHAT_PLATFORMS:
        _push("message", "{name}", assistant_response, _profile())
    elif platform == _ROOM_PLATFORM:
        threading.Thread(target=_deliver_room_reply, args=(_profile(), assistant_response), daemon=True).start()


def _on_request(kind="", platform="", prompt="", **_) -> None:
    if platform not in _CHAT_PLATFORMS:
        return
    asks = {"approval": f"Wants to run “{prompt}”", "sudo": "Asks for the sudo password"}.get(kind, prompt)
    _push("needs_you", "{name} needs you", asks, _profile())


def _on_room_activity(room_id="", member_id="", kind="", payload=None, **_) -> None:
    store.note_room(member_id, room_id)
    if kind == "request.opened":
        command = (payload or {}).get("command") or "a command"
        _push("needs_you", "{name} needs you", f"{member_id} wants to run “{command}”", f"room:{room_id}")


def register(ctx) -> None:
    ctx.register_hook("post_llm_call", _on_reply)
    ctx.register_hook("on_human_input_request", _on_request)
    ctx.register_hook("on_room_member_activity", _on_room_activity)
