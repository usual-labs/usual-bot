"""One function per push service. Each sends a notification and raises if the service refuses."""

from __future__ import annotations

import json
import urllib.parse
import urllib.request

_TIMEOUT = 15


def _post(request: urllib.request.Request) -> None:
    with urllib.request.urlopen(request, timeout=_TIMEOUT):
        pass


def ntfy(settings: dict, title: str, body: str, link: str | None, urgent: bool) -> None:
    # JSON rather than headers, which can't carry names and text outside ASCII.
    message = {"topic": settings["topic"], "title": title, "message": body, "priority": 4 if urgent else 3}
    if link:
        message["click"] = link
    headers = {"Content-Type": "application/json"}
    if settings.get("ntfy_token"):
        headers["Authorization"] = f"Bearer {settings['ntfy_token']}"
    server = settings.get("server", "").rstrip("/") or "https://ntfy.sh"
    _post(urllib.request.Request(server, data=json.dumps(message).encode(), headers=headers, method="POST"))


def pushover(settings: dict, title: str, body: str, link: str | None, urgent: bool) -> None:
    fields = {
        "token": settings["token"],
        "user": settings["user_key"],
        "title": title,
        "message": body,
        "priority": 1 if urgent else 0,
    }
    if link:
        fields |= {"url": link, "url_title": "Open in Usual Bot"}
    url = settings.get("pushover_url", "https://api.pushover.net/1/messages.json")
    _post(urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(), method="POST"))


SERVICES = {"ntfy": ntfy, "pushover": pushover}


def is_ready(settings: dict) -> bool:
    match settings.get("service"):
        case "ntfy":
            return bool(settings.get("topic"))
        case "pushover":
            return bool(settings.get("token") and settings.get("user_key"))
    return False


def send(settings: dict, title: str, body: str, link: str | None = None, urgent: bool = False) -> None:
    SERVICES[settings["service"]](settings, title, body, link, urgent)
