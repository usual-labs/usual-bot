"""A live view of a Bot's headless browser, for Usual Bot.

The Bot's real-profile Chrome (``browser.use_real_profile``) runs headless on the gateway host and
listens for DevTools on a random loopback port. ``/feed`` attaches to it, asks Chrome for a
screencast and forwards each frame to the viewer, so the browser can be watched from any device
signed in to the gateway, without a window on the host. A background tab is nudged to paint (``nudge``).

``GET /status?bot=<profile>`` says whether the Bot has a browser to watch; ``WS /feed`` shows it.

Query: ``bot=<profile>`` and ``ticket=<from POST /api/auth/ws-ticket>``, plus optional
``format=jpeg|png`` (default jpeg) and ``quality=1..100`` (jpeg only, default 90).

Socket messages, server to viewer:
  binary            one frame, JPEG or PNG (only the newest is sent when the viewer falls behind)
  {"type": "state", "state": "waiting" | "live"}   waiting: the Bot has no browser running
  {"type": "tab", "url": ..., "title": ...}        the tab being shown

Watch only for now: nothing the viewer sends reaches the browser.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import itertools
import json
import logging
import re
from pathlib import Path

import aiohttp
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

log = logging.getLogger(__name__)
router = APIRouter()

_BOT = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
_WAIT_S = 2.0  # how often to look for a browser while there is none
_MAX_SIDE = 4096  # Chrome scales frames down only past this; the page's own size is what you get
_NUDGE_S = 0.5  # how often to make a background tab paint
_QUIET_S = 1.0  # a newly shown tab that sends no frame in this long isn't painting


def _screencast(params) -> dict:
    """Screencast settings from the viewer's query: ``format=jpeg|png`` (default jpeg) and
    ``quality=1..100`` for jpeg (default 90). Frames are the page's full size, never scaled down."""
    fmt = "png" if params.get("format") == "png" else "jpeg"
    settings = {"format": fmt, "maxWidth": _MAX_SIDE, "maxHeight": _MAX_SIDE, "everyNthFrame": 1}
    if fmt == "jpeg":
        try:
            settings["quality"] = min(100, max(1, int(params.get("quality", 90))))
        except ValueError:
            settings["quality"] = 90
    return settings


# ── Finding the Bot's browser ────────────────────────────────────────────────────────────────────


def _bot_home(bot: str) -> Path | None:
    """The Bot's profile home, or None for a name that isn't a profile."""
    if not _BOT.match(bot):
        return None
    from hermes_constants import get_default_hermes_root

    root = Path(get_default_hermes_root())
    home = root if bot == "default" else root / "profiles" / bot
    return home if home.is_dir() else None


def _candidates(home: Path) -> list[tuple[int, str]]:
    """(port, browser path) from each real-profile copy's DevToolsActivePort, newest first."""
    found = []
    for marker in (home / "browser-profile").glob("*/DevToolsActivePort"):
        try:
            lines = marker.read_text().split()
            found.append((marker.stat().st_mtime, int(lines[0]), lines[1]))
        except (OSError, ValueError, IndexError):
            continue
    return [(port, path) for _, port, path in sorted(found, reverse=True)]


async def _browser_url(http: aiohttp.ClientSession, home: Path) -> str | None:
    """The DevTools URL of the Bot's running browser, or None when none is running.

    The marker file outlives the browser, and its port can be reused by another process, so the
    answer must name the same browser the marker does."""
    for port, path in _candidates(home):
        try:
            async with http.get(f"http://127.0.0.1:{port}/json/version",
                                timeout=aiohttp.ClientTimeout(total=1.5)) as response:
                url = (await response.json()).get("webSocketDebuggerUrl", "")
        except (aiohttp.ClientError, asyncio.TimeoutError, ValueError, OSError, RuntimeError):
            # RuntimeError: asyncio refusing a socket number the kernel just reused, seen while the
            # browser was restarting. Same meaning as a refused connection: not this one.
            continue
        if url.endswith(path):
            return url
    return None


def _shown(target: dict) -> bool:
    return target.get("type") == "page" and not target.get("url", "").startswith(("devtools://", "chrome-extension://"))


# ── Auth ─────────────────────────────────────────────────────────────────────────────────────────


def _authorized(ws: WebSocket) -> bool:
    """The dashboard's own WebSocket credential check (``?ticket=`` from ``POST /api/auth/ws-ticket``,
    or ``?token=``). Plugin sockets must check their own credential; this keeps it identical to core."""
    try:
        from hermes_cli import web_server_chat
    except Exception:  # noqa: BLE001 - no dashboard, no way to check: refuse
        log.warning("usual-browser: dashboard auth unavailable; refusing the socket")
        return False
    return bool(web_server_chat._ws_auth_ok(ws))


# ── One viewer ───────────────────────────────────────────────────────────────────────────────────


class _Viewer:
    def __init__(self, ws: WebSocket, home: Path) -> None:
        self.ws = ws
        self.home = home
        self.screencast = _screencast(ws.query_params)
        self.gone = asyncio.Event()  # the viewer disconnected
        self.messages: asyncio.Queue[str] = asyncio.Queue()
        self.frame: bytes | None = None
        self.sent: bytes | None = None  # the last picture sent, to skip sending it again
        self.wake = asyncio.Event()  # something is ready to send

    # Sending: one task writes to the socket, text first, then the newest frame.

    def say(self, **message) -> None:
        if message.get("type") == "state":
            self.sent = None  # the viewer drops its picture on "waiting": the next one must go
        self.messages.put_nowait(json.dumps(message))
        self.wake.set()

    def show(self, jpeg: bytes) -> None:
        # A background tab, nudged to paint, sends the same picture again while nothing changes.
        if jpeg == self.sent:
            return
        self.sent = jpeg
        self.frame = jpeg
        self.wake.set()

    async def _send_loop(self) -> None:
        while True:
            await self.wake.wait()
            self.wake.clear()
            while not self.messages.empty():
                await self.ws.send_text(self.messages.get_nowait())
            if self.frame is not None:
                frame, self.frame = self.frame, None
                await self.ws.send_bytes(frame)

    async def _receive_loop(self) -> None:
        with contextlib.suppress(WebSocketDisconnect):
            while True:
                await self.ws.receive_text()  # watch only: input is ignored for now

    async def run(self) -> None:
        tasks = [asyncio.create_task(self._send_loop()), asyncio.create_task(self._receive_loop())]
        for task in tasks:
            task.add_done_callback(lambda _: self.gone.set())
        try:
            async with aiohttp.ClientSession() as http:
                state = None
                while not self.gone.is_set():
                    url = await _browser_url(http, self.home)
                    if url is None:
                        if state != "waiting":
                            state = "waiting"
                            self.say(type="state", state=state)
                        with contextlib.suppress(asyncio.TimeoutError):
                            await asyncio.wait_for(self.gone.wait(), _WAIT_S)
                        continue
                    state = "live"
                    self.say(type="state", state=state)
                    try:
                        await self._watch(http, url)
                    except Exception as exc:  # noqa: BLE001 - the browser went away mid-watch: look again
                        log.info("usual-browser: lost the browser: %r", exc)
                        with contextlib.suppress(asyncio.TimeoutError):
                            await asyncio.wait_for(self.gone.wait(), _WAIT_S)
        finally:
            for task in tasks:
                task.cancel()

    # Watching one browser until it closes or the viewer leaves.

    async def _watch(self, http: aiohttp.ClientSession, url: str) -> None:
        async with http.ws_connect(url, max_msg_size=0, heartbeat=None) as cdp:
            ids = itertools.count(1)
            pending: dict[int, asyncio.Future] = {}
            pages: dict[str, dict] = {}  # targetId -> targetInfo, in the order they appeared
            # painted: when the shown tab last sent a frame; hidden: Chrome says it stopped painting.
            current: dict = {"target": None, "session": None, "shown": 0.0, "painted": 0.0, "hidden": False}
            loop = asyncio.get_running_loop()

            async def call(method: str, params: dict | None = None, session: str | None = None) -> dict:
                message = {"id": next(ids), "method": method, "params": params or {}}
                if session:
                    message["sessionId"] = session
                future = asyncio.get_running_loop().create_future()
                pending[message["id"]] = future
                await cdp.send_str(json.dumps(message))
                return await asyncio.wait_for(future, 10)

            async def show(target_id: str | None) -> None:
                old = current["session"]
                current.update(target=None, session=None)
                if old:
                    with contextlib.suppress(Exception):
                        await call("Target.detachFromTarget", {"sessionId": old})
                if target_id is None:
                    self.say(type="tab", url=None, title=None)
                    return
                attached = await call("Target.attachToTarget", {"targetId": target_id, "flatten": True})
                session = attached["sessionId"]
                current.update(target=target_id, session=session, shown=loop.time(), painted=0.0, hidden=False)
                info = pages.get(target_id, {})
                self.say(type="tab", url=info.get("url"), title=info.get("title"))
                await call("Page.enable", session=session)
                await call("Page.startScreencast", self.screencast, session=session)

            def newest() -> str | None:
                return next(reversed(pages), None)

            async def events() -> None:
                async for raw in cdp:
                    if raw.type != aiohttp.WSMsgType.TEXT:
                        break
                    message = json.loads(raw.data)
                    if "id" in message:
                        future = pending.pop(message["id"], None)
                        if future and not future.done():
                            if "error" in message:
                                future.set_exception(RuntimeError(message["error"].get("message", "CDP error")))
                            else:
                                future.set_result(message.get("result", {}))
                        continue
                    method, params = message.get("method"), message.get("params", {})
                    if method == "Page.screencastFrame" and message.get("sessionId") == current["session"]:
                        current.update(painted=loop.time(), hidden=False)
                        self.show(base64.b64decode(params["data"]))
                        asyncio.create_task(call("Page.screencastFrameAck",
                                                 {"sessionId": params["sessionId"]}, session=current["session"]))
                    elif method == "Page.screencastVisibilityChanged" and message.get("sessionId") == current["session"]:
                        current["hidden"] = not params.get("visible", True)
                    elif method == "Target.targetCreated" and _shown(params["targetInfo"]):
                        # The Bot opened a tab: follow it.
                        info = params["targetInfo"]
                        pages[info["targetId"]] = info
                        asyncio.create_task(show(info["targetId"]))
                    elif method == "Target.targetInfoChanged":
                        info = params["targetInfo"]
                        if info["targetId"] in pages:
                            pages[info["targetId"]] = info
                            if info["targetId"] == current["target"]:
                                self.say(type="tab", url=info.get("url"), title=info.get("title"))
                    elif method == "Target.targetDestroyed":
                        pages.pop(params["targetId"], None)
                        if params["targetId"] == current["target"]:
                            asyncio.create_task(show(newest()))

            async def nudge() -> None:
                """The Bot can work in a tab it never brings to the front, such as one it opened in the
                background. Chrome doesn't paint those, so their screencast sends nothing. A screenshot
                paints the tab for a moment without bringing it forward, and the screencast sends that
                picture; the screenshot itself is thrown away, at the lowest quality to keep it cheap.
                Chrome doesn't report a background tab's new title either, so it's asked for."""
                while True:
                    await asyncio.sleep(_NUDGE_S)
                    session, target = current["session"], current["target"]
                    silent = current["painted"] < current["shown"] and loop.time() - current["shown"] > _QUIET_S
                    if not session or not (current["hidden"] or silent):
                        continue
                    with contextlib.suppress(Exception):  # the tab closed or was switched meanwhile
                        await call("Page.captureScreenshot", {"format": "jpeg", "quality": 1}, session=session)
                        info = (await call("Target.getTargetInfo", {"targetId": target})).get("targetInfo", {})
                        old = pages.get(target, {})
                        if target == current["target"] and (info.get("url"), info.get("title")) != (
                                old.get("url"), old.get("title")):
                            pages[target] = info
                            self.say(type="tab", url=info.get("url"), title=info.get("title"))

            reader = asyncio.create_task(events())
            nudger = asyncio.create_task(nudge())
            try:
                found = await call("Target.getTargets")
                for info in found.get("targetInfos", []):
                    if _shown(info):
                        pages[info["targetId"]] = info
                await call("Target.setDiscoverTargets", {"discover": True})
                # Start on a tab someone (the Bot) is attached to, else the newest.
                attached = [t for t, info in pages.items() if info.get("attached")]
                await show(attached[-1] if attached else newest())
                gone = asyncio.create_task(self.gone.wait())
                await asyncio.wait({reader, gone}, return_when=asyncio.FIRST_COMPLETED)
                gone.cancel()
                if current["session"] and not cdp.closed:
                    with contextlib.suppress(Exception):
                        await call("Page.stopScreencast", session=current["session"])
            finally:
                reader.cancel()
                nudger.cancel()
                for future in pending.values():
                    future.cancel()


# ── Routes ───────────────────────────────────────────────────────────────────────────────────────


def _watchable(home: Path) -> bool:
    """The Bot browses with a real profile, headless: the browser this feed can show."""
    try:
        from hermes_cli.config import read_user_config_raw

        browser = read_user_config_raw(home / "config.yaml").get("browser") or {}
    except Exception:  # noqa: BLE001 - an unreadable config means nothing to show
        return False
    if not isinstance(browser, dict):
        return False

    def on(key: str) -> bool:
        value = browser.get(key)
        return value is True or str(value).strip().lower() in {"1", "true", "yes", "on"}

    return on("use_real_profile") and not on("headed")


@router.get("/status")
async def status(bot: str) -> dict:
    """Behind the dashboard's normal sign-in. ``available``: the Bot browses with a real profile,
    headless, so there's a browser to watch when it's open. ``browser``: it's open now."""
    home = _bot_home(bot)
    if home is None:
        raise HTTPException(status_code=404, detail="no such Bot")
    async with aiohttp.ClientSession() as http:
        running = await _browser_url(http, home) is not None
    return {"bot": bot, "available": _watchable(home), "browser": running}


@router.websocket("/feed")
async def feed(ws: WebSocket) -> None:
    if not _authorized(ws):
        await ws.close(code=4401)
        return
    home = _bot_home(ws.query_params.get("bot", ""))
    if home is None:
        await ws.close(code=4404)
        return
    await ws.accept()
    try:
        await _Viewer(ws, home).run()
    finally:
        with contextlib.suppress(Exception):
            await ws.close()
