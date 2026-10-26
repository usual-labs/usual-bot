# Usual Bot: workspace structure

## Implemented today

- `Packages/HermesKit/` — Gateway auth, transport and domain state
- `Packages/UsualUI/` — Native screens and reusable UI

- `App/UsualBotApp.swift` — application entry
- `App/SignInPresenters.swift` — browser/web-auth presenters
- `App/Assets.xcassets` — the app icon (`AppIcon`), the iPhone launch image (`LaunchMark`) and its
  background (`LaunchBackground`)
- `.github/workflows/ci.yml` — lint, both test suites, Mac and iOS Simulator builds on pushes and PRs
- `.github/workflows/zizmor.yml` — zizmor security lint of the workflows (pushes/PRs touching
  `.github/`), findings in code scanning; `.github/workflows/scorecard.yml` — OpenSSF Scorecard
  weekly and on pushes to main, publishes the README badge; `.github/dependabot.yml` — weekly grouped
  updates of the pinned actions (7-day cooldown); `.github/workflows/codeql.yml` — CodeQL for Swift
  (xcodebuild of the app on `macos-26`, manual build mode) and Actions, on pushes, PRs and weekly.
  A package-only SwiftPM scan misses `App/`; the tracked workflow builds the app with Xcode
- `.github/workflows/release.yml` — on a `v*` tag: Developer ID signed, notarized Mac `.dmg` on a
  GitHub release, with the version's CHANGELOG section (required) as notes. Self-contained: the
  notes extraction and the notarize-and-staple helper are inline. Setup and secrets:
  `docs/guides/releasing.md`. The Homebrew cask (`brew install --cask usual-labs/tap/usual-bot`)
  lives in the separate public repo `usual-labs/homebrew-tap` (local checkout
  `../homebrew-tap/`); nothing bumps it automatically, so release step 5 does it by hand
- `Config/Shared.xcconfig` — shared Xcode settings
- `UsualBot.xcodeproj` — application project
- `design/avatars` — avatar reference and artwork
- `docs/guides/` — user and contributor guides (getting started, user guide, troubleshooting,
  architecture), linked from the README; `docs/screenshots/` — demo-mode screenshots they use
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`,
  `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` — open-source project files.
  When behaviour changes, update the matching guide and the changelog's Unreleased section.

The `design/avatars/2026-10-24-hermes/` folder holds the Hermes doodle (a monochrome-doodle take
on the official Hermes app icon's headphone character), its prompt, source attribution and alpha
verification. It is the app's icon character: the app icon, the iPhone launch screen and the
sign-in/splash mark are made from it. The full-size PNG and
local reference files follow the design asset ignore rules; the generated, smaller copies in the
app and UsualUI are tracked. The copies of Nous Research's official icon (`references/`) were never
committed and must stay out of git: the repository holds only our drawing.

Do not treat generated copies, dependencies, fixtures, archives or sample snippets as independent shipped products. Their semantics remain with their owning source project.
