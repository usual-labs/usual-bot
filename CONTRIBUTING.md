# Contributing to Usual Bot

Thanks for helping. Bugs, polish, accessibility, translations and Hermes protocol support are all
welcome, and so are good bug reports.

Usual Bot aims to stay small: a messenger for your Hermes agents, not a second Hermes app.
Settings, skill setup and gateway administration belong in the official app, so changes that add
them here are unlikely to be merged. If you're unsure whether an idea fits, open a feature request
first and we'll talk it through before you write code.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug** with the bug report form. Include the app version, your Hermes version, Mac or
  iPhone, what you did and the exact message you saw.
- **Suggest a feature** with the feature request form. Say what you're trying to do, not only the
  solution.
- **Fix something.** Issues labelled `good first issue` are small and well described. Comment on
  one before you start so two people don't do the same work.
- **Improve the docs.** The guides in [docs/guides](docs/guides) should match what the app does;
  if they don't, that's a bug.

## Getting set up

1. Install **Xcode 26 or newer**.
2. Clone the repository and `open UsualBot.xcodeproj`.
3. Pick the **UsualBot** scheme and a Mac or iPhone simulator, and Run.
4. No gateway? Set `USUALBOT_DEMO=1` in the scheme's environment for a made-up team of agents
   ([how](docs/guides/getting-started.md#look-around-first-with-the-demo)).

To run on your own device or sign Mac builds, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` and set your team ID and a bundle prefix you own. The file is gitignored.

Before changing code, read the [architecture guide](docs/guides/architecture.md), then the
`AGENTS.md` and `docs/agents/` notes of the package you're touching:

| Package | What it owns |
| --- | --- |
| `Packages/HermesKit` | Sign-in, the WebSocket and JSON-RPC, and the app's state (`AppModel`, chats, rooms, routines). Foundation only, no UI. |
| `Packages/UsualUI` | The SwiftUI screens, shared by Mac and iPhone. |
| `App/` | The app target: sign-in presenters, the ⌥Space panel, the menu bar item, notifications. |

Those notes describe how each part works, its conventions and its known issues. Platform quirks
that have caught us before (the macOS 26 sidebar, the window toolbar, lazy scroll views, text
selection) are in `Packages/UsualUI/docs/agents/07-known-issues.md`. When your change alters
behaviour or you hit something non-obvious, update the notes in the same pull request.

## Making a change

- **Work on a branch** from `main`, named for the change, for example `fix-reconnect-loop`.
- **Keep it focused**: one change per pull request. Unrelated clean-ups go in their own.
- **Test the logic.** HermesKit's tests drive a scripted fake socket and HTTP transport
  (`Tests/HermesKitTests/Fakes.swift`), so most gateway flows can be tested without a gateway.
  Bug fixes should come with a test that failed before the fix.
- **Show it in the demo.** New features should appear in `AppModel.demo()` so reviewers can see
  them without a gateway.
- **Match the surrounding code.** `swift format` settles layout. Comments explain why, in plain
  sentences. Keep files focused; split one that grows past about 500 lines.
- **Write UI text plainly.** Say what happened and what to do next, in short sentences, without
  jargon. "Can't reach the gateway. Check that Tailscale is on." beats "Connection error (-1004)".
- **Mind accessibility.** Icon buttons need accessibility labels, and colours come from `Theme` so
  dark mode and contrast stay right.

### Commit messages

Write the subject as what the change does, in the imperative and in plain words: "Keep background
results after a reconnect", not "fix bug". Add a body when the reason isn't obvious from the diff.

## Before you open a pull request

Run the same checks as CI:

```sh
swift test --package-path Packages/HermesKit
swift test --package-path Packages/UsualUI
swift format lint --strict --recursive App Packages
```

and make sure the app builds for both platforms (Xcode, or the two `xcodebuild` lines in
`.github/workflows/ci.yml`).

In the pull request, describe the change and how you checked it. For UI changes, add screenshots
of the Mac and the iPhone (the demo is fine), in light and dark mode if colours changed. The pull
request template has a short checklist.

## Debug switches

Debug builds read these environment variables:

| Variable | What it does |
| --- | --- |
| `USUALBOT_DEMO=1` | Shows made-up agents instead of signing in. Never connects. |
| `USUALBOT_SHOW_QUICK_PANEL=1` | Opens the ⌥Space panel shortly after launch (Mac). |
| `USUALBOT_WINDOW_WIDTH=560` | Opens the main window at that width (Mac). |
| `USUALBOT_RECORD_FRAMES=1` | Appends every socket frame to `usualbot-frames.jsonl` in the app's temporary directory. |

Launch arguments set the stored UI choices for one run, which helps for screenshots:
`-selectedContact forge -showsProfile YES -sidebarWidth 300`.

## Keep private things out

- **Recorded frames hold real conversations.** Never commit a recording. To turn one into a test
  fixture, cut it down to the frames the test needs and replace names, messages, IDs and paths
  with made-up ones, as in `Tests/HermesKitTests/Fixtures`.
- Never commit tokens, real gateway addresses, or screenshots of real chats. Examples use
  `100.101.102.103` and `hermes.example.com`.
- Avatar design sources stay out of git except the files `.gitignore` allows; the app ships
  smaller copies in `Packages/UsualUI/Sources/UsualUI/Resources`.

## Reporting a security issue

Please don't open a public issue for anything that could expose someone's gateway, tokens or
conversations. Follow [SECURITY.md](SECURITY.md) instead.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
