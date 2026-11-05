# Changelog

All notable changes to Usual Bot are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- **See where tokens go.** Settings › Usage shows your Bots' tokens over the last 7, 30 or 90 days by day and by Bot, what was written, sent new or sent again, the background work beside your chats, and the cost when Hermes knows it.
- **Connect apps from the chat.** When an agent needs an account such as Gmail, or an MCP server's sign-in, a card offers Connect and Not now, opens the sign-in page, and updates once you're done. The Apps page lists the accounts Hermes reaches through your Nous Portal, with Connect and Disconnect.
- **Watch an agent's computer and take over.** An agent with a computer of its own shows a Computer
  button in its chat: watch its screen live, take over the mouse and keyboard, and hand it back.
- **Audio and video in chats.** Voice replies play as voice memos with their transcript, and audio files and videos play in chats and rooms, with Share and Save kept.
- **Make and change Bots.** **+** › **New Bot…** makes a Bot from a name, an optional picture and
  what it's for. Rename a Bot, change its picture or delete it from its profile or its menu in the
  sidebar. Deleting asks you to type its name first.
- **Search your messages.** Type two or more letters in search (⌘K on the Mac, the list's search
  field on iPhone) to find messages from every chat and room, with the words you typed in bold.
  Choose one to open that chat at the message, highlighted for a moment.
- **Search older messages on the gateway.** When a Bot's chat isn't loaded yet, search asks the gateway too and adds its match, marked Earlier; opening it loads the chat and goes to the message. Each result now says when it was said.
- **Dates in chats.** A date sits above the first message, and again after a new day or a quiet
  hour, in chats and rooms. Hover a message on the Mac for its time, or long-press it on iPhone.
- **Routine templates.** New Routine offers the gateway's templates, like a morning briefing or a price watch: answer a few questions and it's set up, with a note if it needs a skill the agent lacks.
- **Manage routines.** Create, edit, delete and run an agent's routines from its profile, and read
  each one's past runs. Schedules read in plain words, a failed run says why, and results can post
  in the chat or stay in past runs.
- **See what the agent is doing.** A chat shows the agent's to-do list and any helpers it hands work
  to, each as one line you can open. The working line also says when the agent waits on its provider
  or compresses the conversation, and how far a long step has got. Notices from Hermes, such as a
  switch to a fallback model, appear in the conversation.
- **Rename and delete rooms.** From a room's panel or its menu in the sidebar. Deleting a room is
  permanent and asks first.
- **Try again in rooms.** A room reply that stopped partway now offers Try Again, and the room shows
  Needs you until you use it.
- **Notifications.** Hear when an agent replies, messages you or needs you, in chats and rooms, not
  just when a background task ends. A chat you're reading stays quiet; any other alerts, even while
  you're in the app. Tapping one opens that chat, and it clears once you've read it.
- **Push on Mac and iPhone.** With the `usual-push` plugin on your gateway, every device you sign in
  on hears from your Bots instantly, even with Usual Bot closed, under Usual Bot's own name. Each
  notification is sealed for that device, so Usual's relay and Apple can't read it. Reading a chat
  on one device quiets it on the others, and you can turn any Bot off per device.
- **Unread counts on the Mac** now also count replies that arrive while the window is behind another
  app.
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
- **Apps.** A Bot's profile has an Apps tab for its MCP servers: switch them on and off, see their
  tools, add one from Hermes's catalog or by address or command, sign in to ones that use their
  provider's page, test the connection and remove them. Keys and tokens go to the gateway and aren't
  kept on the device. Changes reach the Bot's next session, or apply them to the open chat at once,
  which makes its next reply cost more.
- **Vault filters.** The Vault tab sorts what's saved into All, Logins, Payments and Addresses, with
  a count on each, and New item asks what you're adding.
- **Built-in Tailscale on iPhone.** Reach a gateway on your tailnet with the Tailscale VPN off: turn
  on Built-in Tailscale on the connect screen or in Settings under your gateway, and sign in to
  Tailscale once. The app then joins your tailnet as a device of its own. A gateway that signs in
  through Google still needs the VPN for that sign-in, since Google doesn't allow it inside apps.

- **Jump to the newest message.** After you scroll up, a round arrow above the message box takes you
  back to the end, with a dot when something new arrived.
- **Right-click a message on the Mac** to react, reply, copy, edit or undo. VoiceOver offers the same
  actions on both platforms, and says who wrote each message.
- **Every reaction on iPhone,** behind More Reactions, and **Select Text** in a message's menu to copy
  part of it.
- **Menu bar commands on the Mac.** File › New Bot… (⌘N) and New Room… (⇧⌘N), View › Show Profile
  (⌘I) and Collapse Sidebar (⌃⌘S), a Go menu with Search… (⌘K) and Previous/Next Chat (⌃⇧⇥/⌃⇥),
  and Help › Usual Bot Help. The narrow sidebar rail has a Search button. ⌘. stops a running reply.
- **Room details on iPhone.** Tap a room's name to see its members, rename it or delete it.
- **Dismiss a stopped room reply.** The card names the Bot when the app can tell, and Dismiss stops
  it on the gateway, along with any other reply still running in the room.
- **Rooms name themselves.** Leave the name blank and a new room is called after its Bots, like
  "Forge, Atlas & Scribe".
- **VoiceOver announces** approval, question, secret, vault and Connect cards as they appear, and a
  message found by search.

### Changed

- **Usual Bot ships through TestFlight, on the Mac and the iPhone,** with push. The Homebrew cask and
  the GitHub download stop at 0.3.0; the README links the TestFlight beta once it's open to all.
- **The system's own controls and Liquid Glass, on Mac and iPhone.** The chat's top bar, its
  buttons, the message box, the jump-to-latest button and the call bar float in glass; the chat
  list, profile pages, Settings and sign-in are the system's lists and forms; cards and sheets use
  the system's buttons and fields. Bubbles, avatars and the Bot's colour on your messages and Send
  stay. On the Mac, Settings opens in the standard Settings window, and the ⌥Space panel is glass.
- **On iPhone, a Bot's Computer button sits at the top right,** beside "…", which holds View
  Profile and Voice Call. Sheets put ✕ at the top left and the main button at the top right.
- **Usual Bot now needs macOS 26 and iOS 26,** for the system's own controls and Liquid Glass.
  It also no longer fails to open on iOS 18.
- **Search is now a palette.** ⌘K or the Search button finds chats and rooms, and opens New Room,
  Settings or a theme. It replaces the filter at the top of the sidebar on the Mac.
- **You can tell what's clickable.** On the Mac the pointer becomes a hand over buttons, chats,
  menus and the rest of what answers a click.
- **A calmer sidebar.** An agent that needs you shows a dot on its avatar, and rows on the Mac no
  longer show a time, so previews keep their space. The sidebar has a button to collapse it, and chats not in a
  section are listed under Other.
- **More room for a conversation.** On the Mac the conversation and message box can use more of the
  window, and New Room, Settings and an agent's profile match the rest of the app. An agent's Hermes
  profile moved to the Machine tab.
- **A new look for chats.** Replies sit in bubbles, messages are grouped, and text is a little
  larger on the Mac. Your messages take the Bot's colour, and so do its voice and send buttons. Cards
  that ask for something share one shape, and a question's choices are lettered A, B, C. Colours are
  plainer neutrals, with solid surfaces where there was glass.
- **See what a Bot is doing.** While it works, a small avatar and a moving line of text say what
  it's up to: "Reading", "Running a command". The same line shows in rooms and the ⌥Space panel. It
  replaces the typing dots, and a working avatar moves gently instead of wearing a ring.
- **iPhone looks more like a phone messenger.** The chat list shows each chat's last time,
  without lines between rows, and a section's arrow sits beside its
  name; touch and hold a heading for its options. The settings gear sits at the top with a
  connection dot, Settings leads with your gateway, and a chat's **…** button opens the profile or
  starts a call. An agent's profile opens as a page from the chat, with a row for each of
  Routines, Skills, Apps, Vault and Machine and what's in it. In a chat, messages fade and blur softly under the top
  buttons and behind the message box (on iOS 26 and later), the box floats in from the sides, and
  the agent's messages leave room on the right.
- **Answer a question in the message box.** A question with one answer gets a lighter card: tap a
  choice, or type your answer below, where the box says "Answer" plus the agent's name. Elsewhere the
  box says "Ask" plus the agent's name.
- **Messages arrive with a small animation,** which Reduce Motion turns off. On the Mac, the message
  box stays one line until your text wraps, and a message's actions sit right beside it.

- **iPhone follows the system text size.** The chat list, chats, cards, the message box, profiles,
  sheets and settings grow with it, with the in-app chat text size on top. At the largest sizes,
  rows wrap instead of cutting text off, and the message box gives your text the full width.
- **The app says "Bot" everywhere** for the agents you chat with, matching New, Rename and Delete Bot.
- **Sheets look and work the same everywhere.** On iPhone, Cancel and the main action sit in the
  bar; on the Mac, Esc cancels and Return confirms. Start from scratch in New Routine has Back.
- **Approval buttons say what they cover,** and Always allow no longer sits next to Deny.
- **Signing out asks first,** on the Mac and iPhone.
- **A voice call ends with ⇧⌘H** instead of Esc, and its dots stay still with Reduce Motion on.
- **Quick message waits** for a chat that's still opening and sends then, or says why it can't.
  Waiting on you also lists room replies to try again and apps to connect.
- **A message you send while a card waits,** and its reply, come after the card, in view.
- **Settings use the app's ink,** and switches are easier to see in dark mode. Push settings label
  their fields, and the Notifications page says up top when notifications are off.
- **The demo shows idle, unread and working Bots,** not only ones that need you.

### Fixed

- **Long chats open and resize faster.** A chat or room builds its newest messages and adds earlier
  ones as you scroll up to them, keeping your place, instead of laying out its whole history on
  every open and every step of a window resize. Replies are no longer parsed again on each update,
  and the Mac's Skills page builds only the skills in sight. On the Mac, a reply's paragraphs
  select together, and pointing at messages no longer slows a long chat down.
- **Small controls and cards.** The context, model and thinking controls under the message box are
  easier to read and click, and VoiceOver stops on each once. A short card in a chat no longer
  drifts away from its edge. Windows behind others no longer react as the pointer passes.
- **Messages sent from another device** now appear in a chat you have open on this one, once the
  reply finishes, instead of only after reopening the app.
- **Chats no longer drift into blank space.** Conversations use measured message heights and keep
  their scroll position within the content after layout changes and returning from another app.
  Scrolling up still lets you read older messages without new replies pulling you to the end.
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

- **Narrow Mac window with a panel open.** The window makes room for the profile or room panel
  instead of cutting off the sidebar and the chat.
- **A chat's row in the list** shows your message as soon as you send it, and the reply when it
  comes. Rows no longer shift when an unread count appears.
- **A room message that doesn't send** goes back in the message box instead of being lost.
- **Delete Bot** says when the Bot is waiting on you rather than replying, and its Delete is red.
- **Text at the top of a Mac chat** no longer shows beside the name.
- **A message found by search** stands out in light and dark.
- **Small iPhone controls** have 44 pt tap areas, and a question's letters no longer look like keys.
- **VoiceOver** can open an image you sent and Start from scratch or a routine template, says when a
  Bot is working and what a folded section needs, reads each iPhone section heading as one element,
  and names the menu bar item Usual Bot.
- **Grey boxes** around the +, New item, More and gateway menus on the Mac are gone.
- **The empty list offline** says it can't reach your gateway, with Try Again, instead of
  "Connecting…".
- **An app's problem shows in full,** and template summaries get two lines on iPhone. The connect
  screen scrolls, and New Room says why Create is off.
- **On iPhone, renaming a section** uses the heading's size and has Cancel, and the profile's Machine
  row says Needs you while the Bot waits on you.

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

