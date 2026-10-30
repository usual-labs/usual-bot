# Usual Bot: cross-project known issues

Record a new issue as symptom → source-supported cause → verified fix or explicitly unverified
recommendation → prevention and status. Once fixed, keep only the trap and how to avoid it.

## CI and releases

- CI uses `macos-26`: the app needs the macOS 26 / iOS 26 SDK (Liquid Glass), which the `macos-15`
  image's Xcode can't compile.
- Keep the CI job's `name: build` aligned with the required status check. Renaming it also needs the
  repository's branch rule updated.
- Workflow actions are pinned to full commit SHAs. When adding an action, check both the pin and the
  repository's Actions allow-list. CodeQL builds the app with Xcode; a package-only SwiftPM scan
  doesn't cover `App/`.
- `CODEOWNERS` applies from the base branch, so a pull request that adds an owner isn't gated by it.
- Public build and release setup, signing-secret names, environment protection, immutable-release
  behavior and troubleshooting live in [the release guide](../guides/releasing.md). Maintainer
  credentials, account administration and release-session diaries don't belong in the public KB.

## Tests

- **Recovery starts after the chat takes input again.** `attach` opens the chat, then the recovery
  task runs. What can be lost is decided when the chat attaches; otherwise a question sent just
  after a reconnect shows as lost, which failed `SideQuestionTests` on CI.
- **Wait for the event, not a fixed time.** Fixed sleeps failed on slow runners
  (`silentSocketIsClosedAfterTheLimit`). `scripts/check-test-waits.sh` rejects a `Task.sleep` without
  a `// sleep-ok:` reason. Leave several intervals of slack in timing tests. Don't retry a flaky test;
  find the race.

## Mac

- **The Keychain asks for the password after every rebuild without a team.** Ad-hoc builds' designated
  requirement is their `cdhash`, and `TokenStore`'s file-based keychain item trusts the exact app that
  saved it. Set your team in the gitignored `Config/Local.xcconfig`; the requirement is then the bundle
  ID plus the certificate. One more prompt follows the first signed build, and another after a renewed
  certificate. Builds without a team still prompt.
- **The Dock can keep a blank icon** after an icon is added, because the Dock and LaunchServices cache
  it per registration. Quit the app, `touch` the bundle, `lsregister -f <app>`, `killall Dock`, reopen.
- **A `WindowGroup` gets AppKit's automatic window tabbing** unless the app turns it off
  (`NSWindow.allowsAutomaticWindowTabbing = false` in `UsualBotApp.init`). Windows already tabbed when
  the app relaunches weren't tested.
- **AppKit fills menus when they open.** `NSApp.mainMenu` read at launch shows neither the tab items nor
  Enter Full Screen, so open the menu before checking its items.

## Gateway

- `/retry` on a message with a photo answers "retry does not support media or unknown content parts".
  That's the gateway's behaviour: send the message again with the image.
