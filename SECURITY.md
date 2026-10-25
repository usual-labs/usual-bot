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
- The cached chats are written with file protection, in the app's own container.
- Debug-only switches (such as recording socket frames) are compiled out of Release builds.
- Releases are built by a GitHub workflow, signed with a Developer ID, notarized by Apple, and
  immutable once published. Each disk image has a build-provenance attestation:
  `gh attestation verify UsualBot-<version>.dmg -R usual-labs/usual-bot` shows the workflow and
  commit it came from.
