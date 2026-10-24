# Usual Bot: roadmap after 0.1

Milestones M0–M8 (through the 0.1.0 tag) are done. Below, M9–M12 and M14–M16 are built
(each says how far it has been checked); M13 (voice call) is in progress, then M17–M19. See
`app-shell.md` and the package KBs for what exists. Each milestone below runs and can be demoed on its own, ships with
tests, the demo mode (`AppModel.demo()`) and the KBs updated, and is checked on Mac and iPhone.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its
contract (`apps/shared/src/gateway-contract.openrpc.json`). The maintainer's gateway
(`e04614af7bb`, 23 October 2026) was checked only for the audio routes and attachment methods.
None of it has been exercised from this app yet; each milestone starts by confirming its calls
against a real gateway. All of them are on the dashboard socket (legacy dialect) or its REST
routes.

## M9: Attachments (built; live gateway test pending)

Implemented as planned, with one change: PDFs go through `file.attach` like other files, as the
official app's Bot Chat does (`pdf.attach` needs `pdftoppm` on the gateway and only sends page
images). Limits are 25 MB per image and 50 MB per file. Past images show by name until M10 can
load them from the gateway. See the HermesKit and UsualUI KBs for details.

- **You can:** attach images, PDFs and other files to a message. Mac: paperclip, drag and drop,
  paste. iPhone: Photos, camera, Files. Attachments show as removable chips above the message box
  and as thumbnails or file pills in your sent bubble.
- **Gateway:** before `prompt.submit`, `image.attach_bytes {session_id, content_base64, filename}`
  queues an image for the next turn (`image.detach` removes it); `pdf.attach {content_base64,
  filename, first_page?, last_page?}` queues a PDF's pages as images; `file.attach {data_url,
  name}` saves any other file in the session workspace and returns an `@file:` reference the
  message text must carry.
- **App:** HermesKit `ChatThread.send(text:attachments:)`, staging each upload and then
  submitting; UsualUI attachment chips, pickers, drop and paste; `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription` on iPhone.
- **Done when:** an agent describes an attached photo, summarises a PDF and reads an attached file,
  on Mac and iPhone; failed uploads say why and keep the draft.
- **Open:** size limits per method; how history shows past attachments (to draw them after a
  reload); rooms stay text-only (`groups.send` takes text).

## M10: Images in replies (built; a gateway image verified on the Mac 2026-10-24)

Implemented with one change: gateway files load through `/api/fs/read-data-url?profile=`, as the
official app does for remote gateways, because `/api/media` only serves the default profile's
`images`, `screenshots` and `cache` folders. Agents write `MEDIA:/path` lines only when Hermes
tells them the surface renders them; on a server gateway, sessions not created by the desktop
app may get the terminal instructions instead and name files in plain text, which the app
now turns into images too when the path is absolute and ends in an image type (confirmed: the
maintainer's agents write plain paths; a generated image from the gateway's cache showed on the
Mac, 24 October 2026).

- **You can:** see images an agent made or found (screenshots, generated images, charts) inline in
  its reply, tap to view full size, and save or share them.
- **Gateway:** `GET /api/media?path=…` returns a gateway-local image as a base64 data URL,
  auth-gated and limited to the media roots.
- **App:** find image references in replies (Markdown images and media paths; confirm the exact
  form first), load them through `AuthSession` (Bearer token, so not `AsyncImage`), cache them,
  and show a full-size viewer.
- **Done when:** a reply with a generated image shows it inline on both platforms, and a path
  outside the media roots shows a quiet placeholder instead of an error.

## M11: Skills and slash commands (built; live gateway test pending)

Built as planned. The menu offers skills, quick and plugin commands, and the built-ins that
`command.dispatch` runs and that make sense in a chat (/retry, /undo, /compress, /plan, /goal,
/learn); the rest of Hermes's registry drives its terminal UI and stays in the official app. The
skills list comes from the dashboard's `GET /api/skills`, which includes switched-off skills.

- **You can:** type `/` in the message box to pick a command or skill, with a description and
  completion, as `@` already works in rooms. The agent's profile gets a Skills tab next to
  Routines and Machine, with a switch per skill.
- **Gateway:** `commands.catalog {session_id}` (categorised: built-in, quick, plugin, skill),
  `command.dispatch` to run one and get back a structured directive, `skills.manage {action:
  list}` per profile, `PUT /api/skills/toggle` for the switch.
- **App:** a `CommandCatalog` in HermesKit, loaded per chat; a `/` menu in `MessageBox` shared
  with the mention menu; a Skills tab in `ProfilePanel`.
- **Done when:** running a skill from the menu behaves like typing it in the official app, and
  turning a skill off hides it from the menu.
- **Open:** which directives `command.dispatch` returns and which of them a messenger should
  support; commands that only make sense in the official app stay out of the menu.

## M12: Dictation (built; verified on the Mac 2026-10-24)

Built with `SFSpeechRecognizer` on both platforms (on-device when supported) instead of
`SpeechAnalyzer`, which would need a second code path for macOS 15 / iOS 18 and asset downloads.
The mic replaces Send while the box is empty, as in Grok Bot.

- **You can:** tap a mic button in the message box and speak; words appear as you talk, and you
  can edit before sending.
- **Approach:** on-device recognition with Apple's Speech framework (`SpeechAnalyzer` on
  macOS 26 / iOS 26, `SFSpeechRecognizer` before that). It works offline, keeps audio on the
  device and needs nothing from the gateway. Hermes's own speech-to-text
  (`/api/audio/transcribe`, `/api/audio/transcribe-stream`) stays a later option for people who
  want their profile's provider.
- **App:** a `Dictation` helper in UsualUI or the app shell; mic and speech-recognition usage
  strings on both platforms; a level meter on the mic button.
- **Done when:** dictation works on Mac and iPhone, stops cleanly when you send or tap again, and
  explains a denied permission with a way to the system setting.

## M13: Voice call

- **You can:** start a call with an agent from its chat: speak, hear its answer, interrupt by
  speaking, end the call. The turns appear in the chat as normal messages.
- **Approach:** Hermes's "chained" voice mode, built natively: M12's recogniser turns speech into
  a turn (`prompt.submit`), and the reply is spoken as it streams. Speech out comes from the
  gateway's `/api/audio/speak-stream` WebSocket (text in, 16-bit PCM out, sentence by sentence,
  barge-in by `stop`), with `AVSpeechSynthesizer` as the fallback when the gateway has no
  text-to-speech. `/api/audio/tts-lease` warms the engine when a call starts.
- **Not planned:** GPT-Live (`/api/audio/voice-live/*`) needs an OpenAI key on the gateway and a
  WebRTC library in the app, which would end the no-dependencies rule.
- **App:** a call screen (agent avatar, speaking/listening state, mute, end); AVAudioSession on
  iPhone (speaker and Bluetooth routing, interruptions); echo cancellation so the agent's voice
  doesn't trigger barge-in.
- **Done when:** a five-turn spoken conversation works on iPhone and Mac, interrupting stops the
  agent's speech at once, and leaving the app ends the call cleanly.

## M14: Model and reasoning level (built; live switch untested)

Added 24 October 2026 at the user's request, ahead of the rest; built the same day.

- **You can:** see which model a chat uses and how hard it thinks, and change both from two
  menus under the message box, on the right: the model (current provider's models ticked,
  other providers in submenus) and the thinking level (Off, Minimal, Low, Medium, High, Extra
  high, Max, Ultra; hidden for models the catalog marks as non-reasoning). A pick changes this
  chat only; the agent's default model stays. Same layout on Mac and iPhone.
- **Gateway (as built):**
  - `model.options {session_id}`: providers with `slug`, `name`, `models`, `featured_models`
    (an aggregator's shortlist, offered instead of hundreds of models) and per-model
    `capabilities.reasoning` (Hermes assumes true when silent).
  - `config.set {session_id, key: "model", value: "<model> --provider <slug> --session"}`.
    `--session` keeps config.yaml untouched; on a Bot Chat the gateway still records the pick
    (`composer_override_profile`), so it survives resume while the profile's model is unchanged.
    `confirm_required` + `confirm_message` asks first (resend with `confirm_expensive_model`);
    `deferred` means a reply is running and the switch lands at the next turn (a notice says so).
  - `config.set {session_id, key: "reasoning", value}`: per chat; there is no way back to the
    provider default ("" in `session.info`), so the menu shows "Default" with nothing ticked.
  - `session.info` events (and the `info` in resume/create results) carry `model`, `provider`
    and `reasoning_effort` ("" default, "none" off).
- **Not built:** "Make default" (the profile's default model) and the Machine tab entry; fast
  mode. Adding provider keys and the full Models settings stay in the official app.
- **Checked:** HermesKit tests (switch params, confirm, deferred, refused level, catalog, info);
  the menu in the demo on the iPhone Simulator and the Mac. Not yet tried against a real gateway.

## M15: Edit and undo the last message (built; live gateway untested)

- **You can:** on your last message, between replies: **Edit** puts its text back in the
  message box under an "Editing your last message" chip (✕ cancels); Send replaces the message
  and its reply with the new text and a fresh reply. **Undo** removes the message and its reply.
  Both sit in the message's More menu (Mac hover bar) and long-press menu (iPhone).
- **Gateway:** `session.undo {session_id}` → `{removed}` drops the last real user turn and
  everything after it (refused with 4009 while a reply runs); then `session.history` reloads the
  transcript (this device's copy is cut locally if that fails). Edit is undo, then an ordinary
  `prompt.submit` (the Ink TUI's /retry does the same). Not used: `prompt.submit`'s
  `truncate_before_row_id` + `confirm_truncate`, which can rewind to any earlier message.
- **Details:** an edit keeps the text and `@file:` references; images went with the old message
  and must be attached again. If the undo fails, the new text goes back into the box. Undo asks
  no confirmation.
- **Checked:** HermesKit tests (undo + reload, local fallback, refusal, edit, failed edit); the
  menu and editing chip in the iPhone Simulator demo. Not yet tried against a real gateway.

## M16: Reactions (built with reply and copy; live gateway test pending)

Built early, at the user's request (23 October 2026), with Grok Bot's hover actions: React,
Reply and Copy on every message (React in one-to-one chats only, since rooms have no reaction
call). Reply quotes the message in front of yours; in rooms it also @mentions the author, as the
official app's room reply does.

- **You can:** react to a message with an emoji (one per author, tapping the same one removes it)
  and see the agent's reactions.
- **Gateway:** `message.react {session_id, row_id | newest_role, emoji | null, author}` returns
  the row's reactions. `row_id` comes from `session.history`, which carries durable row IDs.
- **App:** keep `row_id` on transcript items; a reaction bar on long-press and right-click;
  reaction badges under bubbles.
- **Open:** how reactions appear in history, and whether agents see or add them.

## M17: Side questions

- **You can:** ask a quick question about the conversation while the agent works, without
  interrupting it or adding to its history (Hermes's `/btw`).
- **Gateway:** `prompt.btw {session_id, text}`; the answer arrives as a `btw.complete` event.
- **App:** a "Side question" action in the message box; the answer appears as a dismissible card
  above the box, not in the transcript.

## M18: Background tasks

- **You can:** hand an agent a task that runs on a fresh agent in the background while you keep
  chatting, and get its result back in the chat.
- **Gateway:** `prompt.background {session_id, text}`; the result arrives as `background.complete`.
- **App:** a "Run in background" action; a status row while it runs; the result as a notice the
  chat keeps, and a notification on iPhone when the app is in the background (local only; push
  stays out of scope).

## M19: Usage and context

- **You can:** see how full the chat's context is and what it has cost, and compress it when it
  gets full.
- **Gateway:** `session.usage {session_id}` (tokens, context, cost), `session.context_breakdown`,
  `session.compress`.
- **App:** a small context meter in the profile panel's Machine tab or the chat header menu, with
  a Compress action.
