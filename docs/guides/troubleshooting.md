# Troubleshooting

Each heading is a message the app shows or a problem people run into, with what causes it and
what to do.

## Connecting and signing in

### "Can't reach the gateway" / "Can't reach … It's a Tailscale address"

The device can't open a connection to the address you entered.

- Check the address and port, for example `100.101.102.103:9119`.
- For a Tailscale address (`100.x.y.z` or a `.ts.net` name), make sure Tailscale is on and signed
  in **on this device**. On iPhone this is the most common cause; there you can also turn on
  **Built-in Tailscale** (connect screen, or the gateway menu at the top left) instead of the VPN.
- Make sure the dashboard listens on that address, not only on `127.0.0.1`
  ([Getting started](getting-started.md#it-must-be-reachable-from-your-device)).
- From the same device or network, `curl http://<address>/api/status` should answer.

### "… is on the public internet, so use https:// to keep your sign-in private."

You entered `http://` with a public address. Usual Bot only sends a sign-in over plain `http` to
private and Tailscale addresses. Put the gateway behind `https`, or reach it over Tailscale.

### "This gateway doesn't offer browser sign-in for apps. Update Hermes on it."

The gateway's `/api/status` doesn't list `native_pkce` in `auth_flows`. Either Hermes on the
gateway is too old, or the dashboard has no interactive sign-in set up (a username and password,
or OAuth). Update Hermes and set up a sign-in; see
[Get your gateway ready](getting-started.md#2-get-your-gateway-ready).

### "Sign-in didn't finish" or "Sign-in was cancelled"

The browser didn't hand the sign-in back. Try again, and finish signing in on the gateway's page.
On the Mac, the page opens in your default browser; when it says you can close the tab, switch back
to Usual Bot. Security software that blocks apps from listening on `127.0.0.1` can also stop it.

### "Your sign-in expired. Sign in again."

The gateway ended the session: you signed out elsewhere, the refresh token expired after a long
time offline, or the gateway's sign-in settings changed. Sign in again.

### Connected, but chats don't load

Usual Bot supports the Hermes **dashboard** (`hermes dashboard`), which speaks the "legacy"
session protocol. A gateway started with `hermes gateway` speaks the newer "canonical" protocol:
the app connects and lists agents, but chats there aren't supported yet. Connect to the gateway
machine's dashboard instead.

## On the Mac

### The Mac asks for my Keychain password after every build

Without an Apple team, each build is signed "to run locally" with a signature that changes every
time, and the Keychain treats each build as a new app. Choose **Always Allow**, or set
`DEVELOPMENT_TEAM` in `Config/Local.xcconfig` (see
[Run it on your iPhone](getting-started.md#run-it-on-your-iphone)) so builds keep one signature.
After the first signed build, macOS asks once more; then it stops.

### The Dock shows a blank icon

macOS caches an app's icon from the first time it saw that copy. Quit Usual Bot, then:

```sh
touch path/to/UsualBot.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f path/to/UsualBot.app
killall Dock
```

### ⌥Space doesn't open the quick message panel

Another app may already use ⌥Space (some launchers and input-source switchers do). Quit or rebind
that app. Usual Bot has to be running; it stays in the menu bar after you close its window.

## Chats

### "/retry didn't run: retry does not support media …"

Hermes can't retry a message that had an image or file attached. Send the message again with the
attachment instead.

### "The answer was lost while Usual Bot was offline. Ask again."

When the connection drops, the app catches up on what it missed when it reconnects. If the gateway
restarted or dropped the chat's live session in between, a side answer or reply can't be
recovered, and the chat says so rather than waiting forever. Ask again. A background task that was
only starting gets a similar note: if no result comes, start it again.

### An image in a reply shows as a file tile

The app couldn't load the file the agent named; hover the tile to see why. Common causes are a
relative path or a file the gateway doesn't let apps read. Ask the agent for the full path, or to
save the image again.

## Voice

### "The microphone is off for Usual Bot"

Allow the microphone in **System Settings › Privacy & Security › Microphone** on the Mac, or
**Settings › Usual Bot** on iPhone. Dictation also needs **Speech Recognition**.

### GPT-Live isn't offered, or "GPT-Live couldn't start"

GPT-Live runs through your gateway with its OpenAI key. Make sure the gateway has one set up for
its voice features, then try again. On-device calls work without it.

## Still stuck?

Search the existing issues, or open a new one with the bug report form. Include the app version,
your Hermes version, Mac or iPhone, and the exact message. Never paste tokens, real gateway
addresses or private conversations into an issue.
