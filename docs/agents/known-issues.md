# Usual Bot: cross-project known issues

## Implemented today

- There is no landing-site/blog implementation, canonical website origin or
  configured Git remote in the 23 October 2026 local inventory. The internal avatar
  HTML gallery is not a product landing page. A blog publication task cannot be
  completed by placing Markdown in this native tree; follow
  [blog-publishing.md](blog-publishing.md) for the missing prerequisites.
- Native CI configuration is not evidence of a successful build or public release.
  CI runs on `macos-26`: the app uses the macOS 26 / iOS 26 SDK (Liquid Glass), which
  the `macos-15` image's Xcode can't compile. With no remote yet, CI has never run.
- Status (23 October 2026): the published-facing text (README, CONTRIBUTING) is current,
  and its screenshots come from the debug demo (`USUALBOT_DEMO=1`), not real chats. The
  history was rewritten before the first push so that no commit contains the
  maintainer's tailnet IP or tailnet name; tests and comments use Tailscale's example
  address `100.101.102.103`. Release `v0.1.0` is tagged locally only.

For new issues record symptom → source-supported cause → verified fix or explicitly
unverified recommendation → prevention and status.
