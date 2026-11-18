"""The routes Usual Bot calls: its devices, the chats it opened, and a Bot's browser
(``browser_api.py``). The dashboard's own sign-in guards them all."""

from __future__ import annotations

import base64
import importlib.util
import logging
import re
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel


def _load(name: str, path: Path, package: Path | None = None):
    # By path: the dashboard imports this file on its own, outside the plugin's package.
    spec = importlib.util.spec_from_file_location(
        name, path, submodule_search_locations=[str(package)] if package else None
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


_here = Path(__file__).resolve().parent
plugin = _load("usual_bot_plugin", _here.parent / "__init__.py", _here.parent)
store = plugin.store
router = APIRouter()
try:
    router.include_router(_load("usual_bot_browser_api", _here / "browser_api.py").router)
except ImportError as error:  # No aiohttp: everything but the browser view still works.
    logging.getLogger(__name__).warning("usual-bot: no browser view: %s", error)

# What Hermes names sessions with, and no more: the ID becomes a key in a file.
_SESSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


class Device(BaseModel):
    """What a device says about itself. Left out, a field stays as it was."""

    relay: str | None = None
    name: str | None = None
    platform: str | None = None
    send_key: str | None = None
    seal_key: str | None = None
    message: bool | None = None
    needs_you: bool | None = None
    previews: bool | None = None
    sound: bool | None = None
    muted: list[str] | None = None
    # Which of the device's gateways this is: its own ID for it, sealed into each notification.
    gateway: str | None = None


class Presence(BaseModel):
    device: str
    # The chat in front of you on that device, or none.
    chat: str | None = None
    names: dict[str, str] | None = None


class Test(BaseModel):
    device: str


@router.get("/settings")
def read_settings() -> dict:
    return {
        "version": plugin.VERSION,
        "devices": [store.public(key, value) for key, value in store.devices().items()],
    }


@router.put("/devices/{device_id}")
def put_device(device_id: str, new: Device) -> dict:
    changes = new.model_dump(exclude_none=True)
    known = store.devices().get(device_id)
    if known is None and not all(changes.get(key) for key in ("relay", "send_key", "seal_key")):
        raise HTTPException(status_code=400, detail="A new device needs its relay and both keys.")
    if "relay" in changes and not changes["relay"].startswith("https://"):
        raise HTTPException(status_code=400, detail="The push relay needs an address starting with https://.")
    if "seal_key" in changes:
        try:
            if len(base64.b64decode(changes["seal_key"], validate=True)) != 32:
                raise ValueError
        except ValueError:
            raise HTTPException(status_code=400, detail="That seal key isn't 32 bytes of base64.") from None
    return store.public(device_id, store.put_device(device_id, changes))


@router.delete("/devices/{device_id}")
def delete_device(device_id: str) -> dict:
    store.remove_device(device_id)
    store.set_open(device_id, None)
    return {"ok": True}


@router.put("/presence")
def presence(new: Presence) -> dict:
    store.set_open(new.device, new.chat)
    if new.chat:
        plugin.push.read_on(new.device, new.chat)
    if new.names is not None:
        store.set_names(new.names)
    return {"ok": True}


@router.post("/test")
def test(new: Test) -> dict:
    fate = plugin.push.send_test(new.device)
    if fate == "gone":
        raise HTTPException(status_code=404, detail="Your gateway doesn’t know this device. Open Usual Bot again.")
    if fate != "sent":
        raise HTTPException(status_code=502, detail="The push relay couldn’t deliver it. Try again in a moment.")
    return {"ok": True}


@router.put("/chats/{session_id}")
def put_chat(session_id: str) -> dict:
    """The app opened this chat, so its Bot is told it's talking through Usual Bot."""
    if not _SESSION.match(session_id):
        raise HTTPException(status_code=400, detail="That isn't a chat's session ID.")
    store.note_chat(session_id)
    return {"ok": True}
