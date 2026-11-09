# Releasing

For maintainers. Usual Bot ships through **TestFlight**, on the Mac and the iPhone alike.
[`scripts/testflight.sh`](../../scripts/testflight.sh) archives both apps with push and uploads
them; Xcode signs them for the App Store and makes the certificates and profiles it needs itself.

Until version 0.3.0, the Mac app was also a notarized download on GitHub and a Homebrew cask. Both
are retired: they couldn't carry push without hand-made Developer ID profiles.

## One-time setup

1. A **paid Apple Developer Program membership**, with Push Notifications on for the App ID
   `labs.usual.UsualBot`.
2. In [App Store Connect](https://appstoreconnect.apple.com), the app `labs.usual.UsualBot` with
   both platforms. If it has only one, open it and add the other with **Add Platform**.
3. In Xcode › Settings › Accounts, an Apple Account that's an **Admin** or the **Account Holder**
   on the team, so Xcode may make distribution certificates.
4. In TestFlight, a test group. For people outside the team, an external group with a public link;
   its **Beta App Description** should say that Usual Bot isn't made by, affiliated with or
   endorsed by Nous Research, the makers of Hermes Agent.

## Making a release

1. **Check CI is green** on the commit you want to ship.
2. **Set the version.** Rename `## Unreleased` in `CHANGELOG.md` to the version and date, for
   example `## 0.4.0 - 2026-11-05`, add a fresh empty `## Unreleased` above it, and set
   `MARKETING_VERSION` in `Config/Shared.xcconfig` to match. Commit, tag (`v0.4.0`) and push.
3. **Upload** from that commit: run the **TestFlight** workflow from the Actions tab (see
   [From GitHub Actions](#from-github-actions)), or from your Mac, with a clean working tree:

   ```sh
   DEVELOPMENT_TEAM=<team ID> scripts/testflight.sh
   ```

   It archives the Mac and iPhone apps, with the current time as the build number, and uploads
   them. `--check` signs and exports into `build/TestFlight` without uploading; `mac` or `iphone`
   does one.
4. **Hand it to testers.** Apple processes each build in a few minutes and sends an email. Answer
   the export compliance question if App Store Connect asks, paste the version's changelog section
   into **What to Test**, and add the builds to the test groups. An external group's first build of
   each version waits for Apple's beta review, usually about a day.

TestFlight builds expire after 90 days, so testers need a newer one before then. They use Apple's
production push service; the app works that out from how it was signed (`PushRelay`).

## From GitHub Actions

The [TestFlight workflow](../../.github/workflows/testflight.yml) runs `scripts/testflight.sh` on a
GitHub macOS runner, signed in with an App Store Connect API key instead of an Xcode account.

- **By hand:** Actions › TestFlight › Run workflow, on `main`. Pick both apps or one, and turn off
  **Upload** to sign and export without uploading, which is the way to check a new key.
- **Each night:** set the repository variable `TESTFLIGHT_NIGHTLY` to `true` (Settings › Secrets and
  variables › Actions › Variables) once a run by hand has worked. A night with nothing new on `main`
  since the last nightly does nothing. Nightly builds keep the version in `Config/Shared.xcconfig`,
  so they reach internal testers right away; external testers still wait for beta review of each
  new version.

Its secrets live in the `testflight` environment, which only `main` may use:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The team ID |
| `APPSTORE_API_KEY_ID` | The API key's ID |
| `APPSTORE_API_ISSUER_ID` | The issuer ID shown above the team's keys |
| `APPSTORE_API_KEY_P8` | The contents of the key's `.p8` file |

Make a team key, not an individual one, under App Store Connect › Users and Access › Integrations ›
App Store Connect API, with the **Admin** role: Xcode uses it to make the distribution certificates
and profiles. Only the team's Account Holder and Admins see that section, and the Account Holder
has to request API access once before anyone can make a key. Set each secret
with `gh secret set <name> --env testflight -R usual-labs/usual-bot`, which reads the value from
standard input.

On a fresh runner Xcode makes a new Apple Development certificate whenever it signs, and Apple
limits how many a team may have. The workflow notes the team's certificates before it builds and
afterwards deletes only the development certificates that appeared during the run
(`scripts/app-store-certificates.swift`).

## When it fails

- **Signing errors in the archive or export**: Xcode isn't signed in to the team, or the account
  can't make distribution certificates. See setup step 3.
- **The Mac or iPhone upload is refused for an unknown app**: App Store Connect doesn't have that
  platform for the app yet. See setup step 2.
- **The build number is already used**: run the script again a minute later; it takes a new number
  each minute.
- **The workflow can't make certificates or profiles**: the API key's role is below Admin. Make a
  new key with the Admin role and replace the secrets.
