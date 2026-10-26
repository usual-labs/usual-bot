# Changelog

All notable changes to Usual Bot are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- **Homebrew.** Install with `brew install --cask usual-labs/tap/usual-bot`, and update with
  `brew upgrade --cask usual-bot`.
- Release downloads carry a build-provenance attestation: `gh attestation verify` shows the
  workflow and commit a disk image came from.

### Changed

- **iPhone message box.** It's larger and sits lower. While you type, your text gets its own row and
  the buttons a row below it, with the context ring and a gauge for the model and thinking: the
  gauge opens a level slider, and the model name opens the full model and thinking settings. The
  row of menus under the box is gone on iPhone; the Mac is unchanged. The box no longer opens the
  keyboard by itself when a chat opens, and scrolling the conversation puts the keyboard away.

## 0.2.0 - 2026-10-25

### Added

- **Attachments.** Send images, PDFs and other files: paperclip, drag and drop or paste on the Mac;
  Photos, camera or Files on iPhone.
- **Images in replies.** Images an agent makes or names show inline, open full size, and can be
  shared or saved.
- **React, reply and copy** on any message.
- **Skills and commands.** Type `/` anywhere in a message for the agent's skills and Hermes
  commands; skills can be switched on and off in the agent's profile.
- **Dictation** with the mic in the message box, recognised on the device when it can.
- **Voice calls** with an agent, using on-device speech or Hermes's GPT-Live voice.
- **Model and thinking** menus for each chat, with **Make Default** to save them for the agent.
- **Edit and undo** your last message.
- **Side questions** with `/btw`, answered without interrupting the agent.
- **Background tasks** with `/bg`, with a notification when one finishes.
- **Context meter** with a button to compress the conversation.
- **Catching up after a dropped connection**: missed replies, background results and side answers
  are recovered, or the chat says when they can't be.
- **Rooms**: the `/` menu for members' skills, and a members panel.
- **App icon, launch screen and sign-in mark** from the Hermes doodle.
- Guides for getting started, using the app, troubleshooting and the architecture; a security
  policy, code of conduct, and issue and pull request templates.
- **A signed, notarized Mac download.** Each release on GitHub has a disk image built by a
  release workflow; released apps use the bundle ID `labs.usual.UsualBot`.

### Fixed

- Picking from the `/` menu left the cursor in the middle of the word.

## 0.1.0 - 2026-10-23

The first version.

### Added

- Browser sign-in to a Hermes dashboard gateway, with tokens in the Keychain.
- Each Hermes profile as a contact with its ongoing chat: streaming replies, Markdown, tool calls
  folded into one line, and a typing indicator.
- Inline approvals and questions; stopping and steering a running reply.
- "Working" and "Needs you" markers in the sidebar, unread counts and an offline cache.
- Rooms: group chats with several agents, `@` mentions and room approvals.
- Each agent's profile with its routines (pause and resume) and machine details.
- The ⌥Space quick message panel and menu bar item on the Mac.
- iPhone layouts, with reconnecting after the app returns from the background.
- A demo mode (`USUALBOT_DEMO=1`) with made-up agents.

