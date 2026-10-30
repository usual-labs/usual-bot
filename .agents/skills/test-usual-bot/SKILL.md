---
name: test-usual-bot
description: See a Usual Bot change working in the real app, on the Mac or the iOS Simulator, using the made-up demo agents. Use to verify UI or behaviour after a change, or to take screenshots.
---

# Test Usual Bot

Use the demo. It shows made-up agents, chats, a room, an approval and routines, and never connects.
Use a real gateway only when the change depends on gateway behaviour and the developer agrees: its
agents, models and skills are real.

## Mac

Build into the gitignored `build/` folder, so this build doesn't stack up beside others:

```sh
xcodebuild build -quiet -project UsualBot.xcodeproj -scheme UsualBot \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
USUALBOT_DEMO=1 build/DerivedData/Build/Products/Debug/UsualBot.app/Contents/MacOS/UsualBot \
  -selectedContact forge
```

Capture the PID you started, and stop only that one. Launch arguments set stored UI choices for one
run: `-selectedContact forge -showsProfile YES -sidebarWidth 300`. Other switches are in
`CONTRIBUTING.md` under Debug switches.

## iPhone

If your harness has device tools, use them. Build for the simulator with
`-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`, install the app and launch it with
`USUALBOT_DEMO=1` in its environment (`SIMCTL_CHILD_USUALBOT_DEMO=1` with `simctl launch`).

## What to look at

Walk the surfaces in `AGENTS.md` and say which applied. Screenshot the state that proves the change,
in light and dark if colours changed. Upload pull request evidence to GitHub; don't commit it.

## What the demo can't show

- A thinking level change: `ChatThread.setReasoning` needs a live session, so the slider snaps back.
- Dictation in the Simulator, which has no speech model. Use the Mac or a device.
- Menu items added by AppKit before the menu opens. Open the menu, then check it.
- Privacy prompts with several builds of one bundle ID around
  (`Packages/UsualUI/docs/agents/07-known-issues.md`).
