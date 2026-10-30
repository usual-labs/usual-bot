# Usual Bot: cross-project known issues

## Implemented today

- CI uses `macos-26`: the app needs the macOS 26 / iOS 26 SDK (Liquid Glass),
  which the `macos-15` image's Xcode cannot compile. Configuration is not proof of a
  successful run. Recorded CI evidence: `2ada691` (run as `fd067cb`, before the 26 October
  history rewrite) passed lint, both test suites and the Mac and iOS Simulator builds on
  25 October 2026.
- Keep the CI job's `name: build` aligned with the required status check. Renaming it
  also requires updating the repository's branch rule; changing YAML alone is insufficient.
- Workflow actions are pinned to full commit SHAs. When adding an action, check both
  the pin and the repository's Actions allow-list. CodeQL builds the app with Xcode;
  a package-only SwiftPM scan does not cover `App/`.
- Public build/release setup, signing-secret names, environment protection, immutable-release
  behavior and troubleshooting live in [the release guide](../guides/releasing.md).
  Maintainer credentials, account administration and release-session diaries do not belong
  in the public knowledge base.

For new issues record symptom → source-supported cause → verified fix or explicitly
unverified recommendation → prevention and status.

## The Keychain asked for the password after every Mac rebuild (fixed locally 2026-10-24)

- Symptom: each new Mac build asked for the login keychain password before reading the saved
  sign-in; "Always Allow" lasted only until the next build.
- Root cause: without `DEVELOPMENT_TEAM`, Mac builds are signed ad hoc, so the app's designated
  requirement is its `cdhash`, which changes every build. `TokenStore` uses the file-based login
  keychain, whose item ACL trusts the exact app that saved it.
- Fix: set your development team in the gitignored `Config/Local.xcconfig` so Mac Debug builds
  use an Apple Development certificate. The designated requirement is then the bundle ID plus
  that certificate, stable across rebuilds. One more prompt follows the first signed build
  (Always Allow); a renewed certificate asks once again. Builds without a team still see the
  prompt (README). The local fix was verified on 24 October 2026; it was not rerun in this audit.

## The Dock kept a blank icon after the app icon was added (fixed locally 2026-10-24)

- Symptom: after `97a938d` added `AppIcon`, the Mac Dock still drew Usual Bot as the generic blank
  app tile, although the built bundle had `AppIcon.icns` and `Assets.car` and
  `NSWorkspace.icon(forFile:)` rendered the doodle.
- Cause: the Dock and LaunchServices cache an app's icon per registration; the dev build had been
  registered (and its icon cached) before it had one.
- Fix: quit the app, `touch` the bundle, `lsregister -f <app>`, `killall Dock` (it relaunches),
  open the app again. Needed again only when the icon changes.

## View > Show Tab Bar drew a tab bar across the Mac window (fixed 2026-10-30)

- Symptom: macOS's automatic View > Show Tab Bar and Window tab items were available, and the tab
  bar sat between the hidden title bar's toolbar and the panes.
- Cause: a `WindowGroup` gets AppKit's automatic window tabbing unless the app turns it off.
- Fix: `NSWindow.allowsAutomaticWindowTabbing = false` in `UsualBotApp.init`. Verified in the demo
  build by dumping the opened View and Window menus, with the flag on as a control. Windows already
  tabbed when the app relaunches weren't tested.
- Prevention: AppKit fills these menus when they open, so `NSApp.mainMenu` read at launch shows
  neither the tab items nor Enter Full Screen. Open the menu before checking its items.

## The gateway won't /retry a message with an image (seen 2026-10-24, shakedown)

- `/retry` on a message that carried a photo answers "retry does not support media or unknown
  content parts"; the app shows it as "/retry didn't run: …". Gateway behaviour, not an app bug:
  send the message again with the image instead.

## CI's first run failed on swift-format lint (fixed 2026-10-25)

- Symptom: the first push to GitHub failed CI at the Lint step with 42 `swift format lint --strict`
  errors in 18 files (long lines, indentation, line breaks, trailing commas); tests and builds
  never ran.
- Cause: the M13–M22 work was tested and built locally but never linted, and nothing ran CI before
  the repo had a remote.
- Fix: `swift format format -i --recursive App Packages` (local swift-format 6.3.0) fixed all of
  them; tests and both unsigned builds passed afterwards.
- Prevention: run the lint line from CONTRIBUTING before every commit, as CI does.


## The heartbeat test failed once on a GitHub runner (fixed 2026-10-25)

- Symptom: `silentSocketIsClosedAfterTheLimit` failed on CI for `82a69da` (run as `ab6419c`;
  no `gateway.ping` sent) while the same code passed before and locally.
- Cause: the test used a 20 ms heartbeat with a 60 ms silence limit and a fixed 200 ms sleep.
  On a slow runner the first heartbeat tick can arrive after the limit, so the channel closes
  before it ever pings.
- Fix: a 300 ms limit (15 heartbeats) and waiting for the ping, then for the socket to close
  (`FakeSocket.isClosed`), instead of sleeping. Passed 15/15 runs locally.
- Prevention: timing tests wait for the event with `waitUntil` and leave several intervals of
  slack; don't assert after a fixed sleep.
