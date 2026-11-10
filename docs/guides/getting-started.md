# Getting started

This guide takes you from nothing to chatting with your own Bots. It has three parts:
get the app, get your Hermes gateway ready, and sign in.

## 1. Get the app

### Install the beta (Mac and iPhone)

Usual Bot is in beta on TestFlight. A public link to join is coming soon; until then, build it
yourself as below. Once it's out:

1. Install Apple's [TestFlight](https://apps.apple.com/app/testflight/id899247664) app on your Mac
   or iPhone.
2. Open the Usual Bot beta link on that device and choose **Accept**, then **Install**.
3. Open Usual Bot. TestFlight updates it when a new build is out, and the app says so too; your
   sign-in and settings stay.

Each build lasts 90 days, and a newer one arrives before then. If you installed Usual Bot with
Homebrew or from a GitHub download, those stopped at 0.3.0. Install the beta over it; you may have
to sign in to your gateway again.

To change the code, build it yourself as below.

### Build it yourself

You need a Mac with **Xcode 26 or newer**. The app runs on macOS 26 and iOS 26 or later.

```sh
git clone https://github.com/usual-labs/usual-bot.git
cd usual-bot
open UsualBot.xcodeproj
```

In Xcode, pick the **UsualBot** scheme and a destination:

- **My Mac** builds and runs the Mac app. Without an Apple team set, Xcode signs it "to run
  locally", which is all you need on your own Mac.
- **An iPhone simulator** works with no setup.
- **Your iPhone** needs an Apple team; see [Run it on your iPhone](#run-it-on-your-iphone).

Press **Run** (⌘R). The app opens on the connect screen.

### Look around first with the demo

Debug builds started with the `USUALBOT_DEMO=1` environment variable show a made-up team of
Bots, a room, an approval and some routines instead of signing in. The demo never connects to
anything, so nothing you do in it is sent anywhere.

- **In Xcode:** **Product › Scheme › Edit Scheme… › Run › Arguments**, add `USUALBOT_DEMO` with
  the value `1` under **Environment Variables**, and run.
- **From Terminal:**

  ```sh
  xcodebuild -project UsualBot.xcodeproj -scheme UsualBot -destination 'platform=macOS' \
    -derivedDataPath build build
  USUALBOT_DEMO=1 build/Build/Products/Debug/UsualBot.app/Contents/MacOS/UsualBot
  ```

Remove the variable again before you sign in to a real gateway.

### Run it on your iPhone

1. Copy the example settings: `cp Config/Local.xcconfig.example Config/Local.xcconfig`.
2. In `Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` to your team ID (Xcode › Settings ›
   Accounts) and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you own, such as `com.yourname`.
   The file is gitignored, so it stays on your machine.
3. Connect the iPhone, pick it as the destination and press **Run**. The first time, Xcode may ask
   to register the device, and iOS asks you to trust the developer in **Settings › General › VPN &
   Device Management**.

A signed build also carries the share extension, which needs an App Group
(`group.<your prefix>.UsualBot`) in your team. Xcode registers it when it signs for you; if it
reports a missing App Group, let it fix signing or build with `-allowProvisioningUpdates`. Builds
that aren't signed for a team run without sharing from other apps.

Setting a team also helps on the Mac: builds keep the same signature, so macOS stops asking for
your Keychain password after each rebuild (see [Troubleshooting](troubleshooting.md#the-mac-asks-for-my-keychain-password-after-every-build)).

## 2. Get your gateway ready

Usual Bot talks to your Hermes gateway's own web listener, the one Hermes calls the **Webapp**
(port 9120 by default). Chats there run on the gateway itself, the same process behind the CLI,
the official desktop app and messaging, so routines and other Bots can post into your Bot Chats.

Usual Bot can also connect to the older **Hermes dashboard** (`hermes dashboard`, port 9119). It
works, but the dashboard holds your Bot Chats itself, so routine results and messages from other
Bots can't reach them while you're connected. The app says so in its connection status.

### Turn on the Webapp

On the gateway machine:

```sh
hermes config set webapp.enabled true
hermes gateway restart
```

The gateway reads these settings when it starts, so restart it after each change below too.
`hermes webapp --status` says whether it's serving and, if not, why.

### It must be reachable from your device

The Webapp listens on `127.0.0.1` only, which other devices can't reach. Pick one:

- **Tailscale Serve (recommended).** Keep the Webapp on `127.0.0.1` and let Tailscale give it an
  `https` address on your tailnet. Nothing is exposed to the internet.

  ```sh
  tailscale serve --bg --https=443 http://127.0.0.1:9120
  hermes config set webapp.public_url https://<machine>.<tailnet>.ts.net
  hermes gateway restart
  ```

  `tailscale serve status` shows the address. On iPhone, keep the Tailscale app's VPN on while you
  use Usual Bot.
- **Your tailnet only, over plain `http`.** To reach the machine by its tailnet address without a
  certificate, have Tailscale forward a port instead. Tailscale already encrypts traffic between
  your devices.

  ```sh
  tailscale serve --bg --tcp=9121 tcp://127.0.0.1:9120
  hermes config set webapp.public_url http://100.101.102.103:9121
  hermes gateway restart
  ```

  Use the machine's own tailnet address (`tailscale ip -4`), and sign in to Usual Bot with
  `100.101.102.103:9121`. Use `--tcp`, not `--http`: Tailscale's `--http` mode answers only at the
  machine's name, and Hermes accepts only the address in `webapp.public_url`.
- **Every network the machine is on.** `hermes config set webapp.host 0.0.0.0`. The Webapp then
  answers on the machine's local and tailnet addresses, over plain `http`; use it only on networks
  you trust. The first time, iOS asks whether Usual Bot may find devices on your local network;
  allow it.
- **The internet.** Put the Webapp behind `https` (a reverse proxy or tunnel with a certificate)
  and set `webapp.public_url` to that address. Usual Bot refuses plain `http` to public addresses,
  so your sign-in never travels unencrypted.

`webapp.host` takes only a loopback address, `0.0.0.0` or `::`, because Hermes's own apps on the
machine reach the Webapp at `127.0.0.1`. A tailnet address there keeps the Webapp off.

### It must have a sign-in

When the Webapp is reachable from other machines (`0.0.0.0`, `::`, or a `public_url`), Hermes
requires the same sign-in as the dashboard, and serves the Webapp only once one is set up. Either
works with Usual Bot:

- **Username and password**, the simplest for a home or tailnet setup.
- **OAuth** through an identity provider, for example Nous Portal.

Hermes's [Webapp docs](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md#use-the-desktop-workspace-from-a-browser)
and [dashboard sign-in docs](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md#authentication-gated-mode)
cover both.

### Check it

From the device you'll use (or any machine on the same network):

```sh
curl https://hermes.example.com/api/status
curl http://100.101.102.103:9120/api/status
```

Look for `"auth_required": true` and `"native_pkce"` in `auth_flows`. `native_pkce` is the browser
sign-in for apps that Usual Bot uses. If it's missing, update Hermes on the gateway.

## 3. Sign in

1. Open Usual Bot and enter the gateway's address. The port is part of it, for example
   `100.101.102.103:9120` or `https://hermes.example.com`. Without a scheme, private and tailnet
   addresses use `http` and everything else `https`.
2. Usual Bot checks the gateway and opens its sign-in page: on the Mac in your default browser, so
   saved passwords and existing sign-ins carry over; on iPhone in a sign-in sheet. Sign in there as
   you would in the official app.
3. The page hands the sign-in back to the app, and your Bots appear as contacts. On the Mac,
   switch back to Usual Bot; the browser tab says you can close it.

The app keeps your sign-in in the Keychain and refreshes it as it goes, so you won't sign in again
unless the gateway ends your session. To switch gateways, sign out from the connection status at
the bottom of the sidebar (on iPhone, Settings › your gateway).

**Moving from the dashboard to the Webapp.** The Webapp has its own address, so sign out of the
dashboard in Usual Bot and sign in again with the Webapp's address. Your Bots and chats are the same
on both. If you use push notifications, run the push plugin's
[install script](../../Integrations/hermes-push/README.md#install) again to update it: older
versions don't notify you when a Bot on the Webapp needs you.

## What's next

- The [user guide](user-guide.md) walks through chats, approvals, rooms, calls and the rest.
- If something doesn't connect, see [Troubleshooting](troubleshooting.md).
