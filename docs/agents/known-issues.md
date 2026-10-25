# Usual Bot: cross-project known issues

## Implemented today

- There is no landing-site/blog implementation, canonical website origin or
  configured Git remote in the 23 October 2026 local inventory. The internal avatar
  HTML gallery is not a product landing page. A blog publication task cannot be
  completed by placing Markdown in this native tree; follow
  [blog-publishing.md](blog-publishing.md) for the missing prerequisites.
- Native CI configuration is not evidence of a successful build or public release.
  CI runs on `macos-26`: the app uses the macOS 26 / iOS 26 SDK (Liquid Glass), which
  the `macos-15` image's Xcode can't compile. With no remote yet, CI has never run.
- Status (25 October 2026): the published-facing docs are README (quick start, features,
  screenshots), `docs/guides/` (getting started, user guide, troubleshooting, architecture),
  CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, CHANGELOG and `.github` issue/PR templates. Its
  screenshots were retaken on 25 October 2026 from the debug demo (`USUALBOT_DEMO=1`), not
  real chats; Mac dark mode couldn't be captured (`-AppleInterfaceStyle Dark` as a launch
  argument didn't change the SwiftUI app), so the dark shot is iPhone. The README's
  quick-start build was checked from a clean clone without `Config/Local.xcconfig` (ad-hoc
  signed, demo opens). Not done until the repo is published, and only by the maintainer:
  enabling GitHub private vulnerability reporting (SECURITY.md relies on it), and the
  Code of Conduct's contact (it points at the maintainer's GitHub profile; a dedicated
  address would be better). The history was rewritten before the first push so that no
  commit contains the maintainer's tailnet IP or tailnet name; tests and comments use
  Tailscale's example address `100.101.102.103`. Release `v0.1.0` is tagged locally only.

For new issues record symptom → source-supported cause → verified fix or explicitly
unverified recommendation → prevention and status.

## The Keychain asked for the password after every Mac rebuild (fixed locally 2026-10-24)

- Symptom: each new Mac build asked for the login keychain password before reading the saved
  sign-in; "Always Allow" lasted only until the next build.
- Root cause: without `DEVELOPMENT_TEAM`, Mac builds are signed ad hoc, so the app's designated
  requirement is its `cdhash`, which changes every build. `TokenStore` uses the file-based login
  keychain, whose item ACL trusts the exact app that saved it.
- Fix (this machine): `Config/Local.xcconfig` (gitignored) sets the maintainer's team, so Mac
  Debug builds are signed with the Apple Development certificate and the designated requirement
  is the bundle ID plus that certificate, stable across rebuilds. No provisioning profile or
  device registration was needed. One more prompt follows the first signed build (Always Allow);
  a renewed certificate asks once again. Forks without a team still see the prompt (README).

## The Dock kept a blank icon after the app icon was added (fixed locally 2026-10-24)

- Symptom: after `a35c1d4` added `AppIcon`, the Mac Dock still drew Usual Bot as the generic blank
  app tile, although the built bundle had `AppIcon.icns` and `Assets.car` and
  `NSWorkspace.icon(forFile:)` rendered the doodle.
- Cause: the Dock and LaunchServices cache an app's icon per registration; the dev build had been
  registered (and its icon cached) before it had one.
- Fix: quit the app, `touch` the bundle, `lsregister -f <app>`, `killall Dock` (it relaunches),
  open the app again. Needed again only when the icon changes.

## The gateway won't /retry a message with an image (seen 2026-10-24, shakedown)

- `/retry` on a message that carried a photo answers "retry does not support media or unknown
  content parts"; the app shows it as "/retry didn't run: …". Gateway behaviour, not an app bug:
  send the message again with the image instead.

