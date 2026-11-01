# Changelog

All notable changes to Usual Bot are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- **Settings.** Choose appearance, chat text size, notification sounds and previews, and voice
  preferences. See the gateway connection and sign out. On Mac, set launch at login and Return or
  ⌘Return to send, and record, disable or restore the Quick Message keyboard shortcut. Open
  Settings with ⌘, on Mac or the gear beside the connection indicator on either platform.

- **Sections.** Group your Bots and rooms in the sidebar. Right-click a chat on the Mac, or touch and
  hold it on iPhone, to move it to a section, or on the Mac drag it to one. Click a heading to fold
  it; a folded section still shows anything that needs you. A Bot's section is saved on the Bot, so
  the Hermes desktop app sees the same groups.
- **Secret and sudo prompts.** When a skill needs a secret or a command needs your sudo password,
  a card in the chat asks for it in a masked field. Send it or skip it. On a gateway using plain
  http away from this device, the card warns you first and the button says Send Unencrypted.
- **Credential vault.** A Bot's profile has a Vault tab: see what's saved (never the secrets), add
  logins, cards and addresses, remove them, and switch on, unlock or lock password managers on the
  gateway. In a chat, cards ask for a master password, a login to save or a one-time code, and you
  can skip any of them. On a plain http gateway away from this device and outside Tailscale, nothing
  secret is sent until you tick "Send it anyway" for that send.
- **Vault filters.** The Vault tab sorts what's saved into All, Logins, Payments and Addresses, with
  a count on each, and New item asks what you're adding.

### Changed

- **A new look for chats.** Replies sit in bubbles, messages are grouped, and text is a little
  larger on the Mac. Your messages take the Bot's colour, and so do its voice and send buttons. Cards
  that ask for something share one shape, and a question's choices are lettered A, B, C. Colours are
  plainer neutrals, with solid surfaces where there was glass.
- **See what a Bot is doing.** While it works, a small avatar and a moving line of text say what
  it's up to: "Reading", "Running a command". The same line shows in rooms and the ⌥Space panel. It
  replaces the typing dots, and a working avatar moves gently instead of wearing a ring.
- **Messages arrive with a small animation,** which Reduce Motion turns off. On the Mac, the message
  box stays one line until your text wraps, and a message's actions sit right beside it.

### Fixed

- **Background work no longer looks like your messages.** When a background process or subagent
  finished, Hermes's note appeared as a long message from you, and in the sidebar. It's now one line
  you can open for the details. Undo and Edit act on your own last message instead of that note.
- **The sidebar stays at the window's edge.** On the Mac, with no chat open, the list sat away from
  the left edge with an empty strip beside it.
- **The end of a chat stays in view.** A new message, a card asking for something or the background
  task bar could land under the message box until you scrolled. A chat now follows its end unless
  you've scrolled away.
- **Secret and sudo requests.** Usual Bot used to decline these. With no other app attached, Hermes
  then took its error text for your answer: it saved that text as the secret, so the skill never
  asked again, and passed it to `sudo` as the password. If a skill has misbehaved since, check its
  variable in the profile's `.env` for a JSON error and remove it.
- **Side questions after a reconnect.** A `/btw` question or `/bg` task sent right after a chat
  reconnected could show as lost, even though the gateway had it.
- **Mac tab bar.** Window tabs are off, so View no longer offers Show Tab Bar and the tab bar can't
  cover the top of the window.

## 0.3.0 - 2026-10-26

### Added

- **Bot pictures.** A Bot that has a picture in the Hermes app (uploaded or generated there) shows
  it in Usual Bot too. Bots with a drawn face or no picture keep Usual Bot's own characters.
- **Homebrew.** Install with `brew install --cask usual-labs/tap/usual-bot`, and update with
  `brew upgrade --cask usual-bot`.
- Release downloads carry a build-provenance attestation: `gh attestation verify` shows the
  workflow and commit a disk image came from.

### Changed

- The sign-in screen and the Mac's About box say Usual Bot is an independent app, not made by or
  affiliated with Nous Research. Release notes say so too.
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

