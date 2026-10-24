# Usual Bot: cross-project known issues

## Implemented today

- Native CI configuration is not evidence of a successful build or public release.
  CI runs on `macos-26`: the app uses the macOS 26 / iOS 26 SDK (Liquid Glass), which
  the `macos-15` image's Xcode can't compile. With no remote yet, CI has never run.

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
  prompt (README).
