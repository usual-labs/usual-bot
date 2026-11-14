"""Tells your devices what agents do, through Usual's push relay, even when Usual Bot isn't running.

Hooks only watch: anything going wrong here is logged and never touches an agent's turn.
"""

from __future__ import annotations

import logging
import threading
import time
from pathlib import Path

from . import relay, store
from .plain import plain

logger = logging.getLogger(__name__)

# As in plugin.yaml. The app reads it to know this plugin says which gateway sent each notification.
VERSION = "0.5.0"

# Where a person talks to the agent. Leaves out helpers ("subagent"), routines and other platforms.
_CHAT_PLATFORMS = {"tui", "desktop", "dashboard"}
# A gateway's own chats (`hermes gateway`) ask for input as "local", whichever app made them, a
# terminal's or an editor's included; Hermes's plugin session API says which.
_GATEWAY_PLATFORM = "local"
_ROOM_PLATFORM = "bot_room"
# A room's activity reports on a queue of its own, so it can land just after the reply's hook.
_ROOM_ACTIVITY_DELAY = 1.5
_PREVIEW_LIMIT = 240
_HIDDEN = {"message": "New message. Open Usual Bot to read it.", "needs_you": "Open Usual Bot to answer."}
TEST = {"title": "Usual Bot", "body": "Notifications from your gateway are working."}


def _home() -> Path:
    """The profile whose hook is running. Only right in the hook itself: a thread it starts sees
    the gateway's main home, as a gateway serving several profiles sets the home per call."""
    from hermes_constants import get_hermes_home

    return Path(get_hermes_home())


def _profile() -> str:
    home = _home()
    return home.name if home.parent.name == "profiles" else "default"


def _is_hidden(home: Path) -> bool:
    """Hidden from the sidebar, in Usual Bot or the official app: it keeps working, quietly.

    Hermes keeps that in the profile's ``profile.yaml``, under ``ui_meta['hermes-bots'].hidden``.
    """
    try:
        try:
            from hermes_yaml import safe_load
        except ImportError:  # A Hermes from before its own YAML module.
            from yaml import safe_load
        meta = safe_load((home / "profile.yaml").read_text(encoding="utf-8-sig")) or {}
        return meta.get("ui_meta", {}).get("hermes-bots", {}).get("hidden") is True
    except Exception:  # Missing or odd: notify, as before hiding existed.
        return False


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
    if not pushes:
        return
    fates = relay.send(pushes)
    _forget_gone(fates)
    store.note_told([device_id for device_id, fate in fates.items() if fate == "sent"], chat)


def read_on(reader: str, chat: str) -> None:
    """You're reading `chat` on `reader`: your other devices take down what they show about it.

    Runs on every presence report, so it sends only to devices notified about it since."""
    others = store.take_told(chat, reader)
    if others:
        threading.Thread(target=_safely, args=(_clear, others, chat), daemon=True).start()


def _clear(device_ids: list[str], chat: str) -> None:
    devices = store.devices()
    pushes = [(devices[key]["relay"], relay.clear(key, devices[key], chat)) for key in device_ids if key in devices]
    if pushes:
        _forget_gone(relay.send(pushes, route="clear"))


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


def _push_unless_hidden(kind: str, title: str, preview: str, chat: str) -> None:
    """A Bot's own chat. A hidden Bot still speaks up in rooms, which aren't hidden."""
    home = _home()

    def deliver_unless_hidden() -> None:
        if not _is_hidden(home):
            deliver(kind, title, preview, chat)

    threading.Thread(target=_safely, args=(deliver_unless_hidden,), daemon=True).start()


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
    said = plain(assistant_response)
    if platform in _CHAT_PLATFORMS:
        _push_unless_hidden("message", "{name}", said, _profile())
    elif platform == _ROOM_PLATFORM:
        threading.Thread(target=_safely, args=(_deliver_room_reply, _profile(), said), daemon=True).start()


def _surface() -> str:
    """The app a gateway chat's turn runs for: ``tui``, ``desktop``, ``cli`` or ``acp``."""
    try:
        from hermes_cli.plugin_session import session_surface

        return session_surface()
    except Exception:  # A Hermes without it: notify, as for any chat.
        return "tui"


def _on_request(kind="", platform="", prompt="", **_) -> None:
    if platform == _GATEWAY_PLATFORM:
        platform = _surface()
    if platform not in _CHAT_PLATFORMS:
        return
    asks = {"approval": f"Wants to run “{prompt}”", "sudo": "Asks for the sudo password"}.get(kind) or plain(prompt)
    _push_unless_hidden("needs_you", "{name} needs you", asks, _profile())


def _on_room_activity(room_id="", member_id="", kind="", payload=None, **_) -> None:
    store.note_room(member_id, room_id)
    if kind == "request.opened":
        command = (payload or {}).get("command") or "a command"
        _push("needs_you", "{name} needs you", f"{member_id} wants to run “{command}”", f"room:{room_id}")


def register(ctx) -> None:
    ctx.register_hook("post_llm_call", _on_reply)
    ctx.register_hook("on_human_input_request", _on_request)
    ctx.register_hook("on_room_member_activity", _on_room_activity)
