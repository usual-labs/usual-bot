"""The flags a Bot's headless real-profile browser launches with.

Hermes appends ``browser.chromium_args`` to every launch. While ``browser.use_real_profile`` is on and
``browser.headed`` is off, this keeps four of them in that list:

  --window-size                 a desktop-size window whose page is 1440 wide, whatever the copied
                                profile's tab layout: vertical tabs take a strip beside the page
  --user-agent                  the browser's real Chrome user agent, without the "HeadlessChrome"
                                that sites such as Cloudflare block; its version follows the installed
                                browser, so a browser update never leaves it behind
  --disable-blink-features=AutomationControlled
                                navigator.webdriver stays false, as in a browser a person runs
  --screen-info                 a real screen size instead of headless 800x600

Flags someone else wrote are never touched: a switch already in the list that this plugin didn't put
there (your own --user-agent, say) wins, and this one is left out. The flags this plugin wrote are
recorded in ``<profile>/usual-browser/flags.json``, so they can be told apart and taken back out when
real-profile browsing or headless mode is turned off.

Changes apply when the browser next launches. A browser that is already running keeps the flags it
started with.
"""

from __future__ import annotations

import json
import logging
import os
import platform
import plistlib
import re
import subprocess
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)

PAGE_WIDTH = 1440  # the page itself, as sites and the Bot's screenshots see it
WINDOW_HEIGHT = 900
SCREEN = "{1920x1080}"
# Vertical tab strip widths, measured on Chrome 156: expanded is the width saved in the profile
# (240 until someone drags it), collapsed is a fixed icon rail.
_STRIP_DEFAULT = 240
_STRIP_COLLAPSED = 56

_PLATFORM_TOKEN = {
    "Darwin": "Macintosh; Intel Mac OS X 10_15_7",  # frozen by Chrome on every macOS version
    "Windows": "Windows NT 10.0; Win64; x64",
    "Linux": "X11; Linux x86_64",
}
_DETECT_TTL_S = 600.0  # how long the default-browser answer is trusted

_lock = threading.Lock()
_cache: dict = {}  # small per-process caches keyed by file and mtime


# ── What the flags should be ─────────────────────────────────────────────────────────────────────


def _switch(flag: str) -> str:
    return flag.split("=", 1)[0]


def _mtime(path: Path) -> float | None:
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def _default_browser() -> str | None:
    """The browser Hermes copies the profile of: the system default Chromium browser."""
    hit = _cache.get("browser")
    if hit and time.monotonic() - hit[0] < _DETECT_TTL_S:
        return hit[1]
    from hermes_cli.browser_connect import detect_default_chromium

    key = detect_default_chromium()
    _cache["browser"] = (time.monotonic(), key)
    return key


def browser_major(binary: str) -> int | None:
    """The installed browser's major version: from its app bundle on macOS, ``--version`` elsewhere."""
    path = Path(binary)
    plist = next((p / "Info.plist" for p in path.parents if p.name == "Contents"), None)
    probe = plist if plist is not None else path
    stamp = (str(probe), _mtime(probe))
    if stamp[1] is None:
        return None
    if _cache.get("major", (None,))[0] == stamp:
        return _cache["major"][1]
    major = None
    try:
        if plist is not None:
            with plist.open("rb") as fh:
                version = str(plistlib.load(fh).get("CFBundleShortVersionString", ""))
        else:
            version = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=10).stdout
        found = re.search(r"(\d+)\.\d+", version)
        major = int(found.group(1)) if found else None
    except (OSError, ValueError, subprocess.SubprocessError, plistlib.InvalidFileException):
        major = None
    _cache["major"] = (stamp, major)
    return major


def user_agent(major: int, browser: str | None, system: str | None = None) -> str:
    """Chrome's own (reduced) user agent for this machine. Edge adds its token; Brave and Chromium
    send Chrome's as is."""
    token = _PLATFORM_TOKEN.get(system or platform.system(), _PLATFORM_TOKEN["Linux"])
    agent = (f"Mozilla/5.0 ({token}) AppleWebKit/537.36 (KHTML, like Gecko) "
             f"Chrome/{major}.0.0.0 Safari/537.36")
    return agent + f" Edg/{major}.0.0.0" if browser == "edge" else agent


def source_profile(data_dir: Path, pin: str | None) -> Path:
    """The profile Hermes copies: ``browser.real_profile_pin``, else the one Chrome last used."""
    if pin:
        return data_dir / pin
    try:
        state = json.loads((data_dir / "Local State").read_text(encoding="utf-8-sig", errors="replace"))
        last = (state.get("profile") or {}).get("last_used") or "Default"
    except (OSError, ValueError, AttributeError):
        last = "Default"
    return data_dir / str(last)


def tab_strip_width(profile: Path) -> int | None:
    """How much of the window's width the profile's tabs take: 0 for tabs along the top, else the
    vertical strip (expanded or collapsed). None when its settings can't be read."""
    prefs = profile / "Preferences"
    stamp = _mtime(prefs)
    if stamp is None:
        return None
    seen = _cache.setdefault("strip", {})
    if str(prefs) in seen and seen[str(prefs)][0] == stamp:
        return seen[str(prefs)][1]
    try:
        tabs = json.loads(prefs.read_text(encoding="utf-8-sig", errors="replace")).get("vertical_tabs") or {}
    except (OSError, ValueError, AttributeError) as exc:
        # macOS keeps a background gateway out of the browser's own folder unless it has Full Disk
        # Access; Hermes then can't refresh its copy either, and launches on the last one.
        log.debug("usual-browser: could not read %s: %r", prefs, exc)
        width = None
    else:
        if not isinstance(tabs, dict) or not tabs.get("enabled"):
            width = 0
        elif tabs.get("collapsed_state"):
            width = _STRIP_COLLAPSED
        else:
            try:
                width = max(0, int(tabs.get("uncollapsed_width") or _STRIP_DEFAULT))
            except (TypeError, ValueError):
                width = _STRIP_DEFAULT
    seen[str(prefs)] = (stamp, width)
    return width


def _truthy(value) -> bool:
    return value is True or str(value).strip().lower() in {"1", "true", "yes", "on"}


def wanted(browser_settings: dict) -> list[str]:
    """The flags this Bot's browser should launch with, or [] when they don't apply to it."""
    if not _truthy(browser_settings.get("use_real_profile")) or _truthy(browser_settings.get("headed")):
        return []
    from hermes_cli.browser_connect import chromium_executable, real_profile_copy_dir, real_profile_data_dir

    browser = _default_browser()
    # The tabs the browser will launch with: the profile Hermes copies from, which it re-copies on
    # launch, else (when that can't be read) the copy from last time, which Hermes then reuses.
    places = []
    data_dir = real_profile_data_dir(browser) if browser else None
    if data_dir:
        pin = browser_settings.get("real_profile_pin")
        places.append(source_profile(Path(data_dir), pin.strip() if isinstance(pin, str) else None))
    if browser:
        places.append(Path(real_profile_copy_dir(browser)) / "Default")
    strip = next((w for w in map(tab_strip_width, places) if w is not None), 0)
    flags = [
        f"--window-size={PAGE_WIDTH + strip},{WINDOW_HEIGHT}",
        "--disable-blink-features=AutomationControlled",
        f"--screen-info={SCREEN}",
    ]
    binary = chromium_executable(browser) if browser else None
    major = browser_major(binary) if binary else None
    if major:
        flags.append(f"--user-agent={user_agent(major, browser)}")
    return flags


# ── Keeping config.yaml in step ──────────────────────────────────────────────────────────────────


def _as_list(value) -> list[str]:
    """``browser.chromium_args`` as Hermes reads it: a list, or one comma/newline separated string."""
    if isinstance(value, str):
        value = value.replace("\n", ",").split(",")
    return [str(v).strip() for v in (value or []) if str(v).strip()]


def merge(current: list[str], ours_before: list[str], want: list[str]) -> tuple[list[str], list[str]]:
    """``(new list, flags of ours in it)``: ``current`` with the flags this plugin wrote last time
    swapped for ``want``. A switch someone else set wins over ours."""
    mine = set(ours_before)
    theirs = [flag for flag in current if flag not in mine]
    taken = {_switch(flag) for flag in theirs}
    added = [flag for flag in want if _switch(flag) not in taken]
    return theirs + added, added


def _state_file(home: Path) -> Path:
    return home / "usual-browser" / "flags.json"


def _read_state(home: Path) -> list[str]:
    try:
        written = json.loads(_state_file(home).read_text()).get("written", [])
        return [str(flag) for flag in written] if isinstance(written, list) else []
    except (OSError, ValueError, AttributeError):
        return []


def _write_state(home: Path, written: list[str]) -> None:
    path = _state_file(home)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"written": written}, indent=2) + "\n")
    os.replace(tmp, path)


def sync() -> bool:
    """Bring this Bot's ``browser.chromium_args`` up to date. True when config.yaml changed."""
    from hermes_cli.config import get_config_path, read_user_config_raw
    from hermes_cli.config_backend import write_config_key
    from hermes_constants import get_hermes_home
    from tools.browser_session_cloud import browser_section

    home = Path(get_hermes_home())
    want = wanted(browser_section())
    with _lock:
        config_path = get_config_path()
        raw_browser = read_user_config_raw(config_path).get("browser") or {}
        current = _as_list(raw_browser.get("chromium_args") if isinstance(raw_browser, dict) else None)
        ours_before = _read_state(home)
        updated, written = merge(current, ours_before, want)
        changed = updated != current
        if changed:
            write_config_key(config_path, "browser.chromium_args", updated)
            log.info("usual-browser: browser flags in %s are now %s", config_path, " ".join(written) or "(none)")
        if written != ours_before:
            _write_state(home, written)
    return changed
