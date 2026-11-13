# Usual Bot: cross-project known issues

Record a new issue as symptom → source-supported cause → verified fix or explicitly unverified
recommendation → prevention and status. Once fixed, keep only the trap and how to avoid it.

## CI and releases

- CI uses `macos-26`: the app needs the macOS 26 / iOS 26 SDK (`ToolbarSpacer`,
  `sharedBackgroundVisibility`), which the `macos-15` image's Xcode can't compile.
- The required status check `build` is CI's last job, which passes only when every other job passed
  or was skipped for a documentation-only change. Add a new CI job to its `needs`, not to the ruleset,
  and keep its name: renaming it also needs the repository's branch rule updated. Filtering the
  workflow itself by path (`paths:`) would leave the required check pending forever on a skipped
  pull request; the `changes` job skips the macOS jobs instead.
- CodeQL's Swift scan (about half an hour of traced build) runs on `main`, weekly and by hand, not
  on pull requests, so a pull request's code scanning results cover the workflows only.
- **CI signs with certificates and profiles made beforehand, not Xcode's cloud signing.** Cloud
  signing from an App Store Connect API key needs a team key with the Admin role: an App Manager
  key failed with "Cloud signing permission error" and "No profiles for … were found". Team keys
  reach every app on the team, so the workflow uploads with an individual key limited to Usual Bot
  instead. Individual keys can't use the provisioning API, so CI never makes or fetches
  certificates or profiles. altool takes a key as individual when its file is named
  `ApiKey_<id>.p8`, and still wants an `--api-issuer`, which it ignores. Not yet verified on a real
  upload.
- **Don't `security import` the signing `.p12` whole.** Certificates made from one signing request
  share a private key, which Keychain Access writes into the `.p12` once per certificate. Importing
  it stops at the second copy, still exits 0, and leaves out the certificates after it: CI found no
  Apple Distribution certificate in a `.p12` that held it. The TestFlight workflow splits the `.p12`
  with `/usr/bin/openssl` and imports each certificate and each distinct key. Homebrew's OpenSSL 3
  reads Keychain Access's `.p12` only with `-legacy`.
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

- **`GatewaySearchTests.anAnswerToAnOlderQueryIsDropped` is flaky (unresolved).** On 8 November 2026
  it failed twice in a row in `scripts/check.sh --fast` (its 1 s `waitUntilOnMain` ran out) and
  passed on the next run, with no HermesKit change. The race isn't found yet.

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
- **The menu bar's File, View and Go items follow the window in front** (`UsualBotCommands`, through
  `focusedSceneValue`). They're disabled while the app is in the background or has no main window,
  so a demo run in the background shows them all disabled; check what they do with the app active.
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
  The Webapp is the same: `webapp.enabled`, a loopback `webapp.host`, a `webapp.public_url` on an
  `.invalid` name and those variables, then `hermes gateway run` with `HOME` and `HERMES_HOME` in a
  scratch folder, so it isn't the machine's running gateway.
- **An unsigned Debug build can't read a sign-in it didn't save itself.** One saved by an earlier
  build, or added with `security add-generic-password -A`, makes macOS ask for the login password.
  After rebuilding, delete the test address's item and sign in again. A scratch `HOME` also hides
  the login Keychain from `security`; to let a test gateway borrow the Claude Code sign-in, link
  only `~/Library/Keychains` into it.

## Push notifications

- **A Mac notification extension needs `NSExtension` › `Subsystems` = `NSExtensionService_Subsystem`.**
  Without it macOS starts the extension the iOS way, `usernoted` logs "Extension will be killed due
  to sluggish startup", and the banner shows the relay's generic text. The Mac build reads
  `Config/NotificationService-Info-macOS.plist` for this.
- **macOS opens the extension from the copy of the bundle ID in `/Applications`.** An older copy
  there without the extension gives "Failed to find extension inside /Applications/UsualBot.app".
  Replace it with the build you're testing.
- **After installing the plugin, restart the dashboard as well as the gateway.** Bot Chats' hooks also
  run in the dashboard process, and `hermes gateway restart` leaves the old gateway running until its
  turns end, still on the old code. The plugin's `presence.json` from 0.1 held one
  `{"focused", "at"}` entry, which 0.2's reader skips.
- **Don't use the `async` forms of `UNUserNotificationCenterDelegate`.** Their thunk calls the
  completion handler from Swift's thread pool; tapping a notification then aborts the iPhone app in
  `-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]`. `AgentNotifications` uses
  the completion-handler forms and calls them on the main actor.
- **`told.json` is written by two processes:** the gateway as it notifies and the dashboard or Webapp
  as you read. `store._shared` takes a file lock as well as the thread lock; on Windows, without
  `fcntl`, it holds only within one process.
- **`log` in zsh is a builtin.** Read the unified log with `/usr/bin/log show`.
- **APNs from `wrangler dev` fails:** workerd has no HTTP/2 client. Deployed Workers reach APNs
  through Cloudflare's proxy.

## Bot browser

- **On macOS, a gateway running as a launchd service can't read the browser's own profile folder.**
  Reading `~/Library/Application Support/Google/Chrome` fails with `EPERM` unless its Python has Full
  Disk Access. Hermes then logs "reusing the last snapshot" and never refreshes the Bot's copy, so its
  sign-ins are as old as that copy. The plugin reads the tab layout from the copy instead.
- **Plugin changes need both restarts.** The feed runs in the dashboard, and the flag hook in the
  Bot's agent. A cloned profile loads agent plugins only from its own `plugins/` folder, which is why
  `install.sh` copies the plugin into each real-profile Bot.
