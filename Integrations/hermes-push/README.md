# Push notifications for Usual Bot

A Hermes plugin that tells you when a Bot replies, messages you or needs you, through
[ntfy](https://ntfy.sh) or [Pushover](https://pushover.net), even when Usual Bot is closed.

It runs on your gateway, which is the only thing awake when your phone isn't. Apple's own push would
need a key held by whoever signs the app, so you bring your own service and nothing runs in between.

## Install

Where your gateway runs:

```sh
git clone https://github.com/usual-labs/usual-bot
sh usual-bot/Integrations/hermes-push/install.sh
```

Restart the gateway's dashboard. The script adds the plugin to every profile, and running it again
after adding a profile covers that one too.

## Set up

In Usual Bot, open **Settings › Notifications › Push**.

- **ntfy:** install the ntfy app and subscribe to a topic. Pick a long name nobody would guess, or
  use an access token, as anyone who knows a public topic can read it. You can also use your own
  ntfy server. On iPhone, a server of your own needs ntfy's upstream setting for instant delivery.
  Messages can still arrive late on iPhone; swipe down in the ntfy app to fetch them.
- **Pushover:** install the app, then paste your user key and an application token from your
  Pushover account.

Press **Send Test**. With ntfy, tapping a notification opens that chat in Usual Bot. Pushover opens
its own app first, so tap the notification, then **Open in Usual Bot** below the message.

## What it sends

- A reply or message from a Bot, and a room member's reply.
- When a Bot asks for approval, asks a question or wants the sudo password. Passwords and your
  answers never reach the plugin.

Helpers, routines and other platforms stay quiet, and so does everything while you're using Usual
Bot on any device. A Mac counts until its screen sleeps. **Send Test** always goes out. With previews
off, notifications say only who needs you.

Previews pass through the service you picked, so use your own ntfy server or turn previews off if
that matters to you. Settings are in `~/.hermes/usual-push/`, readable only by your user.
