# Push notifications for Usual Bot

A Hermes plugin that tells your devices when a Bot replies, messages you or needs you, even when
Usual Bot is closed. It runs on your gateway, which is the only thing awake when your phone isn't.

Each notification is sealed on your gateway for one device, with a key only that device and your
gateway have. Usual's push relay ([`Services/push-relay`](../../Services/push-relay/README.md)) and
Apple pass it on without being able to read it. The relay knows only where to reach each device.

## Install

Where your gateway runs:

```sh
git clone https://github.com/usual-labs/usual-bot
sh usual-bot/Integrations/hermes-push/install.sh
```

Restart your gateway and its dashboard: Bot Chats run hooks in both. The script adds the plugin to
every profile, and running it again after adding a profile covers that one too.

## Set up

Sign in to your gateway in Usual Bot. Each device adds itself, so there's nothing to fill in. Under
**Settings › Notifications** you'll see **This device: Gets notifications**, a **Send Test** button,
and a switch for each Bot on that device.

## What it sends

- A reply or message from a Bot, and a room member's reply.
- When a Bot asks for approval, asks a question or wants the sudo password. Passwords and your
  answers never reach the plugin.

Helpers, routines and other platforms stay quiet, and so does a Bot you've hidden, in Usual Bot or
the Hermes app, except in rooms. A chat you're reading on any device is quiet on
all of them; everything else reaches every device that hasn't turned that Bot off. With previews
off on a device, its notifications say only who needs you.

To hear from a routine, set its **Results** to **Post in this chat**. Its output then lands in the Bot's chat,
the Bot replies there, and that reply notifies you. Don't have a Bot load this plugin's files to
send its own notifications: they're private and change between versions.

Settings are in `~/.hermes/usual-push/`, readable only by your user: each device's choices and the
two keys it gave your gateway. Signing out of Usual Bot removes that device.
