# Usual Bot

A native Mac and iPhone client for [Hermes Agent](https://github.com/NousResearch/hermes-agent).
Your Hermes profiles show up as contacts in a simple messenger: one ongoing chat per agent,
group rooms, inline approvals and routines. Everything else stays in the official Hermes app.

> Early work in progress. The app currently shows sample contacts; connecting to a gateway is next.

## Build

Requirements: Xcode 16 or newer (macOS 15+ / iOS 18+ targets).

```sh
open UsualBot.xcodeproj
```

Pick the **UsualBot** scheme and a Mac or iPhone simulator, then Run. Unsigned and simulator builds
need no setup. To run on your own device, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` and set your team ID and bundle prefix (the file is gitignored).

Without a team, Mac builds are signed "to run locally", and every rebuild looks like a new app to
the Keychain: macOS asks once per build whether Usual Bot may read its saved sign-in. Choose
**Always Allow**, or set your team to make the prompt go away.

## Layout

| Path | What lives there |
| --- | --- |
| `Packages/HermesKit` | Gateway connection, protocol types and state. No UI, no dependencies. |
| `Packages/UsualUI` | Shared SwiftUI screens for Mac and iPhone. |
| `App/` | The thin app shell and platform-only pieces. |
| `Config/` | Build settings (`.xcconfig`) and entitlements. |

## Checks

```sh
swift test --package-path Packages/HermesKit
swift test --package-path Packages/UsualUI
swift format lint --strict --recursive App Packages
```

CI runs the same checks and builds both platforms on every pull request.

## License

Apache-2.0. See [LICENSE](LICENSE).
