"""Push: tells your devices what agents do, through Usual's push relay, even when Usual Bot isn't running.

Hooks only watch: anything going wrong here is logged and never touches an agent's turn.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from collections import OrderedDict
from pathlib import Path

from . import relay, store
from .plain import plain
from .turns import asked_by_bot, asked_hidden, said

logger = logging.getLogger(__name__)

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
# The relay refuses a sealed text over 3000 characters: 2222 bytes of JSON once its base64, nonce
# and tag are taken off. Less the gateway's tag, which `relay` adds.
_READ_ROOM = 2100
# Turns whose words reach your devices, by Hermes's turn ID, as `pre_llm_call` saw them start: what
# a Bot says mid-turn arrives without the turn's history, so this is the only place to tell.
_LOUD_TURNS: OrderedDict[str, None] = OrderedDict()
_LOUD_TURNS_LIMIT = 256
_LOUD_TURNS_LOCK = threading.Lock()
# How long your other devices wait after the one you're using, or used last, hears. Long enough to
# read it there first, as Telegram does; short enough that a phone in your pocket still buzzes.
LATER = 15
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


def deliver(
    kind: str, title: str, preview: str, chat: str, speaker: str | None = None, interim: bool = False
) -> None:
    """To the device you're using, or else the one you used last, and `LATER` seconds after to
    every other device that wants it, unless you've read that chat by then. Nothing goes while
    you're reading that chat on any device. `interim` is what a Bot says before its reply, which
    the app doesn't count as unread on its own.

    Blocks for `LATER` when some devices wait: call it on a thread of its own."""
    if store.is_open(chat):
        return
    since = time.time()
    settings = store.settings()
    names = settings["names"]
    if speaker:
        preview = f"{names.get(speaker, speaker)}: {preview}"
    title = title.format(name=names.get(chat, chat))
    wanting = [
        device_id
        for device_id, device in settings["devices"].items()
        if device.get(kind, True) and chat not in device.get("muted", [])
    ]
    first = store.first_to_hear(wanting)
    _send(first, kind, title, preview, chat, interim)
    rest = [device_id for device_id in wanting if device_id not in first]
    if not rest:
        return
    time.sleep(LATER)
    if not (store.is_open(chat) or store.read_since(chat, since)):
        _send(rest, kind, title, preview, chat, interim)


def _send(device_ids: list[str], kind: str, title: str, preview: str, chat: str, interim: bool) -> None:
    # Read again: a device may have gone, or had clears owed, while the others waited.
    devices = store.devices()
    pushes = []
    carried: dict[str, list[str]] = {}
    for device_id in device_ids:
        if (device := devices.get(device_id)) is None:
            continue
        body = _shorten(preview) if device.get("previews", True) else _HIDDEN[kind]
        payload = {"title": title, "body": body, "chat": chat, "kind": kind, "sound": device.get("sound", True)}
        if interim:
            payload["interim"] = True
        if read := _fitting(payload, chat, store.owed_clears(device_id)):
            payload["read"] = carried[device_id] = read
        pushes.append((device["relay"], relay.push(device_id, device, kind, payload, chat)))
    if not pushes:
        return
    fates = relay.send(pushes)
    _forget_gone(fates)
    sent = [device_id for device_id, fate in fates.items() if fate == "sent"]
    for device_id in sent:
        if device_id in carried:
            store.paid_clears(device_id, carried[device_id])
    store.note_told(sent, chat)


def _fitting(payload: dict, chat: str, owed: list[str]) -> list[str]:
    """The owed clears that fit beside the notification, this chat's first, so the read ones about
    it go before the new one shows. The rest wait for the next notification."""
    owed = sorted(owed, key=lambda known: known != chat)
    room = _READ_ROOM - len(json.dumps(payload))
    read: list[str] = []
    for known in owed:
        room -= len(json.dumps(known)) + 2
        if room < 0:
            break
        read.append(known)
    return read


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


def _push_unless_hidden(kind: str, title: str, preview: str, chat: str, interim: bool = False) -> None:
    """A Bot's own chat. A hidden Bot still speaks up in rooms, which aren't hidden."""
    home = _home()

    def deliver_unless_hidden() -> None:
        if not _is_hidden(home):
            deliver(kind, title, preview, chat, interim=interim)

    threading.Thread(target=_safely, args=(deliver_unless_hidden,), daemon=True).start()


def _safely(action, *args) -> None:
    try:
        action(*args)
    except Exception as error:  # Named only: an error can quote the message.
        logger.warning("usual-bot: couldn't notify: %s", type(error).__name__)


def _deliver_room_reply(profile: str, text: str, interim: bool) -> None:
    """The reply's hook doesn't say which room, but that member's activity just did."""
    time.sleep(_ROOM_ACTIVITY_DELAY)
    if room := store.room_of(profile):
        deliver("message", "{name}", text, f"room:{room}", speaker=profile, interim=interim)


def _is_loud(platform: str, conversation_history) -> bool:
    return platform in _CHAT_PLATFORMS | {_ROOM_PLATFORM} and not (
        asked_hidden(conversation_history) or asked_by_bot(conversation_history)
    )


def on_turn_start(turn_id="", platform="", conversation_history=None, **_) -> None:
    """Remembers whether what the Bot says on the way to its reply should notify too."""
    if not turn_id or not _is_loud(platform, conversation_history):
        return
    with _LOUD_TURNS_LOCK:
        _LOUD_TURNS[turn_id] = None
        while len(_LOUD_TURNS) > _LOUD_TURNS_LIMIT:
            _LOUD_TURNS.popitem(last=False)


def on_interim(text="", surface="", turn_id="", **_) -> None:
    """What a Bot says before it's done, such as "On it, looking now". A turn `pre_llm_call` didn't
    see start, like a side question's fork, stays quiet."""
    with _LOUD_TURNS_LOCK:
        loud = bool(turn_id) and turn_id in _LOUD_TURNS
    if loud:
        _notify(text, surface, interim=True)


def on_reply(assistant_response="", platform="", conversation_history=None, **_) -> None:
    if _is_loud(platform, conversation_history):
        _notify(assistant_response, platform)


def _notify(response, platform: str, interim: bool = False) -> None:
    # A Bot that chose not to reply (`[SILENT]`, often a routine or a finished process) has no news.
    words = said(response)
    if not isinstance(words, str) or not words.strip():
        return
    text = plain(words)
    if platform in _CHAT_PLATFORMS:
        _push_unless_hidden("message", "{name}", text, _profile(), interim)
    elif platform == _ROOM_PLATFORM:
        threading.Thread(target=_safely, args=(_deliver_room_reply, _profile(), text, interim), daemon=True).start()


def _surface() -> str:
    """The app a gateway chat's turn runs for: ``tui``, ``desktop``, ``cli`` or ``acp``."""
    try:
        from hermes_cli.plugin_session import session_surface

        return session_surface()
    except Exception:  # A Hermes without it: notify, as for any chat.
        return "tui"


def on_request(kind="", platform="", prompt="", **_) -> None:
    if platform == _GATEWAY_PLATFORM:
        platform = _surface()
    if platform not in _CHAT_PLATFORMS:
        return
    asks = {"approval": f"Wants to run “{prompt}”", "sudo": "Asks for the sudo password", "secret": "Asks for a secret"}.get(kind) or plain(prompt)
    _push_unless_hidden("needs_you", "{name} needs you", asks, _profile())


def on_room_activity(room_id="", member_id="", kind="", payload=None, **_) -> None:
    store.note_room(member_id, room_id)
    if kind == "request.opened":
        command = (payload or {}).get("command") or "a command"
        _push("needs_you", "{name} needs you", f"{member_id} wants to run “{command}”", f"room:{room_id}")
