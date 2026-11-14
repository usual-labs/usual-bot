"""Usual Bot's devices for this plugin. The dashboard's own sign-in guards these routes."""

from __future__ import annotations

import base64
import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel


def _load_plugin():
    # By path: the dashboard imports this file on its own, outside the plugin's package.
    root = Path(__file__).resolve().parent.parent
    spec = importlib.util.spec_from_file_location(
        "usual_push_plugin", root / "__init__.py", submodule_search_locations=[str(root)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()
store = plugin.store
router = APIRouter()


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
        plugin.read_on(new.device, new.chat)
    if new.names is not None:
        store.set_names(new.names)
    return {"ok": True}


@router.post("/test")
def test(new: Test) -> dict:
    fate = plugin.send_test(new.device)
    if fate == "gone":
        raise HTTPException(status_code=404, detail="Your gateway doesn’t know this device. Open Usual Bot again.")
    if fate != "sent":
        raise HTTPException(status_code=502, detail="The push relay couldn’t deliver it. Try again in a moment.")
    return {"ok": True}
