# Usual Bot: cross-project known issues

## Implemented today

- Native CI configuration is not evidence of a successful build or public release.
  CI runs on `macos-26`: the app uses the macOS 26 / iOS 26 SDK (Liquid Glass), which
  the `macos-15` image's Xcode can't compile. With no remote yet, CI has never run.

For new issues record symptom → source-supported cause → verified fix or explicitly
unverified recommendation → prevention and status.
