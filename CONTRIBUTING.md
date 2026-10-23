# Contributing to Usual Bot

Thanks for helping. Usual Bot aims to stay small: a messenger for your Hermes agents, not a second
Hermes app. Settings, skills and setup belong in the official app, so changes that add them here
are unlikely to be merged. Bugs, polish, accessibility and protocol support are always welcome.

## Getting set up

1. Install Xcode 26 or newer.
2. `open UsualBot.xcodeproj`, pick the **UsualBot** scheme and a Mac or iPhone simulator, and Run.
3. No gateway? Set `USUALBOT_DEMO=1` in the scheme's environment to get a made-up team of agents.
   See [Try it without a gateway](README.md#try-it-without-a-gateway).

To run on your own device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set
your team ID and a bundle prefix you own. The file is gitignored.

## Where things live

- `Packages/HermesKit`: talking to the gateway (sign-in, the WebSocket, JSON-RPC) and the app's
  state (`AppModel`, chats, rooms, routines). Foundation only, no UI.
- `Packages/UsualUI`: the SwiftUI screens, shared by Mac and iPhone.
- `App/`: the app itself, sign-in presenters and the Mac's ⌥Space panel and menu bar item.

Each package has an `AGENTS.md` and `docs/agents/` notes: how it works, its conventions and its
known issues. Read the relevant ones before changing a package, and update them in the same pull
request when behaviour changes or you hit something non-obvious. Platform quirks that have caught
us before (the macOS 26 sidebar, the window toolbar, lazy scroll views) are in
`Packages/UsualUI/docs/agents/07-known-issues.md`.

## Before you open a pull request

```sh
swift test --package-path Packages/HermesKit
swift test --package-path Packages/UsualUI
swift format lint --strict --recursive App Packages
```

CI runs these and builds the app for macOS and the iOS Simulator. For UI changes, add a screenshot
of the Mac and the iPhone (the demo mode is fine), in light and dark mode if colours changed.

- Keep pull requests focused: one change, with tests where the logic can be tested. HermesKit's
  tests drive a fake socket and a scripted HTTP transport (`Tests/HermesKitTests/Fakes.swift`).
- Match the surrounding code: `swift format` settles layout, and comments explain why, in plain
  sentences.
- UI text is plain and short. Say what happened and what to do next, without jargon.

## Debug switches

Debug builds read these environment variables:

| Variable | What it does |
| --- | --- |
| `USUALBOT_DEMO=1` | Shows made-up agents instead of signing in. |
| `USUALBOT_SHOW_QUICK_PANEL=1` | Opens the ⌥Space panel shortly after launch (Mac). |
| `USUALBOT_WINDOW_WIDTH=560` | Opens the main window at that width (Mac). |
| `USUALBOT_RECORD_FRAMES=1` | Appends every socket frame to `usualbot-frames.jsonl` in the app's temporary directory. |

## Keep private things out

- **Recorded frames hold real conversations.** Never commit a recording. To turn one into a test
  fixture, cut it down to the frames the test needs and replace names, messages, IDs and paths
  with made-up ones, as in `Tests/HermesKitTests/Fixtures`.
- Never commit tokens, gateway addresses that aren't examples, or screenshots of real chats.
- Avatar design sources stay out of git except the files `.gitignore` allows; the app ships
  256 px copies in `Packages/UsualUI/Sources/UsualUI/Resources/Avatars`.

## Reporting a security issue

Please don't open a public issue for anything that could expose someone's gateway or sign-in.
Report it privately through the repository's **Security › Report a vulnerability** page.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
