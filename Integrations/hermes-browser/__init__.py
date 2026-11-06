"""usual-browser: watch a Bot's headless real-profile browser from Usual Bot.

Two halves in one plugin:
  dashboard/plugin_api.py   the live feed (runs in the dashboard)
  flags.py                  the Chrome flags that browser launches with (runs in the Bot, below)
"""

from __future__ import annotations

import logging

from . import flags

log = logging.getLogger(__name__)


def _before_tool(tool_name: str = "", args=None, task_id: str = "", **kwargs) -> None:
    """Before a browser tool runs (and so before the Bot's browser can launch), bring the flags up to
    date. Never blocks the tool: Hermes treats a raising hook as a veto."""
    if not str(tool_name).startswith("browser"):
        return None
    try:
        flags.sync()
    except Exception as exc:  # noqa: BLE001 - a flag problem must never stop the Bot browsing
        log.warning("usual-browser: could not update the browser flags: %s", exc)
    return None


def register(ctx) -> None:
    ctx.register_hook("pre_tool_call", _before_tool)
