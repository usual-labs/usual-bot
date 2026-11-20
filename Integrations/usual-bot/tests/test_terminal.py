"""The terminal drawer's shell: only for a Bot whose commands run on this host, in the folder they run
in, without the gateway's secrets, and gone when the app closes it."""

import asyncio
import importlib.util
import json
import os
import pwd
import sys
import tempfile
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load():
    # FastAPI is the dashboard's; the tests need only the names the module imports.
    if "fastapi" not in sys.modules:
        fastapi = types.ModuleType("fastapi")

        class Router:
            def get(self, *_args, **_kwargs):
                return lambda function: function

            websocket = get

        fastapi.APIRouter = Router
        fastapi.HTTPException = type("HTTPException", (Exception,), {"__init__": lambda self, **kw: None})
        fastapi.WebSocket = object
        fastapi.WebSocketDisconnect = type("WebSocketDisconnect", (Exception,), {})
        sys.modules["fastapi"] = fastapi
    spec = importlib.util.spec_from_file_location("usual_bot_terminal_under_test", ROOT / "dashboard" / "terminal_api.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


terminal_api = _load()


class PlaceCase(unittest.TestCase):
    def test_a_sandboxed_bot_has_no_shell(self):
        self.assertEqual(terminal_api.place({"backend": "docker"}), ("docker", None))
        self.assertEqual(terminal_api.place({"backend": "SSH", "cwd": "/srv"}), ("ssh", None))

    def test_a_local_bot_works_where_hermes_runs_its_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(terminal_api.place({}, here=folder), ("local", folder))
            self.assertEqual(terminal_api.place({"cwd": "."}, here=folder), ("local", folder))
            self.assertEqual(terminal_api.place({"backend": "local", "cwd": folder}, here="/"), ("local", folder))
        missing = terminal_api.place({"cwd": "/no/such/folder"}, here="/")
        self.assertEqual(missing, ("local", os.path.expanduser("~")))

    def test_the_shell_gets_none_of_the_gateways_secrets(self):
        user = pwd.getpwuid(os.getuid())
        env = terminal_api.shell_environment(
            Path("/h/profiles/scout"), user, {"PATH": "/bin", "ANTHROPIC_API_KEY": "sk-x", "LANG": "C.UTF-8"}
        )
        self.assertNotIn("ANTHROPIC_API_KEY", env)
        self.assertEqual(env["PATH"], "/bin")
        self.assertEqual(env["HERMES_HOME"], "/h/profiles/scout")
        self.assertEqual(env["TERM"], "xterm-256color")
        self.assertEqual(env["HOME"], user.pw_dir)


class FakeSocket:
    """The app's side: types `script` once the shell is ready, and keeps what comes back."""

    def __init__(self, script):
        self.query_params = {"cols": "100", "rows": "30"}
        self.script = list(script)
        self.received = []
        self.incoming: asyncio.Queue = asyncio.Queue()

    async def send_bytes(self, data):
        self.received.append(data)
        if data[0] == 1 and json.loads(data[1:])["type"] == "ready":
            for message in self.script:
                self.incoming.put_nowait(message)

    async def receive_bytes(self):
        return await self.incoming.get()

    def output(self):
        return b"".join(message[1:] for message in self.received if message[0] == 0).decode(errors="replace")

    def controls(self):
        return [json.loads(message[1:]) for message in self.received if message[0] == 1]


class ShellCase(unittest.TestCase):
    def run_shell(self, script, timeout=10):
        with tempfile.TemporaryDirectory() as folder:
            folder = os.path.realpath(folder)
            ws = FakeSocket(script)
            shell = terminal_api._Shell(ws, Path(folder), folder, shell="/bin/sh")
            asyncio.run(asyncio.wait_for(shell.run(), timeout))
            return ws, folder, shell

    def test_a_shell_runs_what_you_type_and_says_when_it_ends(self):
        resize = b"\x01" + json.dumps({"type": "resize", "cols": 42, "rows": 7}).encode()
        ws, folder, _ = self.run_shell(
            [resize, b"\x00echo \"$HERMES_HOME|$(pwd)|$(stty size)\"\n", b"\x00exit 3\n"]
        )
        controls = ws.controls()
        self.assertEqual(controls[0]["type"], "ready")
        self.assertEqual(controls[0]["cwd"], folder)
        self.assertIn(f"{folder}|{folder}|7 42", ws.output())
        self.assertEqual(controls[-1], {"type": "exit", "code": 3})

    def test_closing_the_socket_hangs_up_the_shell(self):
        class Gone(Exception):
            pass

        script = [b"\x00sleep 30\n"]
        ws = FakeSocket(script)
        real = ws.receive_bytes
        calls = {"count": 0}

        async def receive():
            calls["count"] += 1
            if calls["count"] > 1:
                await asyncio.sleep(0.3)  # the command has started
                raise Gone
            return await real()

        ws.receive_bytes = receive
        with tempfile.TemporaryDirectory() as folder:
            shell = terminal_api._Shell(ws, Path(folder), folder, shell="/bin/sh")
            asyncio.run(asyncio.wait_for(shell.run(), 10))
        with self.assertRaises(ChildProcessError):
            os.waitpid(shell.pid, os.WNOHANG)


if __name__ == "__main__":
    unittest.main()
