"""Seals a notification for each device and hands it to Usual's push relay.

Each device made its own seal key and gave it only to this gateway, so the relay and Apple carry
text they can't read. The app's notification extension opens it on the device.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import urllib.request

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

logger = logging.getLogger(__name__)
_TIMEOUT = 15
_BATCH = 20  # The relay takes this many pushes at once.


def seal(seal_key: str, payload: dict) -> str:
    """AES-GCM, as nonce, then ciphertext and tag: what CryptoKit's `SealedBox(combined:)` reads."""
    nonce = os.urandom(12)
    sealed = AESGCM(base64.b64decode(seal_key)).encrypt(nonce, json.dumps(payload).encode(), None)
    return base64.b64encode(nonce + sealed).decode()


def thread(seal_key: str, chat: str) -> str:
    """Groups a chat's notifications without telling Apple which chat it is."""
    return hmac.new(base64.b64decode(seal_key), chat.encode(), hashlib.sha256).hexdigest()[:32]


def push(device_id: str, device: dict, kind: str, payload: dict, chat: str | None) -> dict:
    entry = {"device": device_id, "key": device["send_key"], "kind": kind, "sealed": seal(device["seal_key"], payload)}
    if chat:
        entry["thread"] = thread(device["seal_key"], chat)
    return entry


def clear(device_id: str, device: dict, chat: str) -> dict:
    """A silent push that takes down what the device shows about a chat. `kind` is sealed too, so
    no one can pass a message's sealed text off as one of these."""
    payload = {"kind": "read", "chat": chat}
    return {"device": device_id, "key": device["send_key"], "sealed": seal(device["seal_key"], payload)}


def send(pushes: list[tuple[str, dict]], route: str = "send") -> dict[str, str]:
    """Sends `(relay, push)` pairs and answers each device's fate: `gone` means forget that device.

    `route` is the relay's `send`, for notifications, or `clear`, for silent pushes."""
    by_relay: dict[str, list[dict]] = {}
    for relay, entry in pushes:
        by_relay.setdefault(relay.rstrip("/"), []).append(entry)
    fates: dict[str, str] = {}
    for relay, entries in by_relay.items():
        for start in range(0, len(entries), _BATCH):
            batch = entries[start : start + _BATCH]
            try:
                results = _post(f"{relay}/v1/{route}", {"pushes": batch})["results"]
            except Exception as error:  # Named only: an error can quote the request.
                logger.warning("usual-push: couldn't reach the relay: %s", type(error).__name__)
                fates |= {entry["device"]: "failed" for entry in batch}
                continue
            for result in results:
                fates[result["device"]] = result["status"]
                if result["status"] not in ("sent", "gone"):
                    logger.warning("usual-push: the relay said %s: %s", result["status"], result.get("reason"))
    return fates


def _post(url: str, body: dict) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "usual-push"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=_TIMEOUT) as response:
        return json.loads(response.read())
