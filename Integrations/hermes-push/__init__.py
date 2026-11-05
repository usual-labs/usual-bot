"""Tells your devices what agents do, through Usual's push relay, even when Usual Bot isn't running.

Hooks only watch: anything going wrong here is logged and never touches an agent's turn.
"""

from __future__ import annotations

import logging
import threading
import time
from pathlib import Path

from . import relay, store

logger = logging.getLogger(__name__)

# Where a person talks to the agent. Leaves out helpers ("subagent"), routines and other platforms.
_CHAT_PLATFORMS = {"tui", "desktop", "dashboard"}
_ROOM_PLATFORM = "bot_room"
# A room's activity reports on a queue of its own, so it can land just after the reply's hook.
_ROOM_ACTIVITY_DELAY = 1.5
_PREVIEW_LIMIT = 240
_HIDDEN = {"message": "New message. Open Usual Bot to read it.", "needs_you": "Open Usual Bot to answer."}
TEST = {"title": "Usual Bot", "body": "Notifications from your gateway are working."}


def _profile() -> str:
    from hermes_constants import get_hermes_home

    home = Path(get_hermes_home())
    return home.name if home.parent.name == "profiles" else "default"


def _shorten(text: str) -> str:
    line = " ".join(text.split())
    return line if len(line) <= _PREVIEW_LIMIT else line[: _PREVIEW_LIMIT - 1] + "…"


def deliver(kind: str, title: str, preview: str, chat: str, speaker: str | None = None) -> None:
    """To every device that wants it, unless you're reading that chat on one of them."""
    if store.is_open(chat):
        return
    settings = store.settings()
    names = settings["names"]
    if speaker:
        preview = f"{names.get(speaker, speaker)}: {preview}"
    title = title.format(name=names.get(chat, chat))
    pushes = []
    for device_id, device in settings["devices"].items():
        if not device.get(kind, True) or chat in device.get("muted", []):
            continue
        body = _shorten(preview) if device.get("previews", True) else _HIDDEN[kind]
        payload = {"title": title, "body": body, "chat": chat, "kind": kind, "sound": device.get("sound", True)}
        pushes.append((device["relay"], relay.push(device_id, device, kind, payload, chat)))
    _forget_gone(relay.send(pushes))


def send_test(device_id: str) -> str:
    """Answers the relay's verdict for that device, such as `sent`."""
    device = store.devices().get(device_id)
    if device is None:
        return "gone"
    payload = TEST | {"kind": "test", "sound": device.get("sound", True)}
    fates = relay.send([(device["relay"], relay.push(device_id, device, "test", payload, None))])
    _forget_gone(fates)
    return fates.get(device_id, "failed")


def _forget_gone(fates: dict[str, str]) -> None:
    for device_id, fate in fates.items():
        if fate == "gone":
            store.remove_device(device_id)


def _push(kind: str, title: str, preview: str, chat: str) -> None:
    threading.Thread(target=_safely, args=(deliver, kind, title, preview, chat), daemon=True).start()


def _safely(action, *args) -> None:
    try:
        action(*args)
    except Exception as error:  # Named only: an error can quote the message.
        logger.warning("usual-push: couldn't notify: %s", type(error).__name__)


def _deliver_room_reply(profile: str, text: str) -> None:
    """The reply's hook doesn't say which room, but that member's activity just did."""
    time.sleep(_ROOM_ACTIVITY_DELAY)
    if room := store.room_of(profile):
        deliver("message", "{name}", text, f"room:{room}", speaker=profile)


def _on_reply(assistant_response="", platform="", **_) -> None:
    if not assistant_response.strip():
        return
    if platform in _CHAT_PLATFORMS:
        _push("message", "{name}", assistant_response, _profile())
    elif platform == _ROOM_PLATFORM:
        threading.Thread(
            target=_safely, args=(_deliver_room_reply, _profile(), assistant_response), daemon=True
        ).start()


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
