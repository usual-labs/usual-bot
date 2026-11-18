# Usual Bot's gateway plugin

A Hermes plugin with what Usual Bot needs from your gateway:

- **Push.** Tells your devices when a Bot replies, messages you or needs you, even when Usual Bot is
  closed.
- **A Bot's browser.** Lets you watch a Bot's browser live, while it runs headless on your gateway.
- **Where the Bot is.** Tells a Bot, in the chats Usual Bot opened, that it's talking through
  Usual Bot and what shows there.

It does nothing for chats you have in a terminal, the Hermes app or anywhere else.

## Install

In Usual Bot, open **Plugins** from the sidebar's footer on a Mac and choose **Install**. It goes
into every Bot, and into each Bot you make in the app afterwards.

Or, where your gateway runs:

```sh
git clone https://github.com/usual-labs/usual-bot
sh usual-bot/Integrations/install-usual-bot.sh
```

Then restart your gateway (`hermes gateway restart`), and its dashboard if you run one. The script
adds the plugin to every profile, and running it again after adding a profile covers that one too.
It also removes `usual-push` and `usual-browser`, the two plugins this one replaces; your devices and
settings stay.

## Push

Each notification is sealed on your gateway for one device, with a key only that device and your
gateway have. Usual's push relay ([`Services/push-relay`](../../Services/push-relay/README.md)) and
Apple pass it on without being able to read it. The relay knows only where to reach each device.

Sign in to your gateway in Usual Bot. Each device adds itself, so there's nothing to fill in. Under
**Settings › Notifications** you'll see **This device: Gets notifications**, a **Send Test** button,
and a switch for each Bot on that device.

What it sends:

- A reply or message from a Bot, and a room member's reply.
- When a Bot asks for approval, asks a question or wants the sudo password. Passwords and your
  answers never reach the plugin.

Helpers, routines and other platforms stay quiet, and so does the reply to a widget's button (its
answer is the widget changing), and a Bot you've hidden, in Usual Bot or the Hermes app, except in
rooms. A chat you're reading on any device is quiet on all of them; everything else reaches every
device that hasn't turned that Bot off. Opening a chat on one device takes down what your other
devices show about it, with a silent push that names nothing outside its seal. With previews off on
a device, its notifications say only who needs you.

To hear from a routine, set its **Results** to **Post in this chat**. Its output then lands in the
Bot's chat, the Bot replies there, and that reply notifies you. Don't have a Bot load this plugin's
files to send its own notifications: they're private and change between versions.

Settings are in `~/.hermes/usual-push/`, readable only by your user: each device's choices and the
two keys it gave your gateway. Signing out of Usual Bot removes that device.

A device signed in to two gateways gives each one its own ID, which the plugin seals into every
notification, so the app can tell your gateways' `default` Bots apart and switch to the right
gateway when you tap.

## A Bot's browser

For Bots that browse with your real browser profile (`browser.use_real_profile`), so they're
signed in where you are. Watch only for now: nothing you do in the view reaches the browser.

Before such a Bot uses its browser, the plugin keeps these Chrome flags in its
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
turned off, and leaves the flags of a Bot that doesn't browse with your real profile alone.

Changes apply the next time the Bot's browser starts. A browser that's already running keeps the
flags it started with.

The dashboard serves:

- `GET /api/plugins/usual-bot/status?bot=<profile>` returns `available` (the Bot browses with your
  real profile, headless) and `browser` (its browser is open now).
- `WS /api/plugins/usual-bot/feed?bot=<profile>&ticket=<from POST /api/auth/ws-ticket>` streams
  the page. It takes optional `format=jpeg|png` (default jpeg), `quality=1..100` (default 90) and
  `density=1|2` (default 1).
  Binary messages are frames at the page's full size. Text messages are
  `{"type":"state","state":"waiting"|"live"}` and `{"type":"tab","url","title"}`. The view follows
  the tab the Bot opens, and waits when the Bot's browser isn't running.

  The Bot often works in a tab it opened in the background, which Chrome doesn't paint. While you
  watch one, the plugin takes a throwaway screenshot of it twice a second so it paints, without
  bringing it to the front. The page sees itself become visible for that moment.

  Chrome's screencast sends the page at its size in CSS pixels whatever the density, so at
  `density=2` the plugin uses it only to see that the page changed, and then sends a screenshot
  drawn at twice the pixels, at most four a second. The page's `devicePixelRatio`, and the
  screenshots the Bot takes, stay at 1.

There's a test page in the dashboard at `/usual-bot`.

On macOS, a gateway running as a background service can't read your browser's own folder unless it
has Full Disk Access. Hermes then reuses the copy it made last time, and the plugin reads the tab
layout from that copy. The feed checks sign-in with the dashboard's own WebSocket check, the same
one Hermes' bundled Kanban plugin uses. It isn't a public Hermes API, so a Hermes update could
change it.

## Where the Bot is

Usual Bot's chats reach Hermes the way its terminal UI's do, so a Bot is told it's in a terminal,
where files it sends print as text. In a chat Usual Bot opened, the plugin adds a note to the first
message: that the Bot is talking through Usual Bot, which isn't Hermes's official app, and what
shows there (Markdown, files with `MEDIA:` lines, and widgets). The text is in
[`context.py`](context.py). It says nothing about you or your device.

Hermes keeps the note with that message, so the plugin adds it once per chat, and again only when
the chat no longer has it, as after compressing the chat. Routines' results and other Bots'
messages posted in the chat get it too, because they're turns in it. Rooms don't.

The app tells the plugin which chats it opened with `PUT /api/plugins/usual-bot/chats/<session ID>`.
The list is in `~/.hermes/usual-push/chats.json`; a chat nobody has used in 30 days drops off it. A
Bot Chat you also open in the Hermes app is the same chat, so its Bot hears about Usual Bot there
too.
