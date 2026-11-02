# Usual Bot: cross-project known issues

Record a new issue as symptom → source-supported cause → verified fix or explicitly unverified
recommendation → prevention and status. Once fixed, keep only the trap and how to avoid it.

## CI and releases

- CI uses `macos-26`: the app needs the macOS 26 / iOS 26 SDK (`ToolbarSpacer`,
  `sharedBackgroundVisibility`), which the `macos-15` image's Xcode can't compile.
- Keep the CI job's `name: build` aligned with the required status check. Renaming it also needs the
  repository's branch rule updated.
- Workflow actions are pinned to full commit SHAs. When adding an action, check both the pin and the
  repository's Actions allow-list. CodeQL builds the app with Xcode; a package-only SwiftPM scan
  doesn't cover `App/`.
- `CODEOWNERS` applies from the base branch, so a pull request that adds an owner isn't gated by it.
- **Pass `Binding(get:set:)` a closure, not a method reference.** CI's Xcode 26.6 crashed in IR
  generation on `set: setLaunchAtLogin` (a reabstraction thunk for an `@isolated(any)` setter);
  `set: { setLaunchAtLogin($0) }` builds. Xcode 27 compiles both, so a local build doesn't catch it.
- Public build and release setup, signing-secret names, environment protection, immutable-release
  behavior and troubleshooting live in [the release guide](../guides/releasing.md). Maintainer
  credentials, account administration and release-session diaries don't belong in the public KB.

## Tests

- **A Bot made in the demo doesn't open while `-selectedContact` is passed.** That launch argument
  pins the stored selection for the run, so the app's write to it is ignored. New Room behaves the
  same. Launch without it, or pick the Bot from the sidebar.
- **Recovery starts after the chat takes input again.** `attach` opens the chat, then the recovery
  task runs. What can be lost is decided when the chat attaches; otherwise a question sent just
  after a reconnect shows as lost, which failed `SideQuestionTests` on CI.
- **Wait for the event, not a fixed time.** Fixed sleeps failed on slow runners
  (`silentSocketIsClosedAfterTheLimit`). `scripts/check-test-waits.sh` rejects a `Task.sleep` without
  a `// sleep-ok:` reason. Leave several intervals of slack in timing tests. Don't retry a flaky test;
  find the race.

## Mac

- **Carbon shares hot keys unless registration is exclusive.** A successful registration with
  options `0` can compete with another app for the same shortcut. Keep `kEventHotKeyExclusive` so
  conflicts are reported; `scripts/check-shortcuts.sh` reserves a key in a second process to check
  refusal, fallback and release without touching saved preferences.
- **SwiftUI buttons can leave the shortcut recorder as first responder.** Disable and Restore Default
  must end recording explicitly; waiting for `resignFirstResponder` leaves the next key able to
  replace the shortcut after the user disabled it. The shortcut check covers both actions.
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

- **A Bot renamed outside the app refuses its chat for up to 5 minutes** ("This chat is open in
  another Hermes window/terminal"). A chat's lease is filed in the profile folder, and the session
  that took it releases it at the path it had, which the rename moved. The dashboard's 5-minute sweep
  then drops leases with no live session. So the app sends `session.close` for the old ID's session
  (`ChatThread.release`); a session left by an earlier run of the app holds the lease until the
  dashboard drops that session (seen holding for over 15 minutes). Hermes-side; seen on `bf0203a794`.

- **MCP sign-in needs the gateway reachable from the browser** (source finding, unverified live).
  Hermes builds the OAuth redirect from the address the app used (`request.base_url`) unless
  `dashboard.public_url` is set, so the browser on the same device can usually reach it. A provider
  may still refuse a plain `http` redirect that isn't localhost, such as a Tailscale IP; the flow
  then ends in `error` with the provider's reason. The gateway's callback page says to return to
  Hermes, not Usual Bot.
- **A catalog install that fetches code reports nothing back.** `needs_install` entries run as a
  background `hermes mcp install` and answer `{background: true}`. The app reloads the list for about
  three minutes and says so if the server never appears; the install's log is on the gateway.
- **Removing an app keeps its secrets.** `_remove_mcp_server` deletes only the config entry: a key in
  the profile's `.env` and an OAuth token stay, and adding it again reuses them.
- **Run Now answers only when the run ends.** `POST /api/cron/jobs/{id}/trigger` runs the job inside
  the request, which can take minutes, so it gets a 30-minute timeout. If the app loses the request
  (the iPhone suspends it, the network drops), the run goes on: the routine says to check Past Runs.
  A second press while it runs gets 409.
- **Script-only runs have no transcript.** Their rows in `/runs` have `cron_output:` IDs and only a
  180-character `preview`, so that's all a past run shows for them.

- **Deleting a Bot can take several seconds.** Hermes stops its gateway first (up to 10 s) before
  removing the folder; the sheet shows Deleting… until the request ends.

- `/retry` on a message with a photo answers "retry does not support media or unknown content parts".
  That's the gateway's behaviour: send the message again with the image.
- **A real sign-in needs a gated gateway, which loopback isn't.** `dashboard --isolated` on `127.0.0.1`
  reports no `native_pkce`, so the app refuses it. To test sign-in without a real login, give a
  throwaway profile `dashboard.public_url: https://usualbot-test.invalid` and start the server with
  `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`, `_PASSWORD` and `_SECRET`. That server still lists every
  profile in the Hermes home, and the machine's running gateway picks up a new profile by itself:
  open only the throwaway agent. A debug build keeps its settings under its own bundle ID, apart from
  the installed app's. `CFFIXED_USER_HOME` moves its cache but not `UserDefaults`, so afterwards
  delete `gatewayAddress` from that domain, and the Keychain item for the test address.
