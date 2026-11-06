# Bot browser view for Usual Bot

A Hermes plugin that lets you watch a Bot's browser live from Usual Bot, on your Mac or your phone,
while that browser runs headless on your gateway with no window on its screen. It's for Bots that
browse with your real browser profile (`browser.use_real_profile`), so they're signed in where you
are.

Watch only for now: nothing you do in the view reaches the browser.

## Install

Where your gateway runs:

```sh
git clone https://github.com/usual-labs/usual-bot
sh usual-bot/Integrations/hermes-browser/install.sh
```

Restart your gateway (`hermes gateway restart`) and its dashboard.

The script adds the plugin only to Bots that browse with your real profile. The one exception is
your main Hermes folder: the dashboard serves the view from there, so it gets a copy whenever any
Bot needs one. That copy does nothing to the main Bot's browser unless it uses your real profile too.
Run the script again after turning real-profile browsing on or off for a Bot.

## What it does to the Bot's browser

Before the Bot uses its browser, the plugin keeps these Chrome flags in that Bot's
`browser.chromium_args`:

- **`--window-size`**: a desktop-size window whose page is 1440 pixels wide. The browser copies your
  tab layout from your profile, and vertical tabs take a strip beside the page, so the window is
  widened by that strip: none for tabs along the top, the width you dragged them to when expanded
  (240 by default), 56 when collapsed.
- **`--user-agent`**: your browser's own user agent without the "HeadlessChrome" that sites such as
  Cloudflare block. Its version follows the browser you have installed, so an update never leaves
  it behind.
- **`--disable-blink-features=AutomationControlled`**: `navigator.webdriver` stays false, as in a
  browser you run yourself.
- **`--screen-info`**: a 1920×1080 screen instead of headless 800×600.

A flag you set yourself wins: if `chromium_args` already has your own `--user-agent`, say, the plugin
leaves it and adds only the others. The flags it wrote are listed in `<profile>/usual-browser/flags.json`,
so it can tell them from yours. It takes them back out when real-profile browsing or headless mode is
turned off.

Changes apply the next time the Bot's browser starts. A browser that's already running keeps the
flags it started with.

## The view

The dashboard serves:

- `GET /api/plugins/usual-browser/status?bot=<profile>` returns `available` (the Bot browses with your
  real profile, headless) and `browser` (its browser is open now).
- `WS /api/plugins/usual-browser/feed?bot=<profile>&ticket=<from POST /api/auth/ws-ticket>` streams
  the page. It takes optional `format=jpeg|png` (default jpeg) and `quality=1..100` (default 90).
  Binary messages are frames at the page's full size. Text messages are
  `{"type":"state","state":"waiting"|"live"}` and `{"type":"tab","url","title"}`. The view follows
  the tab the Bot opens, and waits when the Bot's browser isn't running.

  The Bot often works in a tab it opened in the background, which Chrome doesn't paint. While you
  watch one, the plugin takes a throwaway screenshot of it twice a second so it paints, without
  bringing it to the front. The page sees itself become visible for that moment.

There's a test page in the dashboard at `/usual-browser`.

## Good to know

- On macOS, a gateway running as a background service can't read your browser's own folder unless
  it has Full Disk Access. Hermes then reuses the copy it made last time, and the plugin reads the
  tab layout from that copy.
- The feed checks sign-in with the dashboard's own WebSocket check, the same one Hermes' bundled
  Kanban plugin uses. It isn't a public Hermes API, so a Hermes update could change it.
