# Releasing

For maintainers. Pushing a version tag runs [`.github/workflows/release.yml`](../../.github/workflows/release.yml),
which builds the Mac app, signs it with the team's **Developer ID**, has Apple **notarize** it, and
publishes a GitHub release with `UsualBot-<version>.dmg` and its SHA-256 checksum. Because it's
signed and notarized, the app opens without any Gatekeeper warning.

The iPhone app isn't released this way: GitHub can't install apps on iPhones. That would go
through TestFlight later.

## One-time setup

You need a **paid Apple Developer Program membership**, and the **Account Holder** has to create the
certificate. Everything below goes into the repository's secrets, and nothing is stored in git.

### 1. A Developer ID Application certificate

In Xcode: **Settings › Accounts**, select your Apple Account, select the team, click
**Manage Certificates…**, then **+** › **Developer ID Application**. Xcode creates it with its
private key in your login keychain. (Or create it at developer.apple.com › Certificates, IDs &
Profiles › Certificates › **+** › **Developer ID Application**, with a signing request from
Keychain Access.)

A Developer ID certificate lasts five years. Apps signed with it keep working after it expires,
but new releases need a new certificate (and new secrets).

### 2. An App Store Connect API key, for notarization

1. Go to [App Store Connect](https://appstoreconnect.apple.com) › **Users and Access** ›
   **Integrations** › **App Store Connect API** › **Team Keys**, and click **+**.
2. Name it "Usual Bot notarization" and give it the **Developer** role.
3. Download the key, `AuthKey_<KEY ID>.p8`. Apple lets you download it **only once**.
4. Note the **Key ID** (in the list) and the **Issuer ID** (above the list).

### 3. The repository secrets

Export the certificate: in **Keychain Access**, open **login › My Certificates**, right-click
"Developer ID Application: *your name* (*TEAM ID*)", choose **Export…**, and save it as
`DeveloperID.p12` with a strong password. Exporting from **My Certificates** brings the private
key along.

Then set six secrets under the repository's **Settings › Secrets and variables › Actions**, or
with the GitHub CLI (each command without a file asks for the value, so it stays out of your shell
history):

```sh
base64 -i DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12 -R usual-labs/usual-bot
gh secret set MACOS_CERTIFICATE_PASSWORD -R usual-labs/usual-bot
gh secret set APPLE_TEAM_ID -R usual-labs/usual-bot
gh secret set APPSTORE_API_KEY_P8 -R usual-labs/usual-bot < AuthKey_XXXXXXXXXX.p8
gh secret set APPSTORE_API_KEY_ID -R usual-labs/usual-bot
gh secret set APPSTORE_API_ISSUER_ID -R usual-labs/usual-bot
```

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | The exported `.p12`, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The password you gave the `.p12` |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPSTORE_API_KEY_P8` | The contents of the `.p8` file |
| `APPSTORE_API_KEY_ID` | The key's Key ID |
| `APPSTORE_API_ISSUER_ID` | The Issuer ID |

Afterwards, delete `DeveloperID.p12`, and keep the `.p8` somewhere safe, such as a password
manager. If the certificate or the key leaks, revoke it (the certificate at
developer.apple.com, the key in App Store Connect) and make new ones.

## Making a release

1. **Check CI is green** on the commit you want to release.
2. **Update the changelog.** Rename `## Unreleased` in `CHANGELOG.md` to the version and date,
   for example `## 0.2.0 - 2026-11-02`, and add a fresh empty `## Unreleased` above it. The
   workflow uses that section as the release notes, and stops if it's missing.
3. **Commit, tag and push:**

   ```sh
   git commit -am "Release 0.2.0"
   git tag v0.2.0
   git push origin main v0.2.0
   ```

4. **Watch the run** under **Actions › Release**. It takes about 10–20 minutes, mostly waiting for
   Apple's notary service. The release appears under **Releases** when it's done.

To try the pipeline without a real release, push a pre-release tag such as `v0.2.0-rc.1`. It uses
the `0.2.0` notes and is marked as a pre-release; delete the release and the tag afterwards if you
don't want to keep them.

## What the workflow does

1. Checks the tag (`v1.2.3` or `v1.2.3-rc.1`), the changelog section and that every secret is set.
2. Imports the certificate into a temporary keychain on the runner.
3. Archives a Release build for Apple silicon and Intel. The app's version comes from the tag, its
   build number from the run number, and its bundle ID is `labs.usual.UsualBot`. Changing the bundle
   ID later would make the app look new to macOS, so people would have to sign in again.
4. Exports the app signed with Developer ID and the hardened runtime, and checks the signature.
5. Notarizes the app and staples the ticket to it, so it opens even offline.
6. Puts it in a disk image with a shortcut to Applications, signs, notarizes and staples that too,
   and checks it with Gatekeeper (`spctl`).
7. Publishes the GitHub release with the notes, the `.dmg` and its `.sha256`.
8. Deletes the temporary keychain and key file, even when a step failed.

## When it fails

- **"Missing repository secrets"**: one of the secrets above isn't set. The message names it.
- **"CHANGELOG.md has no … section"**: the changelog section is missing, or its heading doesn't
  start with `## <version>`.
- **Signing errors in Archive or Export**: the `.p12` is probably missing its private key (export the
  certificate from **My Certificates**, not **Certificates**), or the password is wrong.
- **Notarization "Invalid"**: the step prints Apple's log, which names the file and the problem.
  Fix it, delete the tag (`git push --delete origin v0.2.0` and `git tag -d v0.2.0`), and tag again.
- **401 or 403 from the notary service**: the API key, Key ID or Issuer ID doesn't match, the key
  was revoked, or its role is too low (make a key with the **App Manager** role instead).
