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
5. The **update check** at `bot.usual.dev`, which tells TestFlight builds that a newer one is out:
   deploy [`Services/updates`](../../Services/updates/README.md) with an App Store Connect key. When
   the public link opens, set its `BETA_GROUP` to the external group, so the app offers only builds
   that passed beta review.

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

Within an hour of a build being processed, the app offers it to testers (`Services/updates`); there
is nothing to publish. TestFlight builds expire after 90 days, so testers need a newer one before then. They use Apple's
production push service; the app works that out from how it was signed (`PushRelay`).

## From GitHub Actions

The [TestFlight workflow](../../.github/workflows/testflight.yml) runs `scripts/testflight.sh` on a
GitHub macOS runner. It signs with certificates and profiles a maintainer made beforehand, and
uploads with an individual App Store Connect API key that can reach only Usual Bot, so nothing it
runs can make, change or revoke anything in the Apple account.

- **By hand:** Actions › TestFlight › Run workflow, on `main`. Pick both apps or one, and turn off
  **Upload** to sign and export without uploading, which is the way to check new certificates or
  profiles.
- **Each night:** set the repository variable `TESTFLIGHT_NIGHTLY` to `true` (Settings › Secrets and
  variables › Actions › Variables) once a run by hand has worked. A night with nothing new on `main`
  since the last nightly does nothing. Nightly builds keep the version in `Config/Shared.xcconfig`,
  so they reach internal testers right away; external testers still wait for beta review of each
  new version.

### Signing material

An Admin or the Account Holder makes these on a Mac, in the
[developer portal](https://developer.apple.com/account/resources/certificates/list):

1. **Two certificates**, the ordinary kind, not cloud-managed: **Apple Distribution**, which signs
   both apps, and **Mac Installer Distribution**, which signs the Mac package. Make each from a
   certificate signing request (Keychain Access › Certificate Assistant), so its private key stays
   in your keychain, then download and open it. One request can serve both.
2. **One `.p12`** holding both, with their private keys: in Keychain Access › login › My
   Certificates, select the two certificates, not the keys under them, choose File › Export Items,
   and give it a password. `/usr/bin/openssl pkcs12 -in Usual.p12 -nokeys | grep subject` should
   print both names.
3. **Four App Store profiles**, each using that Apple Distribution certificate:

   | Type | Bundle ID | Secret |
   | --- | --- | --- |
   | App Store Connect (iOS) | `labs.usual.UsualBot` | `PROFILE_IOS_APP` |
   | App Store Connect (iOS) | `labs.usual.UsualBot.NotificationService` | `PROFILE_IOS_NOTIFICATIONS` |
   | Mac App Store Connect | `labs.usual.UsualBot` | `PROFILE_MAC_APP` |
   | Mac App Store Connect | `labs.usual.UsualBot.NotificationService` | `PROFILE_MAC_NOTIFICATIONS` |

   The App IDs need Push Notifications on. The workflow reads each profile's name from the file, so
   name them as you like.

### The upload key

The key belongs to a user whose App Store Connect access is limited to Usual Bot (App Manager is
enough), so it can't touch the team's other apps. Individual keys can't make or download
certificates and profiles, which is why those are made beforehand.

1. An Admin lets that user generate an individual key, under Users and Access › People.
2. Signed in as that user, generate one under Users and Access › Integrations › Individual Keys,
   and download the `.p8`. Apple offers the download once.

### Secrets

They live in the `testflight` environment, which only `main` may use. Set each with
`gh secret set <name> --env testflight -R usual-labs/usual-bot`, which reads the value from
standard input; the files are base64 first, as in `base64 -i Usual.p12 | gh secret set SIGNING_P12 …`.

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The team ID, from Membership details in the developer account |
| `SIGNING_P12` | The `.p12`, base64 |
| `SIGNING_P12_PASSWORD` | Its password |
| `PROFILE_IOS_APP`, `PROFILE_IOS_NOTIFICATIONS`, `PROFILE_MAC_APP`, `PROFILE_MAC_NOTIFICATIONS` | The four profiles, base64 |
| `APPSTORE_API_KEY_ID` | The individual key's ID |
| `APPSTORE_API_KEY_P8` | The contents of its `.p8` file |

### Once a year

The certificates last a year, and a profile stops working when its certificate does. The workflow
fails 30 days before either expires and says which. Make new certificates and profiles as above,
replace `SIGNING_P12`, `SIGNING_P12_PASSWORD` and the four profile secrets, run the workflow by hand
with **Upload** off, then revoke the old certificates.

## When it fails

- **Signing errors in the archive or export**: Xcode isn't signed in to the team, or the account
  can't make distribution certificates. See setup step 3.
- **The Mac or iPhone upload is refused for an unknown app**: App Store Connect doesn't have that
  platform for the app yet. See setup step 2.
- **The build number is already used**: run the script again a minute later; it takes a new number
  each minute.
- **The workflow says a profile is for another app, lists devices, or expires soon**: replace that
  profile's secret with an App Store profile for the bundle ID it names.
- **The workflow says the `.p12` has no Apple Distribution or Installer certificate**: export it
  again with both certificates selected, as in step 2 of the signing material, and replace
  `SIGNING_P12` and `SIGNING_P12_PASSWORD`.
- **The workflow's export can't find a certificate or profile**: a profile was made with another
  Apple Distribution certificate.
