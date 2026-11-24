"""The devices Usual Bot pushes to, which chat each has open, and which chats are the app's. Shared by
every profile on this gateway."""

from __future__ import annotations

import json
import threading
import time
from contextlib import contextmanager
from pathlib import Path

try:
    import fcntl
except ImportError:  # Windows: the lock then holds only within one process.
    fcntl = None

_lock = threading.Lock()
_rooms_seen: dict[str, str] = {}
# Usual Bot repeats this while a chat is open, so a crashed app can't silence pushes for long.
PRESENCE_LIFETIME = 15

# Chats a device remembers being notified about. Older ones just stay up when read elsewhere.
TOLD_LIMIT = 200

# A device's choices. Everything is on until its owner turns it off on that device.
CHOICES = {"message": True, "needs_you": True, "previews": True, "sound": True}
# Kept here, never shown back: the relay's key to push to the device, and the key that seals for it.
SECRETS = ("send_key", "seal_key")

# A chat the app hasn't opened, nor a Bot used, in this long is forgotten: it gets no chat context.
CHAT_LIFETIME = 30 * 24 * 3600
# How old a chat's last use can get before a turn writes it down again, so most turns write nothing.
_CHAT_REFRESH = 24 * 3600


def _root() -> Path:
    from hermes_constants import get_default_hermes_root

    # Named for the plugin push came from, so devices added before the plugins merged stay.
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
    with _shared():
        for name in ("told.json", "cleared.json"):
            entries = _read(name)
            if entries.pop(device_id, None) is not None:
                _write(name, entries)


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


def set_open(device_id: str, chat: str | None, active: bool | None = None) -> None:
    """The chat a device has in front of you, or `None` once it has none. `active` says you're
    using that device; an app from before it said so is in use whenever it has a chat open."""
    now = time.time()
    with _lock:
        presence = _presence()
        if chat is None:
            presence.pop(device_id, None)
        else:
            presence[device_id] = {"chat": chat, "at": now}
        _write("presence.json", presence)
        in_use = active or (active is None and chat is not None)
        if not (in_use or chat):
            return
        seen = _read("seen.json")
        used = seen.get("devices", {}) | ({device_id: now} if in_use else {})
        read = seen.get("chats", {})
        if chat:
            read = {key: at for key, at in read.items() if key != chat} | {chat: now}
        _write("seen.json", {"devices": used, "chats": dict(list(read.items())[-TOLD_LIMIT:])})


def first_to_hear(device_ids: list[str]) -> list[str]:
    """Of these devices, the ones a notification goes to straight away: those you're using, or else
    the one you used last. The others hear later, if you haven't read it by then. With no device
    ever seen in use, as with apps from before this, all of them hear at once."""
    used = _read("seen.json").get("devices", {})
    known = {key: used[key] for key in device_ids if isinstance(used.get(key), (int, float))}
    if not known:
        return list(device_ids)
    now = time.time()
    in_use = [key for key, at in known.items() if now - at < PRESENCE_LIFETIME]
    return in_use or [max(known, key=known.get)]


def read_since(chat: str, since: float) -> bool:
    """Whether you've had this chat open on any device since then."""
    at = _read("seen.json").get("chats", {}).get(chat)
    return isinstance(at, (int, float)) and at >= since


def is_open(chat: str) -> bool:
    """Whether you're reading this chat on any device: then none of them hears about it."""
    now = time.time()
    return any(
        entry.get("chat") == chat and now - entry.get("at", 0) < PRESENCE_LIFETIME
        for entry in _presence().values()
    )


@contextmanager
def _shared(name: str = "told"):
    """For a file both the gateway and the dashboard write: `told.json`, which the gateway writes as
    it notifies and the dashboard as you read, and `chats.json`."""
    with _lock:
        if fcntl is None:
            yield
            return
        root = _root()
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with open(root / f".{name}.lock", "a") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            yield


def note_told(device_ids: list[str], chat: str) -> None:
    """These devices now show a notification about this chat. The push carried this chat's clear
    first, so none is owed for it any more: a later one would take down this notification."""
    if not device_ids:
        return
    with _shared():
        told = _read("told.json")
        for device_id in device_ids:
            chats = [known for known in told.get(device_id, []) if known != chat] + [chat]
            told[device_id] = chats[-TOLD_LIMIT:]
        _write("told.json", told)
        _drop_cleared(device_ids, [chat])


def take_told(chat: str, reader: str) -> list[str]:
    """You're reading `chat` on `reader`: the other devices that still show a notification about it.

    Forgets them, so each is cleared once, and `reader`'s own, which it clears itself. Each of the
    others is also owed the clear in its next notification (`owed_clears`), as iOS can drop the
    silent push.
    """
    with _shared():
        _drop_cleared([reader], [chat])
        told = _read("told.json")
        showing = [device_id for device_id, chats in told.items() if chat in chats]
        if not showing:
            return []
        for device_id in showing:
            told[device_id] = [known for known in told[device_id] if known != chat]
            if not told[device_id]:
                del told[device_id]
        _write("told.json", told)
        others = [device_id for device_id in showing if device_id != reader]
        cleared = _read("cleared.json")
        for device_id in others:
            chats = [known for known in cleared.get(device_id, []) if known != chat] + [chat]
            cleared[device_id] = chats[-TOLD_LIMIT:]
        if others:
            _write("cleared.json", cleared)
    return others


def owed_clears(device_id: str) -> list[str]:
    """Chats read elsewhere since this device was last notified, newest first. Its next
    notification carries them, so its extension takes those down even when the app can't run."""
    with _shared():
        return list(reversed(_read("cleared.json").get(device_id, [])))


def paid_clears(device_id: str, chats: list[str]) -> None:
    """A notification carrying these clears reached the relay."""
    with _shared():
        _drop_cleared([device_id], chats)


def _drop_cleared(device_ids: list[str], chats: list[str]) -> None:
    """Under `_shared()`."""
    cleared = _read("cleared.json")
    changed = False
    for device_id in device_ids:
        kept = [known for known in cleared.get(device_id, []) if known not in chats]
        if kept != cleared.get(device_id, []):
            changed = True
            if kept:
                cleared[device_id] = kept
            else:
                del cleared[device_id]
    if changed:
        _write("cleared.json", cleared)


def _fresh_chats(now: float) -> dict[str, float]:
    return {
        key: used
        for key, used in _read("chats.json").items()
        if isinstance(used, (int, float)) and now - used < CHAT_LIFETIME
    }


def note_chat(session_id: str) -> None:
    """The app opened this chat: its turns get the chat context."""
    now = time.time()
    with _shared("chats"):
        _write("chats.json", _fresh_chats(now) | {session_id: now})


def is_app_chat(session_id: str, parent_session_id: str = "") -> bool:
    """Whether the app opened this chat, or the one it continues: compression can move a chat to a
    new session, whose parent is the old one. Each use keeps it from being forgotten."""
    if not session_id:
        return False
    now = time.time()
    chats = _fresh_chats(now)
    used = chats.get(session_id)
    if used is None and not (parent_session_id and parent_session_id in chats):
        return False
    if used is None or now - used > _CHAT_REFRESH:
        with _shared("chats"):
            _write("chats.json", _fresh_chats(now) | {session_id: now})
    return True
