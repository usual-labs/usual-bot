"""Push settings and whether you're at Usual Bot. Shared by every profile on this gateway."""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path

_lock = threading.Lock()
_rooms_seen: dict[str, str] = {}
# Usual Bot repeats this while you're at it, so a crashed app can't silence pushes for long.
PRESENCE_LIFETIME = 15

DEFAULTS = {
    "service": "off",  # "off", "ntfy" or "pushover"
    "server": "https://ntfy.sh",
    "topic": "",
    "ntfy_token": "",
    "token": "",  # The Pushover application token
    "user_key": "",  # Pushover only
    "message": True,
    "needs_you": True,
    "previews": True,
    "names": {},  # Chat ID to the name Usual Bot shows for it
}
SECRETS = ("ntfy_token", "token", "user_key")


def _root() -> Path:
    from hermes_constants import get_default_hermes_root

    return get_default_hermes_root() / "usual-push"


def _read(name: str) -> dict:
    try:
        return json.loads((_root() / name).read_text())
    except (OSError, ValueError):
        return {}


def _write(name: str, value: dict) -> None:
    root = _root()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = root / f".{name}.tmp"
    temporary.touch(mode=0o600)
    temporary.write_text(json.dumps(value, indent=2))
    temporary.replace(root / name)


def settings() -> dict:
    return DEFAULTS | _read("settings.json")


def update(changes: dict) -> dict:
    with _lock:
        merged = settings() | changes
        _write("settings.json", merged)
        return merged


def public(values: dict) -> dict:
    """The settings without their secrets, for the app to show."""
    shown = {key: value for key, value in values.items() if key not in SECRETS and key != "names"}
    return shown | {f"has_{key}": bool(values.get(key)) for key in SECRETS}


def note_room(member: str, room: str) -> None:
    """Remembers where a member last spoke. A file, as each profile loads this plugin apart."""
    if _rooms_seen.get(member) == room:
        return
    _rooms_seen[member] = room
    with _lock:
        _write("rooms.json", _read("rooms.json") | {member: room})


def room_of(member: str) -> str | None:
    return _read("rooms.json").get(member)


def set_focused(focused: bool) -> None:
    with _lock:
        _write("presence.json", {"focused": focused, "at": time.time()})


def is_focused() -> bool:
    presence = _read("presence.json")
    return presence.get("focused") is True and time.time() - presence.get("at", 0) < PRESENCE_LIFETIME
