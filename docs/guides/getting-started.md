# Getting started

This guide takes you from nothing to chatting with your own agents. It has three parts:
get the app, get your Hermes gateway ready, and sign in.

## 1. Get the app

### Install a release (Mac)

With [Homebrew](https://brew.sh), one command installs the latest release:

```sh
brew install --cask usual-labs/tap/usual-bot
```

`brew upgrade --cask usual-bot` updates it later. Without Homebrew, use the signed and notarized
disk image that each release has (from version 0.2.0 on):

1. Download `UsualBot-<version>.dmg` from the
   [latest release](https://github.com/usual-labs/usual-bot/releases/latest).
2. Open it and drag **Usual Bot** onto **Applications**.
3. Open Usual Bot from Applications or Spotlight.

To check the download, compare `shasum -a 256 UsualBot-<version>.dmg` with the `.sha256` file
next to it on the release page. To check that it was built by this project's release workflow from
the tagged source, run `gh attestation verify UsualBot-<version>.dmg -R usual-labs/usual-bot`. To update, download the new version and replace the app; your
sign-in and settings stay.

For the iPhone, or to change the code, build it yourself as below.

### Build it yourself

You need a Mac with **Xcode 26 or newer**. The app runs on macOS 15 and iOS 18 or later.

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
agents, a room, an approval and some routines instead of signing in. The demo never connects to
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

Setting a team also helps on the Mac: builds keep the same signature, so macOS stops asking for
your Keychain password after each rebuild (see [Troubleshooting](troubleshooting.md#the-mac-asks-for-my-keychain-password-after-every-build)).

## 2. Get your gateway ready

Usual Bot talks to the **Hermes dashboard**, the same server the official Hermes desktop app
connects to (`hermes dashboard`, port 9119 by default). It needs two things from it.

### It must be reachable from your device

By default the dashboard listens on `127.0.0.1` only, which other devices can't reach. Pick one:

- **Tailscale (recommended).** Put the gateway machine and your devices on the same tailnet and
  bind the dashboard to the machine's tailnet address, for example
  `hermes dashboard --host 100.101.102.103`. Nothing is exposed to the internet. On iPhone,
  Tailscale has to be on while you use the app.
- **Your home network.** Bind to the machine's local address. The first time, iOS asks whether
  Usual Bot may find devices on your local network; allow it.
- **The internet.** Put the dashboard behind `https` (a reverse proxy with a certificate). Usual
  Bot refuses plain `http` to public addresses, so your sign-in never travels unencrypted.

### It must have a sign-in

When the dashboard listens on anything other than `127.0.0.1`, Hermes requires a sign-in method,
and won't start without one. Either works with Usual Bot:

- **Username and password**, the simplest for a home or tailnet setup. Run
  `hermes dashboard --host <address>` in a terminal once and Hermes offers to set one up.
- **OAuth** through an identity provider, for example Nous Portal.

Hermes's own [web dashboard docs](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md)
cover both, and how to run the dashboard as a service.

### Check it

From the device you'll use (or any machine on the same network):

```sh
curl http://100.101.102.103:9119/api/status
```

Look for `"auth_required": true` and `"native_pkce"` in `auth_flows`. `native_pkce` is the browser
sign-in for apps that Usual Bot uses. If it's missing, update Hermes on the gateway.

## 3. Sign in

1. Open Usual Bot and enter the gateway's address. The port is part of it, for example
   `100.101.102.103:9119` or `https://hermes.example.com`. Without a scheme, private and tailnet
   addresses use `http` and everything else `https`.
2. Usual Bot checks the gateway and opens its sign-in page: on the Mac in your default browser, so
   saved passwords and existing sign-ins carry over; on iPhone in a sign-in sheet. Sign in there as
   you would in the official app.
3. The page hands the sign-in back to the app, and your agents appear as contacts. On the Mac,
   switch back to Usual Bot; the browser tab says you can close it.

The app keeps your sign-in in the Keychain and refreshes it as it goes, so you won't sign in again
unless the gateway ends your session. To switch gateways, sign out from the connection status at
the bottom of the sidebar (on iPhone, the dot at the top left).

## What's next

- The [user guide](user-guide.md) walks through chats, approvals, rooms, calls and the rest.
- If something doesn't connect, see [Troubleshooting](troubleshooting.md).
