# Changelog

All notable changes to Usual Bot are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

Changes that aren't in a release yet are in the
[merged pull requests](https://github.com/usual-labs/usual-bot/pulls?q=is%3Apr+is%3Amerged+sort%3Aupdated-desc),
each under its **Changelog** heading.

## 0.6.0 - 2026-11-27

### Added

- **Reply to part of a message, point by point.** Select some words and choose **Reply** (the button
  over the selection or ⌘L on the Mac, Select Text on iPhone) to answer just those words. Add as
  many as you like, from any messages: they go as one message, each quote with your answer under it.
  Click or tap a waiting quote to change your answer, or press Return without typing to send the
  quotes as they are. An answer can run to several lines, and one you've started stays in the chat's
  draft when you switch chats or quit.
- **Queue a message for when the reply ends.** While a Bot is replying, choose **Queue** beside Send
  (⌥Return on the Mac) and your message, files included, is sent by itself once the reply ends.
  Queued messages wait above the message box, where you can edit, send now or remove each one. Stop
  holds them until you choose **Resume**. Needs the gateway's Webapp; on the older dashboard a
  message steers, as before.
- **Edit any message of yours, and Try Again.** Edit used to work on your last message only. Now
  sending an edit to an earlier one replaces it and everything after it with a fresh answer; the app
  shows what will go and asks first when that's more than the last exchange or the Bot acted in it.
  Files the Bot changed and commands it ran stay as they are. **Try Again** on the Bot's last reply
  asks your message again for a different answer. While a reply runs, or offline, Edit and Undo stay
  in the menu, greyed out with the reason.
- **A file viewer.** Images, PDFs and Markdown files in a chat or room open beside the conversation:
  on the Mac's right, where the profile opens, and as their own page on iPhone, with Share (and Save
  on the Mac). That covers files a Bot sends, files you attach, and files a Bot names by their full
  path in its reply, which now show as a file to open. In the ⌥Space panel, a file opens beside its
  chat in the main window.
- **Widgets in messages.** When a Bot writes a small web page, such as a chart or a calculator, and
  shows it with `::preview`, it runs right in its message, as in Hermes's desktop app. It takes the
  chat's colours in light and dark, and its links open in your browser. In the ⌥Space panel it shows
  as a card, and notifications say "Sent a widget".
- **Widgets that answer back.** A button in a widget can ask the Bot to do something, such as clear
  old logs. It goes to the Bot without showing as your message, the widget changes once the Bot has
  done it, and the reply notifies you if you've left the chat. If the Bot is still replying, it
  waits in the queue as "From a widget", where you can remove it. Widgets in rooms can't send.
- **Give a Bot a goal and watch it work.** Send `/goal` and what you want, even while the Bot is
  replying, and it keeps working on it reply after reply. The goal shows above the message box with
  how many turns it has used, what Hermes made of the last reply, and why it stopped if it did.
  **Stop Goal** stops it, **Continue** carries on with a full set of turns, and **Clear** removes
  it. You're notified when a goal ends without you, while the app is connected.
- **Share to a Bot from other apps.** Choose Usual Bot in the share sheet on iPhone or the Share
  menu on the Mac, and the app opens on **Send to**. Pick a Bot or room, and what you shared (a
  link, text, photos or files) goes into its message box for you to add to and send. Rooms take text
  and links.
- **Two gateways.** Sign in to a second Hermes gateway and switch between them from the gateway menu
  at the bottom of the Mac sidebar, or from Settings. The gateway you leave keeps its sign-in and
  chats, and still sends you notifications; tapping one switches to it. Give each gateway a name of
  your own or turn its notifications off. Telling their notifications apart needs the Usual Bot
  plugin on both gateways.
- **Pin a chat.** Choose **Pin** from a chat's menu in the sidebar (right-click on the Mac, touch
  and hold on iPhone) and it stays at the top as a large avatar, with its unread count or needs-you
  dot. A new pin goes after the others, and pins stay where you put them: on the Mac, drag one onto
  another to swap places, drop a chat on a pin to pin it there, or drag a pin to a section to unpin
  it; on either device, choose **Move Left** or **Move Right**. A Bot's pin shows on your other
  devices and in the Hermes app; a room's pin and the order stay on the device.
- **Mark as Unread.** Mark a Bot Chat unread from one of its messages or from the chat list, to come
  back to it later. It's unread on your other devices and in the Hermes desktop app too, and opening
  it on the device where you marked it goes back to that message. **Mark as Read** in the chat list
  clears it.
- **A NEW line shows where unread replies start.** Open a chat or room with replies you haven't read
  and a blue NEW line sits above the first of them, or above the message you marked unread from. It
  stays put while you read and is gone the next time you open the chat with nothing new.
- **See when a Bot is working, even after it replies.** A green dot on its avatar shows while it
  works. That includes work that goes on after the reply: a command it left running (such as
  watching a pull request), a background task, or one of its routines running.
- **Gateway calls.** Choose **Gateway** as the call engine to talk with a Bot through the
  speech-to-text and text-to-speech set up on its Hermes profile, in the voice configured there. The
  reply is spoken sentence by sentence as it's written, and you can talk over it. Your voice goes to
  your gateway, which may send it on to paid services. If the gateway can't hear or speak, the call
  says why and offers **Use On-device**.
- **Dictate through your gateway.** Choose Gateway in Settings › Voice › Dictation to have your
  Bot's own speech-to-text on Hermes hear you. Words appear as you talk if the gateway streams them;
  otherwise "Transcribing…" shimmers where they'll go until you stop. If the gateway can't
  transcribe, **Use On-device** turns the same recording into words on your device.
- **Read a reply aloud.** A Bot's message has **Read Aloud** in its menu on the Mac and iPhone, in
  chats and rooms. It reads the words, not the Markdown marks, code or file paths, in this device's
  voice with the language, voice and speed from Settings › Voice, so it's free and works offline.
  **Stop Reading** shows under the message while it plays. Playing a voice memo or video, leaving
  the chat or starting a call stops it.
- **Choose who answers in a room.** A message without an `@name` can go to everyone, to a lead Bot
  that picks who answers, or to whoever Hermes picks. Set it in New Room or under Room Settings… in
  the room's panel, which also keeps one line on what the room is for and notes every Bot should
  keep in mind. A small line says who was picked. Needs Hermes 0.23 or later on the gateway.
- **Continue a paused discussion.** When Hermes stops Bots that keep replying to each other, the
  room offers Continue.
- **A terminal for each Bot (Mac).** Press ⌘J in a Bot's chat to open a shell on your gateway's
  computer, in the folder the Bot works in. The drawer also lists the commands the Bot ran in the
  chat, with their output. The shell needs the Usual Bot plugin.
- **Zoom the Mac window.** View › Zoom In (⌘+), Zoom Out (⌘−) and Actual Size (⌘0) make everything
  in the window bigger or smaller, from 80% to 150%, as a browser zooms a page. It's also in
  Settings › General, in place of Chat text size on the Mac, which only grew message text. A text
  size you'd chosen before carries over.
- **More of the Mac from the keyboard.** ⌘1 to ⌘9 open your first nine chats, counting down the
  sidebar from the pinned ones; hold ⌘ for a moment to see each chat's number. Go › Back (⌘[) and
  Forward (⌘]) step through the chats and rooms you opened. ⌘D starts and stops dictation, or hold
  it while you talk. Help › Keyboard Shortcuts (⌘/) lists every shortcut.
- **The app's icon shows how many replies you haven't read.** The number on the Dock and Home Screen
  icon counts unread replies in chats and rooms, leaving out chats you muted, and it keeps counting
  pushed messages while the app is closed. If you'd allowed notifications before, turn on Badges for
  Usual Bot in the system's notification settings.
- **Warnings before your subscription runs out.** When a Bot runs on a Claude (or other)
  subscription that's at 90% of its 5-hour or weekly limit, the chat says how much is used and when
  it resets. Rooms name the Bots it affects. Settings › Usage shows each limit.
- **Swipe to reply, and see message times, on iPhone.** Swipe a message to the right to reply to it.
  Drag a chat or room to the left to see when each message was sent, or flick it left to open the
  Bot's page or the room's details.
- **Bots can ask for secrets through a masked prompt.** With the Usual Bot plugin installed, a Bot
  can request a key or token without asking you to paste it into chat. Hermes saves the value in the
  profile’s `.env`.
- **Usual Bot says when a newer build is in TestFlight.** Below the chat list, a line says when a
  newer version is out and offers **Update in TestFlight**, which opens TestFlight to install it, or
  **Later**, which hides that build until the next one. It names only builds Apple has approved for
  testers, so you can always install it. Settings › About keeps the update link. TestFlight builds
  check bot.usual.dev every few hours. The check sends nothing about you; other builds never check.
- **A plainer chat.** Turn off **Show what Bots do with tools** in Settings › General to hide the
  lines for commands, edits, tools, to-do lists and helpers. Messages, Bots talking to each other
  and routine results stay.
- **Right-click a link to open it or copy its address.** On the Mac, a link in a message has its own
  menu, so you can copy the link without copying the whole message.
- **Suggestions as you type on the Mac.** The message box shows macOS inline predictive text. Press
  Tab to take a suggestion.
- **The Mac's message box shows a scroll bar when your message is longer than it.** Past eight
  lines, a thin bar at the box's edge shows where you are in your text. Drag it to move through it.

### Changed

- **One Usual Bot plugin, installed from the app.** The push and browser plugins are now one,
  `usual-bot` (0.14.0). On the Mac, Plugins installs or updates it in every Bot through Hermes after
  you confirm what Hermes's check found, and the puzzle piece shows a yellow dot when an update is
  out. Bots you make in Usual Bot get it too. Updating replaces both old plugins and keeps your
  devices and settings; until you update, the old ones keep working.
- **Bots know they're in Usual Bot.** With the plugin updated, Bots in the chats you open in Usual
  Bot are told that files and widgets show here, so they send files you can open instead of only
  naming their paths. They reply like a chat: a few short sentences with the answer first, a short
  line like "Checking the two threads and this week's traffic." before longer work, and no
  report-style headings. A Bot whose own instructions set a different voice keeps it. A Bot
  answering another Bot's message is told its reply goes back to that Bot. The plugin says nothing
  about you or your device, and does nothing for your other apps' chats.
- **Bots talking to each other stay out of your way.** When a Bot asks another Bot for something,
  its chat shows who it asked and what came back ("Asked Forge", "Forge answered"). The other Bot's
  work folds into one line, "Talked with Atlas", which you can open, and its reply to that Bot
  doesn't notify you or count as unread. If the answer gets lost on the way, the chat says so and
  opens the other Bot's chat for you.
- **Your messages are easier to read.** In a chat, your messages showed in the Bot's colour, which
  turned a long message into a bright block. They're now in a calm grey bubble, as in rooms. The
  Bot's colour stays on Send and its picture.
- **Quieter text in dark mode.** Text is off-white instead of pure white and the grey of previews,
  dates and labels is a step darker, so regular text no longer looks bold on the dark background. On
  the Mac the sidebar's names, its section titles and the name above a chat are a little smaller and
  lighter. Inline code in a reply is smaller and grey on a faint background.
- **Long replies are easier to read on the Mac.** Lines and paragraphs have a little more room, list
  items sit closer together than paragraphs, and letters are spaced slightly wider.
- **You can see what a Bot is doing while it works.** Instead of always saying "Thinking…", the line
  under your message says what kind of tool the Bot is using ("Reading…", "Running a command…").
  Between steps it shows the face and word Hermes picked, such as "(¬‿¬) pondering…".
- **A clearer "needs you" dot.** The amber dot sits in the same place as the green working one, and
  rooms now show both.
- **A routine's results show in full in its Bot's chat.** A routine set to post in the chat used to
  leave a folded line you had to open. Its result now shows as a message under "From the routine"
  and the routine's name, with Show All for a long one. If the Bot chooses not to reply, the result
  itself counts as unread. Turn off **Show routine results in full** in Settings › General to fold
  each into one line again.
- **Tool steps, helpers and results fold the same way.** Each is one line with an icon and a plain
  summary; opened, its steps or report hang beneath it. Each helper gets its own row with how long
  it took, and its report shows as formatted text. Background commands say whether they finished or
  failed, with the exit code, and show the command and its output separately. Long reports show
  their first lines with Show All instead of scrolling inside the chat.
- **Notifications go to the device you're using first.** A message reaches the device you're using,
  or the one you used last, straight away. Your other devices get it 15 seconds later, unless you've
  read that chat by then. A Mac you've left alone for a minute doesn't count as in use. Needs the
  Usual Bot plugin 0.13.0 or later.
- **Reading a chat clears its notifications on your other devices.** Notifications about a chat
  you've read on your Mac leave your iPhone's lock screen, and the other way round, rooms included.
  If iOS missed the update, for example because you'd swiped Usual Bot away, they clear when that
  device's next notification arrives.
- **You're notified when a Bot says what it's doing.** A Bot's message before its reply, like "On
  it, looking now", now notifies like the reply itself. Update the Usual Bot plugin to get it.
- **Tapping a notification opens the chat sooner on iPhone.** When iOS allows it, a notification
  lets Usual Bot load that chat in the background, so tapping it soon after opens the chat already
  connected, with the message there. iOS doesn't do this for an app swiped away in the app switcher,
  and not always in Low Power Mode.
- **Switching chats is faster.** A chat now opens with its newest messages, and the earlier ones
  come a moment later; on a real gateway switching took about a third less time. On the Mac the last
  three chats you opened stay ready, each where you'd scrolled to, and the message box and the
  chat's name are no longer built again on every switch.
- **Coming back to the app is quicker on iPhone.** After a short visit to another app, the chat is
  ready to type in straight away. After a longer one, the chat on screen reconnects first, before
  the rest of the app catches up.
- **Touching and holding a message on iPhone opens a sheet.** Reactions, Reply, Mark as Unread,
  Copy, Select Text, Read Aloud and the rest now open in a sheet from the bottom, instead of a menu
  that lifted the whole message, so a long reply no longer pushes the menu off the screen. It opens
  while you're still holding.
- **Reactions sit at the top of a message's right-click menu on the Mac.** The quick reactions show
  in a row instead of under a React submenu.
- **A message's actions show when you point near it.** Pointing beside a message, or where its
  buttons appear, now shows them, not only pointing at the message itself.
- **On iPhone, a chat's model, thinking and context are in the Bot's profile.** Tap the Bot's name
  above the chat, then use **This Chat**. The message box no longer shows them while you type.
- **A Bot's profile is easier to scan.** Thinking is a slider, the context shows as a bar with
  Compress beside it, and the Mac's tabs are rows that open each page, with a back button. Next Up
  shows the Bot's two soonest routines with their switches. On the Mac, the model is a button that
  opens a list of every model, with search.
- **Dictation shows your voice.** While you dictate, your words appear above a row with a waveform
  of your voice, ✕ to cancel and take the words back out, Stop, and Send. The mic stays beside Send
  while you type, so you can dictate more into a message you've started.
- **Sending puts the iPhone keyboard away,** so your message and the reply have the screen. Tap
  anywhere in the message box to write again, not just the line of text. With a hardware keyboard
  the cursor stays in the box.
- **Clearer message box buttons on iPhone.** Attach, mic and the other secondary buttons sit on a
  grey circle, Stop is in the Bot's colour while a reply runs, and transcribing shows the same
  spinner as uploading files.
- **Chats fade out at the top and bottom on iPhone.** Messages fade into the background under the
  clock and the name, and below the message box, so the bars read more cleanly.
- **The iPhone chat list has no "Chats" title.** The list starts higher up the screen. The back
  button in a chat still says "Chats".
- **Hermes wears the app icon.** Your main Bot shows the Usual Bot icon instead of a drawn
  character, until you give it a picture of its own.
- On the Mac, a drag selects across a reply's paragraphs, headings, list items and quotes, not just
  within one of them.
- Web and email addresses written out in messages are links now, yours included, and links are
  underlined (and blue in replies) so they stand out from the words around them.
- **Voice calls read tables and file paths more naturally.** A table is read as its cells and a file
  path as the file's name.
- **Dragging in the Mac sidebar drops at once.** A dragged chat's picture no longer hangs where you
  dropped it.

### Fixed

- **Chats load reliably with many Bots.** With many Bots, chats could fail with "The gateway took
  too long to answer." and the connection kept dropping and reconnecting. The chat you're looking at
  now loads first, the others follow a few at a time, and a slow gateway no longer drops the
  connection.
- **Scrolling up through a chat works everywhere.** In a chat whose newest messages were short,
  scrolling to the top stopped at the newest few. As earlier messages loaded, the message you were
  reading could leap far up or down, and on iPhone the chat could freeze for seconds. Earlier
  messages now load a page at a time as you scroll (on iPhone, as you lift your finger), and the
  chat stays on the message you were reading.
- **Sending always shows your message.** A message sent while the chat was still scrolling, such as
  with fingers resting on the trackpad or just after a flick, left you further up and no longer
  following the reply. The round arrow button now works mid-scroll too.
- **Chats open at their last message.** Opening a chat could leave a blank under its last message.
  The newest message now sits just above the message box.
- **A finished reply no longer shows as "Writing…".** Opening a chat, often by tapping a
  notification, just as a reply ended could leave it showing "Writing…" until you opened the chat
  again. The reply now shows as soon as the chat connects.
- **Messages from your other devices show right away.** A message sent from your iPhone showed on
  your Mac only once the reply to it finished, which can take minutes. Its words now show as the
  reply starts, and its images join them when the reply ends.
- **Messages with an image show the image.** Some messages showed a file path, "[Image attached at:
  …]", "[screenshot]" or the Bot's instructions instead of the picture. They now show the picture
  and your words, and an image sent without words no longer shows "What do you see in this image?".
- **Files you send open again.** A video or file you sent in a chat showed "File not found (HTTP
  404)". It now plays or opens from the chat's workspace.
- **Messages with several photos stay on the screen.** On iPhone, a message with a few photos that
  couldn't load pushed the whole chat past the edge of the screen and cut off every message. The
  photos now wrap onto more rows.
- **No more "[SILENT]" messages.** When a Bot had nothing to add, for example a routine with nothing
  new or a note from another Bot, the chat showed "[SILENT]" and sent a notification for it. Now
  nothing shows and nothing notifies. Update the Usual Bot plugin from the app to stop the
  notifications.
- **Messages Hermes sends on its own no longer show as yours.** The first-run opening and goal
  controls from Hermes's own app showed up as your messages, and Undo or Edit could take them back.
  They're hidden now, as in Hermes.
- **The sidebar shows what you sent while a Bot worked.** A message sent during a reply showed in
  the sidebar as "[OUT-OF-BAND USER MESSAGE…". It now shows your words, or "You added a message
  while it worked" before the chat has loaded.
- **Chat previews show links as words.** A last message that started with a link could show in the
  chat list as raw Markdown, brackets and address included. It now shows the link's words.
- **Notifications show a reply's words, not its Markdown.** Headings, bullets, bold, code marks,
  tables and link addresses no longer appear in a notification. For pushed notifications, update the
  Usual Bot plugin.
- **A chat you left open no longer counts as read while the app is away.** A reply that came in
  while the iPhone checked in from the background was marked read on all your devices because that
  chat had been on screen when you left.
- **Typing /new no longer leaves an unanswerable confirmation.** `/new` and other commands Usual Bot
  doesn't offer were sent to the gateway, which asked to confirm and then said "No pending command
  to approve." The app now says the command doesn't work here and sends nothing.
- **A command that fails shows as failed.** A command that exited with an error used to show as
  done.
- **Pasting images and files on the Mac.** ⌘V in a chat attaches a copied image (a screenshot, Copy
  Image) or files copied in Finder; it used to do nothing. Text pastes as before.
- **No crash on a new line after pasted text.** Starting a new line in the message box right after
  text pasted from Windows or some web pages could close the app. It now adds the line.
- **Closing a window no longer quits the app on the Mac.** It could crash when you closed a window
  that had shown Jump to Latest.
- **Usual Bot no longer quits in the background on iPhone.** Leaving the app while it was renewing
  your sign-in could make iOS end it.
- **Dictation keeps what you said.** Pausing while dictating replaced the earlier words with the new
  ones; now the new words are added after them. Speech recognition's last words could arrive after
  Send and put the whole message back, or overwrite what you typed just after you stopped. On iPhone
  the cursor now ends after the dictated words instead of staying on the first character or jumping
  into the middle.
- **Dictation settings say where your voice goes.** The footer said dictation always stays on the
  device and works offline. It now says words are recognised on the device when it has your
  language's speech model, and otherwise by Apple's speech service.
- **Voice calls say when they can't hear you.** A call whose speech recognition couldn't start sat
  silent with no error. It now tries Apple's speech servers, as dictation does, and if that fails it
  tells you what to turn on.
- **Calls on iPhone keep hearing you.** A few seconds into a call, the microphone could switch off
  while the call still showed Listening. The call now starts the microphone again. If it can't, the
  call ends and says what to do.
- **Talking over a call's reply starts a new turn.** Words said right after cutting the Bot off
  could join the reply being stopped instead of starting a new turn.
- **The Mac call bar's buttons are visible again.** Settings, Transcript and Mute showed as pale
  circles with nearly invisible icons in dark mode. They now match the chat bar's round buttons.
- **Selected text is blue again.** Selecting text in the message box and other text fields showed a
  grey highlight in dark mode. It now uses your Mac's accent colour, and blue on iPhone.
- **Inactive windows no longer show a grey band at the top.** The sidebar and chat headers fade into
  their background colour instead.
- **No grey band behind the Mac message box while a reply runs.** The box now looks the same whether
  or not the Bot is working. ⌘. still stops a reply, and it's now also in View ▸ Stop Reply.
- **Resizing the Mac window is smooth again.** The window lagged behind the pointer while you
  dragged its edge. It now keeps up.
- **Scrolling a chat does less work.** On the Mac, the chat no longer redraws its jump button and
  toolbar on every frame of a scroll.
- **Paragraphs no longer run together on iPhone.** Paragraphs in a row in a reply were closer
  together than a list's items. They're now spaced like the rest of the reply.
- **The pointing hand shows where it should on the Mac.** Jump to Latest over message text, and
  links inside tables, showed a text cursor.
- **Working avatars stay in place as chats open.**
- **Every Bot sits inside the Plugins sheet's Bot's Browser list.** The last Bot could show outside
  the list's card on the Mac.
- **One subscription shows once in Settings › Usage.** Bots that share a Claude login could appear
  under two identical "Anthropic subscription" sections. They now share one.
- **Usage lines up in Settings on iPhone.** The Usage row's symbol and title sat to the left of the
  gateway's above them. They now line up.
- **The period picker in Usage stays still.** Choosing 7, 30 or 90 Days made the picker shrink and
  grow as a spinner appeared beside it. The spinner now sits in the corner of the totals, and a
  period you loaded in the last minute shows at once without loading again.

## 0.5.0 - 2026-11-09

### Added

- **Chats on the gateway's Webapp.** Usual Bot now chats through the listener `hermes gateway`
  serves itself (turn on `webapp.enabled`; port 9120), the same place the CLI, the Hermes desktop
  app and messaging run their chats. There, routine results set to post in the chat and messages
  from other Bots arrive in your Bot Chats while Usual Bot is open, and the Bot's reply to them
  notifies you. [Getting started](docs/guides/getting-started.md#2-get-your-gateway-ready) shows
  how to set it up; sign in again with the Webapp's address. The dashboard keeps working.
- **Routine results and Bot messages say who sent them.** A routine's result reads "From the
  routine “Morning brief”", and another Bot's message "Message from Scout", instead of Hermes's
  instructions to the agent.

### Changed

- Connected to the dashboard, the connection status says that routines and other Bots can't post
  in chats, and what to do instead.
- In a room on the Webapp, a reply that stopped partway can only be dismissed when Hermes can't tell
  whether it finished, and dismissing it no longer stops the room's other replies.

### Fixed

- **Replies keep their line breaks.** A reply written a line per item ran its lines together into
  one paragraph. Each line now shows on its own, in chats, rooms and the ⌥Space panel.
- The push plugin (`usual-push` 0.3.1) notifies you when a Bot on the Webapp asks for approval or a
  question, and keeps a hidden Bot quiet on a gateway that serves several profiles. Run its install
  script again to update it.

## 0.4.0 - 2026-11-08

### Added

- **Unread counts follow you.** Read a Bot's chat on the Mac or iPhone and its unread count, and its
  notifications, clear on your other devices too. Rooms still count on each device, as Hermes keeps
  no read position for them.
- **Plugins on the Mac.** A puzzle-piece button at the foot of the sidebar, between the gateway and Settings, shows whether your gateway has Usual's push and browser plugins and which Bots have a browser and computer to watch. Each setup step offers its commands to copy, or **Ask a Bot**, which opens a Bot's chat with the request typed in for you to send.
- **Hide a Bot.** Choose **Hide Bot** from a Bot's menu in the sidebar or its profile to take it out of the sidebar on every device, and out of the Hermes app's list. It keeps working and stays in its rooms, but doesn't notify you. Settings › General › Hidden Bots lists hidden Bots, including ones hidden in the Hermes app, with **Show** to bring each back. Quiet notifications need the `usual-push` plugin 0.3.0 on the gateway.
- **Wait for whole replies.** Turn off Settings › General › Show replies as they're written, and each of an agent's messages appears once it's finished, with "Writing…" while it's on the way. Quick Message follows it too.
- **See where tokens go.** Settings › Usage shows your Bots' tokens over the last 7, 30 or 90 days by day and by Bot, what was written, sent new or sent again, the background work beside your chats, and the cost when Hermes knows it.
- **Connect apps from the chat.** When an agent needs an account such as Gmail, or an MCP server's sign-in, a card offers Connect and Not now, opens the sign-in page, and updates once you're done. The Apps page lists the accounts Hermes reaches through your Nous Portal, with Connect and Disconnect.
- **Watch an agent's computer and take over.** An agent with a computer of its own shows a Computer
  button in its chat: watch its screen live, take over the mouse and keyboard, and hand it back.
- **Watch an agent's browser.** An agent that browses with your own browser profile, out of sight on
  your gateway, shows a Browser button in its chat: watch the page it has open, on the Mac or iPhone.
  Settings › General › Bot's Browser picks the picture quality and 1× or 2× pixel density for this
  device. It needs the `usual-browser` plugin (`Integrations/hermes-browser`) on the gateway.
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

- **Start typing to write on the Mac.** After you click a Bot in the sidebar or somewhere in the chat, typing goes straight into the message box, so you don't have to click it first. Shortcuts, the arrow keys and Space still do what they did, and other text fields keep their typing.
- **Tables in replies line up.** An agent's table shows as columns with a bold header, instead of a line per row. Long cells wrap, and a table too wide for the message scrolls sideways inside it.
- **Lighter chat bars on the Mac.** The chat's name and the message box no longer sit on a solid band with a line; the conversation blurs softly under them. The sidebar's connection and Settings float in glass over the list, level with the message box, and the message box is as tall as the header's buttons and sits as close to the bottom edge as they sit to the top. The narrow sidebar keeps only Expand Sidebar and Settings at its foot. The sidebar's list blurs under the window buttons as the chat does under its name.
- **Model, thinking and context in the Bot's panel on the Mac.** They moved from under the message box to **This Chat** in the Bot's profile panel, so nothing sits under the box any more.
- **Larger chat text on iPhone, and more contrast everywhere.** Messages are 18 pt with a 24 pt line, and the message box 18 pt, as in Grok's phone app. Text is pure white in dark mode and near-black in light, secondary text and the message box's buttons are brighter, and dark mode's chat and agent bubbles are a step darker, so text stands out more.
- **Chats only move up while a Bot works.** The "Thinking…" row no longer leaves and returns around each tool, a finished turn keeps its to-do list and helpers where they were, and an answered card leaves its space until the next message fills it.
- **A thin, quiet scroll bar everywhere on the Mac,** instead of the wide bright one macOS shows with a mouse connected: chats and rooms, the sidebar, profiles, Settings, sheets and menus. It widens under the pointer, and you can drag it.
- **Smoother profile and room panels on the Mac.** They slide in fast and settle, instead of moving at one speed and pausing on the way. The room's details get a close button like a profile's, and a Bot's ••• menu sits beside it.
- **The pointing hand over everything you can click on the Mac,** and switches in the system's blue, so on and off are easy to tell apart.
- **Quieter buttons.** The message box's attach, mic and Stop buttons, and the Mac's React, Reply and More beside a message, are plain icons instead of glass circles. Send and the call button keep the Bot's colour.
- **A wider message box on iPhone, and the keyboard goes away with a tap.** Tap the conversation to put the keyboard away, as well as swiping down it; the box no longer jumps as the keyboard finishes going.
- **A clearer Jump to latest button on the Mac,** a solid circle with an arrow, and the conversation no longer shows through the message box or around the model menus under it.
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

- **Long answers to an agent's question show in full on the Mac.** A choice too long for one line wraps instead of being cut off, and its letter lines up with the others.
- **Your answers keep their questions.** When an agent asks several questions at once, your message in the chat shows each question above your answer, since the card goes once you send. The agent always got both.
- **The iPhone message box opens with the keyboard.** It grows and rises in one motion, and the context and thinking buttons appear once it's open, instead of showing below the box first.
- **Tapping a notification on iPhone no longer closes the app.**
- **Back shows in Mac sheets again,** so a routine's past run, or a template's form, has a way out, and Quit works while a sheet is open.
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

