"""Usual Bot's settings for this plugin. The dashboard's own sign-in guards these routes."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel


def _load(name: str):
    # By path: the dashboard imports this file on its own, outside the plugin's package.
    path = Path(__file__).resolve().parent.parent / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"usual_push_{name}", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


store = _load("store")
services = _load("services")
router = APIRouter()
# Names no chat, so it just opens the app.
TEST_LINK = "usualbot://open"


class Settings(BaseModel):
    service: str
    server: str = "https://ntfy.sh"
    topic: str = ""
    message: bool = True
    needs_you: bool = True
    previews: bool = True
    # Left out, a saved secret stays. An empty string removes it.
    ntfy_token: str | None = None
    token: str | None = None
    user_key: str | None = None


class Presence(BaseModel):
    focused: bool = False
    names: dict[str, str] | None = None


@router.get("/settings")
def read_settings() -> dict:
    return store.public(store.settings())


@router.put("/settings")
def write_settings(new: Settings) -> dict:
    if new.service != "off" and new.service not in services.SERVICES:
        raise HTTPException(status_code=400, detail="Usual Bot doesn't know that push service.")
    if not new.server.startswith(("https://", "http://")):
        raise HTTPException(status_code=400, detail="The ntfy server needs an address starting with https://.")
    changes = new.model_dump(exclude_none=True)
    return store.public(store.update(changes))


@router.put("/presence")
def presence(new: Presence) -> dict:
    store.set_focused(new.focused)
    if new.names is not None:
        store.update({"names": new.names})
    return {"ok": True}


@router.post("/test")
def test() -> dict:
    settings = store.settings()
    if not services.is_ready(settings):
        raise HTTPException(status_code=400, detail="Finish setting up a push service first.")
    try:
        services.send(settings, "Usual Bot", "Notifications from your gateway are working.", TEST_LINK)
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"The service refused it: {type(error).__name__}") from error
    return {"ok": True}
