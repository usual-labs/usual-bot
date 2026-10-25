# Usual Bot: cross-project known issues

## Implemented today

- There is no landing-site/blog implementation or canonical website origin. The source is
  public on GitHub at `usual-labs/usual-bot` (remote `origin`, pushed 25 October 2026). The internal avatar
  HTML gallery is not a product landing page. A blog publication task cannot be
  completed by placing Markdown in this native tree; follow
  [blog-publishing.md](blog-publishing.md) for the missing prerequisites.
- Native CI configuration is not evidence of a successful build or public release.
  CI runs on `macos-26`: the app uses the macOS 26 / iOS 26 SDK (Liquid Glass), which
  the `macos-15` image's Xcode can't compile. On GitHub, the first run failed at
  lint (below); `fd067cb` passed every step (lint, both test suites, Mac and iOS Simulator
  builds) on 25 October 2026.
- Status (25 October 2026): the published-facing docs are README (quick start, features,
  screenshots), `docs/guides/` (getting started, user guide, troubleshooting, architecture),
  CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, CHANGELOG and `.github` issue/PR templates. Its
  screenshots were retaken on 25 October 2026 from the debug demo (`USUALBOT_DEMO=1`), not
  real chats; Mac dark mode couldn't be captured (`-AppleInterfaceStyle Dark` as a launch
  argument didn't change the SwiftUI app), so the dark shot is iPhone. The README's
  quick-start build was checked from a clean clone without `Config/Local.xcconfig` (ad-hoc
  signed, demo opens). GitHub private vulnerability reporting, which SECURITY.md
  relies on, was turned on 25 October 2026 (API reports `enabled: true`). Still open: the
  Code of Conduct's contact points at the maintainer's GitHub profile (a dedicated address
  would be better). The history was rewritten before the first push so that no
  commit contains the maintainer's tailnet IP or tailnet name; tests and comments use
  Tailscale's example address `100.101.102.103`. Tag `v0.1.0` has no GitHub release.
  **Usual Bot 0.2.0 is released** (25 October 2026, tag `v0.2.0` on `fcb19b6`, the commit
  with the fuller app icon; marked Latest): `UsualBot-0.2.0.dmg` + `.sha256`. The downloaded
  DMG matched its checksum, `spctl` accepted the DMG and app as "Notarized Developer ID",
  and the app is `labs.usual.UsualBot` 0.2.0 (build 3) with the new icon. A first `v0.2.0`
  run on `49d9a41` was cancelled before publishing so the icon could ship, and the tag was
  moved; the `v0.2.0-rc.1` test pre-release and its tag were deleted afterwards.
- GitHub security settings (25 October 2026, set via the API): Actions may run only
  GitHub-owned actions pinned to a full commit SHA (`sha_pinning_required`), so a new action
  must be pinned or CI fails; workflow runs from every outside contributor need approval;
  secret scanning and push protection are on; the "Release tags" ruleset lets only repo admins
  create, move or delete `v*` tags; the six signing secrets exist only in the `release`
  environment (required reviewer: the maintainer, `v*` tags only), not repo-wide. In
  `release.yml` the signing job has `contents: read` and a separate `publish` job without
  secrets has `contents: write`, plus `id-token`/`attestations: write` to sign a
  build-provenance attestation for the DMG (`actions/attest-build-provenance`). Two branch
  rulesets on `main`: "main: no history rewrites" (deletion and force-push blocked, **no
  bypass, not even admins**) and "main: pull requests and CI" (PR, linear history, required
  `build` check from GitHub Actions; admins bypass, so the maintainer pushes directly).
  Immutable releases are on (already enabled when checked; v0.2.0 itself predates it and isn't
  immutable): the publish job creates a draft, attaches assets, then publishes; a published
  release's assets and tag can't change and tags can't be reused, so test releases need a new
  `-rc.N`. Dependabot (`.github/dependabot.yml`) groups weekly updates of the pinned actions;
  vulnerability alerts and security-update PRs are on. Automated security checks: CodeQL default
  setup (Swift + Actions; GitHub turned it on by itself, no workflow file), zizmor
  (`zizmor.yml`, clean even at `--persona pedantic` on 25 October 2026) and OpenSSF Scorecard
  (`scorecard.yml`, README badge). The Actions allow-list adds exactly two third-party actions,
  `zizmorcore/zizmor-action` and `ossf/scorecard-action` (any SHA, but pins are required). The CI
  job keeps `name: build` because that is the required status check on main; renaming it means
  updating the "main: pull requests and CI" ruleset. The org doesn't require two-factor
  authentication (changing it needs the `admin:org` scope or the web UI).
- Release pipeline (verified 25 October 2026): the six secrets were set from the maintainer's
  Developer ID certificate (team G6WL4CPNV3) and an App Store Connect key with the
  **Developer** role, which notarytool accepted. `v0.2.0-rc.1` ran every step green on the
  first try, with no provisioning profile needed. Its downloaded `.dmg` matched its
  `.sha256`; `spctl` accepted the disk image and the app inside as "Notarized Developer ID"
  with stapled tickets; the app is `labs.usual.UsualBot` 0.2.0, universal, hardened runtime,
  and launched to its window on this Mac (macOS 27). Not checked: a fresh download through a
  browser (quarantine prompt) on a second Mac, and macOS 15 itself.

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

- Symptom: `silentSocketIsClosedAfterTheLimit` failed on CI for `ab6419c` (no `gateway.ping`
  sent) while the same code passed before and locally.
- Cause: the test used a 20 ms heartbeat with a 60 ms silence limit and a fixed 200 ms sleep.
  On a slow runner the first heartbeat tick can arrive after the limit, so the channel closes
  before it ever pings.
- Fix: a 300 ms limit (15 heartbeats) and waiting for the ping, then for the socket to close
  (`FakeSocket.isClosed`), instead of sleeping. Passed 15/15 runs locally.
- Prevention: timing tests wait for the event with `waitUntil` and leave several intervals of
  slack; don't assert after a fixed sleep.
