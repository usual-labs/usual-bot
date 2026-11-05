"""The devices Usual Bot pushes to, and which chat each has open. Shared by every profile on this gateway."""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path

_lock = threading.Lock()
_rooms_seen: dict[str, str] = {}
# Usual Bot repeats this while a chat is open, so a crashed app can't silence pushes for long.
PRESENCE_LIFETIME = 15

# A device's choices. Everything is on until its owner turns it off on that device.
CHOICES = {"message": True, "needs_you": True, "previews": True, "sound": True}
# Kept here, never shown back: the relay's key to push to the device, and the key that seals for it.
SECRETS = ("send_key", "seal_key")


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
    return {"devices": {}, "names": {}} | _read("settings.json")


def devices() -> dict[str, dict]:
    return settings()["devices"]


def put_device(device_id: str, changes: dict) -> dict:
    """Adds a device or changes it. Fields left out stay as they were."""
    with _lock:
        values = settings()
        device = CHOICES | {"muted": []} | values["devices"].get(device_id, {}) | changes
        values["devices"][device_id] = device
        _write("settings.json", values)
        return device


def remove_device(device_id: str) -> None:
    with _lock:
        values = settings()
        if values["devices"].pop(device_id, None) is not None:
            _write("settings.json", values)


def set_names(names: dict[str, str]) -> None:
    with _lock:
        _write("settings.json", settings() | {"names": names})


def public(device_id: str, device: dict) -> dict:
    """A device without its keys, for the app to show."""
    return {"id": device_id} | {key: value for key, value in device.items() if key not in SECRETS}


def note_room(member: str, room: str) -> None:
    """Remembers where a member last spoke. A file, as each profile loads this plugin apart."""
    if _rooms_seen.get(member) == room:
        return
    _rooms_seen[member] = room
    with _lock:
        _write("rooms.json", _read("rooms.json") | {member: room})


def room_of(member: str) -> str | None:
    return _read("rooms.json").get(member)


def _presence() -> dict[str, dict]:
    # Only devices' entries: version 0.1 kept a single {"focused", "at"} here.
    return {key: value for key, value in _read("presence.json").items() if isinstance(value, dict)}


def set_open(device_id: str, chat: str | None) -> None:
    """The chat a device has in front of you, or `None` once it has none."""
    with _lock:
        presence = _presence()
        if chat is None:
            presence.pop(device_id, None)
        else:
            presence[device_id] = {"chat": chat, "at": time.time()}
        _write("presence.json", presence)


def is_open(chat: str) -> bool:
    """Whether you're reading this chat on any device: then none of them hears about it."""
    now = time.time()
    return any(
        entry.get("chat") == chat and now - entry.get("at", 0) < PRESENCE_LIFETIME
        for entry in _presence().values()
    )
