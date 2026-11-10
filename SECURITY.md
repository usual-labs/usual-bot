# Security policy

Usual Bot holds the keys to someone's Hermes agents: a sign-in that can read their conversations
and approve commands on their machines. We take reports about it seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through this repository's
**Security › Report a vulnerability** page (GitHub's private vulnerability reporting).

Include what you found, how to reproduce it, which version or commit you tested, and what an
attacker could do with it. Please leave real tokens, gateway addresses and conversations out of
the report; made-up ones are fine.

We aim to acknowledge a report within a week and to keep you updated while we fix it. Once a fix
is released, we're glad to credit you in the advisory and the changelog, unless you'd rather stay
anonymous.

## What's in scope

Problems in this repository's code, for example:

- how the app signs in, stores and refreshes tokens (`Packages/HermesKit/Sources/HermesKit/Auth`);
- the loopback sign-in listener and its `state` and PKCE checks;
- sending a sign-in or token over plain `http`, or to the wrong host;
- the offline cache, notifications or logs exposing conversations;
- the push relay (`Services/push-relay`) or the gateway plugin (`Integrations/hermes-push`)
  letting anyone read a notification, or push to a device that didn't give them its send key;
- the update check (`Services/updates`) exposing its App Store Connect key, or making the app open
  anything but TestFlight;
- a secret or sudo password reaching anything but the gateway that asked for it;
- an approval being granted without the person choosing it;
- the GPT-Live web view reaching more than it should.

Problems in **Hermes Agent** itself (the gateway, its sign-in pages, its permissions) belong to the
Hermes project; please report those to
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent/security). If you're not
sure which side a problem is on, report it here and we'll help route it.

## Supported versions

Usual Bot is young and built from source. Fixes land on `main` and in the next release; older
releases don't get separate patches.

## How the app and its releases protect you

- Tokens are stored in the Keychain, readable only on this device and only after it has been
  unlocked once since it started.
- The app refuses plain `http` to public addresses; it's allowed only for private and Tailscale
  addresses.
- The cached chats and your unsent drafts are written with file protection, in the app's own
  container. Drafts are left out of device backups, and signing out deletes both.
- Push notifications are sealed on your gateway with a key only that device and the gateway hold;
  Usual's relay and Apple carry them without being able to read them. The relay stores only each
  device's push token and hashes of its two secrets.
- TestFlight builds ask Usual's update check at `bot.usual.dev` which build is the latest. The
  request carries nothing about you, and the service stores nothing.
- Debug-only switches (such as recording socket frames) are compiled out of Release builds.
- Builds ship through Apple's TestFlight, signed by the team and checked by Apple. Each version is
  tagged in this repository. The older Homebrew and GitHub downloads (up to 0.3.0) were signed with
  a Developer ID and notarized.
