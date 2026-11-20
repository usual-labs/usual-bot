"""A shell on the gateway host for Usual Bot's terminal drawer.

The shell runs as the gateway's user, in the folder the Bot runs its commands in, with
``HERMES_HOME`` set to the Bot's profile. Only for a Bot whose commands run on this host
(``terminal.backend: local``, Hermes's default): a sandboxed Bot's commands run somewhere a shell
here can't reach, so it gets none rather than a misleading one.

``GET /terminal/status?bot=<profile>`` says whether the Bot has a shell to open; ``WS /terminal``
opens one. Query: ``bot=<profile>``, ``ticket=<from POST /api/auth/ws-ticket>``, and optional
``cols`` and ``rows``.

Every socket message is binary and starts with a tag byte:
  0 + bytes   server to app: what the shell printed; app to server: what you typed
  1 + JSON    server to app: {"type": "ready", "user", "host", "cwd"} once it starts,
              {"type": "exit", "code": N} when it ends; app to server: {"type": "resize", "cols", "rows"}

Closing the socket hangs up the shell (SIGHUP to its process group), as closing a terminal window
does. Close codes: 4401 not signed in, 4404 no such Bot, 4409 the Bot's commands run in a sandbox.
"""

from __future__ import annotations

import asyncio
import contextlib
import fcntl
import json
import logging
import os
import pty
import pwd
import re
import signal
import socket
import struct
import termios
from pathlib import Path

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

log = logging.getLogger(__name__)
router = APIRouter()

_BOT = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
_OUTPUT, _CONTROL = 0, 1
_READ = 65536
# What Hermes reads as "the folder the gateway runs in" (``_terminal_config_value_is_bridgeable``).
_HERE = {"", ".", "auto", "cwd"}
# Kept from the gateway's environment; the rest (its keys and tokens) stays out of your shell,
# whose login profile sets up the usual.
_KEEP = ("PATH", "LANG", "LC_ALL", "LC_CTYPE", "TZ")


def _bot_home(bot: str) -> Path | None:
    """The Bot's profile home, or None for a name that isn't a profile. Same as ``browser_api``'s."""
    if not _BOT.match(bot):
        return None
    from hermes_constants import get_default_hermes_root

    root = Path(get_default_hermes_root())
    home = root if bot == "default" else root / "profiles" / bot
    return home if home.is_dir() else None


def _authorized(ws: WebSocket) -> bool:
    """The dashboard's own WebSocket credential check, as ``browser_api`` does it."""
    try:
        from hermes_cli import web_server_chat
    except Exception:  # noqa: BLE001 - no dashboard, no way to check: refuse
        log.warning("usual-bot: dashboard auth unavailable; refusing the terminal")
        return False
    return bool(web_server_chat._ws_auth_ok(ws))


def _terminal_config(home: Path) -> dict:
    try:
        from hermes_cli.config import read_user_config_raw

        terminal = read_user_config_raw(home / "config.yaml").get("terminal") or {}
    except Exception:  # noqa: BLE001 - unreadable: Hermes's defaults
        return {}
    return terminal if isinstance(terminal, dict) else {}


def place(terminal: dict, here: str | None = None) -> tuple[str, str | None]:
    """``(backend, folder)`` from a profile's ``terminal`` section. The folder is where a local
    Bot runs its commands, or None for a sandboxed one."""
    backend = str(terminal.get("backend") or "local").strip().lower()
    if backend != "local":
        return backend, None
    configured = str(terminal.get("cwd") or "").strip()
    folder = os.getcwd() if here is None else here
    if configured not in _HERE:
        folder = os.path.expanduser(configured)
    if not os.path.isdir(folder):
        folder = os.path.expanduser("~")
    return backend, folder


def _user() -> pwd.struct_passwd:
    return pwd.getpwuid(os.getuid())


def shell_environment(home: Path, user: pwd.struct_passwd, source: dict[str, str]) -> dict[str, str]:
    env = {key: source[key] for key in _KEEP if key in source}
    env.setdefault("PATH", "/usr/local/bin:/usr/bin:/bin")
    env.update(
        HOME=user.pw_dir,
        USER=user.pw_name,
        LOGNAME=user.pw_name,
        SHELL=user.pw_shell or "/bin/sh",
        TERM="xterm-256color",
        COLORTERM="truecolor",
        HERMES_HOME=str(home),
    )
    env.setdefault("LANG", "en_US.UTF-8")
    return env


def _size(cols, rows) -> tuple[int, int]:
    def clamp(value, fallback: int) -> int:
        try:
            return min(1000, max(2, int(float(value))))
        except (TypeError, ValueError):
            return fallback

    return clamp(cols, 80), clamp(rows, 24)


# ── One shell ────────────────────────────────────────────────────────────────────────────────────


class _Shell:
    def __init__(self, ws: WebSocket, home: Path, folder: str, shell: str | None = None) -> None:
        self.ws = ws
        self.shell = shell
        self.home = home
        self.folder = folder
        self.pid = 0
        self.fd = -1
        self.out: asyncio.Queue[bytes | None] = asyncio.Queue()

    def _spawn(self, cols: int, rows: int) -> None:
        user = _user()
        shell = self.shell or user.pw_shell or "/bin/sh"
        env = shell_environment(self.home, user, dict(os.environ))
        env["SHELL"] = shell
        argv = [shell, "-l"]
        folder = self.folder
        pid, fd = pty.fork()
        if pid == 0:  # the child: only what's safe between fork and exec
            try:
                os.chdir(folder)
                os.execve(shell, argv, env)
            finally:
                os._exit(127)
        self.pid, self.fd = pid, fd
        self.resize(cols, rows)

    def resize(self, cols: int, rows: int) -> None:
        with contextlib.suppress(OSError):
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def _readable(self) -> None:
        try:
            data = os.read(self.fd, _READ)
        except OSError:  # EIO: the shell and everything holding the terminal are gone
            data = b""
        if data:
            self.out.put_nowait(data)
        else:
            asyncio.get_running_loop().remove_reader(self.fd)
            self.out.put_nowait(None)

    def _exit_code(self) -> int | None:
        with contextlib.suppress(ChildProcessError):
            done, status = os.waitpid(self.pid, os.WNOHANG)
            if done:
                return os.waitstatus_to_exitcode(status)
        return None

    async def _send(self) -> None:
        while (data := await self.out.get()) is not None:
            await self.ws.send_bytes(bytes([_OUTPUT]) + data)
        code = None
        for _ in range(20):  # the shell closed the terminal; give it a moment to be reaped
            code = self._exit_code()
            if code is not None:
                break
            await asyncio.sleep(0.05)
        self.pid = 0
        await self.ws.send_bytes(bytes([_CONTROL]) + json.dumps({"type": "exit", "code": code}).encode())

    async def _receive(self) -> None:
        while True:
            message = await self.ws.receive_bytes()
            if not message:
                continue
            if message[0] == _OUTPUT:
                with contextlib.suppress(OSError):
                    os.write(self.fd, message[1:])
            elif message[0] == _CONTROL:
                with contextlib.suppress(ValueError):
                    body = json.loads(message[1:])
                    if isinstance(body, dict) and body.get("type") == "resize":
                        self.resize(*_size(body.get("cols"), body.get("rows")))

    async def run(self) -> None:
        cols, rows = _size(self.ws.query_params.get("cols"), self.ws.query_params.get("rows"))
        self._spawn(cols, rows)
        loop = asyncio.get_running_loop()
        loop.add_reader(self.fd, self._readable)
        user = _user()
        await self.ws.send_bytes(
            bytes([_CONTROL])
            + json.dumps({"type": "ready", "user": user.pw_name, "host": socket.gethostname(), "cwd": self.folder}).encode()
        )
        sender = asyncio.create_task(self._send())
        receiver = asyncio.create_task(self._receive())
        try:
            await asyncio.wait({sender, receiver}, return_when=asyncio.FIRST_COMPLETED)
        finally:
            receiver.cancel()
            sender.cancel()
            with contextlib.suppress(Exception):
                loop.remove_reader(self.fd)
            await self._hang_up()

    async def _hang_up(self) -> None:
        if self.pid:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(self.pid, signal.SIGHUP)
            for _ in range(20):
                if self._exit_code() is not None:
                    break
                await asyncio.sleep(0.1)
            else:
                with contextlib.suppress(ProcessLookupError, PermissionError):
                    os.killpg(self.pid, signal.SIGKILL)
                with contextlib.suppress(ChildProcessError):
                    os.waitpid(self.pid, 0)
        with contextlib.suppress(OSError):
            os.close(self.fd)


# ── Routes ───────────────────────────────────────────────────────────────────────────────────────


@router.get("/terminal/status")
async def status(bot: str) -> dict:
    """Behind the dashboard's normal sign-in. ``available``: the Bot runs its commands on this host,
    so a shell here is where they run."""
    home = _bot_home(bot)
    if home is None:
        raise HTTPException(status_code=404, detail="no such Bot")
    backend, folder = place(_terminal_config(home))
    return {
        "bot": bot,
        "available": folder is not None,
        "backend": backend,
        "user": _user().pw_name,
        "host": socket.gethostname(),
        "cwd": folder,
    }


@router.websocket("/terminal")
async def terminal(ws: WebSocket) -> None:
    if not _authorized(ws):
        await ws.close(code=4401)
        return
    home = _bot_home(ws.query_params.get("bot", ""))
    if home is None:
        await ws.close(code=4404)
        return
    _, folder = place(_terminal_config(home))
    if folder is None:
        await ws.close(code=4409)
        return
    await ws.accept()
    try:
        await _Shell(ws, home, folder).run()
    except WebSocketDisconnect:
        pass
    finally:
        with contextlib.suppress(Exception):
            await ws.close()
