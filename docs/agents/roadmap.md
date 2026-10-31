# Usual Bot: roadmap after 0.1

Milestones M0–M8 (through the 0.1.0 tag) are done. Below, M9–M24 are built (each says how far it has been checked).

Shakedown, 24 October 2026: the maintainer went through every feature on the Mac against their
(legacy-protocol) gateway: attachments (photo and file), reactions, a skill, `/status`,
`/reasoning`, model and thinking switches, the context meter, edit and undo, `/btw` mid-reply,
`/bg` (also with the app quit mid-task, recovered on reopen), compress, a room's `/` menu and
panel, and both call engines. All worked; one bug was found and fixed (the cursor after a menu
pick, UsualUI known issues). Agent defaults (M20) were left out on purpose (they change an
agent's default model everywhere). Not covered: iPhone on a real device beyond sign-in. See `app-shell.md` and the
package KBs for what exists. Each milestone below runs and can be demoed on its own, ships with
tests, the demo mode (`AppModel.demo()`) and the KBs updated, and is checked on Mac and iPhone.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its
contract (`apps/shared/src/gateway-contract.openrpc.json`). The maintainer's gateway
(`e04614af7bb`, 23 October 2026) was checked only for the audio routes and attachment methods.
None of it has been exercised from this app yet; each milestone starts by confirming its calls
against a real gateway. All of them are on the dashboard socket (legacy dialect) or its REST
routes.

## M9: Attachments (built; verified on the Mac against the maintainer's gateway 2026-10-24)

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
  reload); rooms stay text-only on legacy (dashboard) gateways; only the canonical gateway serves `groups.attachment.upload` (see M22).

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

## M11: Skills and slash commands (built; verified on the Mac against the maintainer's gateway 2026-10-24)

Built as planned, then widened on 24 October 2026: the menu offers skills (✦) and commands (⌘)
together: quick and plugin commands, and Hermes's built-ins that the official app offers
(`commands.catalog` → `commands[name].desktop` null), minus the few that would switch, rename or
split the agent's one chat or only style a terminal. Built-ins that `command.dispatch` doesn't
run go through `slash.exec`, and their terminal output shows in a monospaced block;
`/reasoning` sets this chat's level through `config.set`. The skills list comes from the
dashboard's `GET /api/skills`, which includes switched-off skills.

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

## M13: Voice call (built; both engines verified on the Mac against the maintainer's gateway 2026-10-24)

The call is a glass bar over the chat (Grok Bot's design) with settings and a live transcript.
It has two engines, picked in the bar's settings (**Engine**: Automatic, On-device, GPT-Live;
`@AppStorage("callEngine")`). Automatic uses GPT-Live when the agent's gateway selects it
(`voice.voice_chat_mode: gpt-live`) and can run it, on-device speech otherwise; choosing GPT-Live
where the gateway can't run it shows the gateway's reason instead of falling back.

- **You can:** start a call with an agent from its chat (waveform button beside the mic): speak,
  hear its answer, interrupt by speaking, mute, end. Your requests and the agent's replies are
  ordinary messages in the chat.
- **On-device engine** (`VoiceCall`, `CallAudio`): Apple's recogniser turns what you say into a
  message after a 1.1 s pause; the reply is read aloud with `AVSpeechSynthesizer` as it streams
  (voice, speed and language in the settings); microphone and voice share one `AVAudioEngine`
  with voice processing, or take turns where that fails (error -10875 on the maintainer's Mac);
  barge-in needs two recognised words. Not tried in a real call yet.
- **GPT-Live engine** (`LiveCall`): OpenAI's full-duplex voice model (`gpt-live-1`) listens and
  speaks at once and delegates real work to Hermes, as in the official app. The WebRTC media runs
  in WebKit inside a hidden 1 pt web view (`live-call.html`, a port of the desktop's
  `lib/voice-live.ts`), so the app still has no third-party dependency. The app, not the page,
  exchanges the SDP offer through `POST /api/audio/voice-live/session?profile=` (seeded with the
  chat's latest text turns), so neither the sign-in nor the OpenAI key reaches the page. Each
  `session.delegation.created` becomes `prompt.submit` with `surface: voice-live` and the recent
  spoken exchange as `voice_context`; the reply streams back as `session.commentary.append`
  (whole sentences, code and file lines skipped) and tool progress as
  `session.thinking.append`. Needs an OpenAI key on the gateway (`OPENAI_API_KEY` or
  `voice.gpt_live.api_key`); OpenAI bills about $0.05 per call minute. The voice is the gateway's
  (`voice.gpt_live.voice`).
- **Checked:** the maintainer's GPT-Live call on the Mac worked (24 October 2026); unit tests for
  the session calls, seed history, delegated turn and spoken sentences. Not tried: the on-device
  engine in a real call, and either engine on iPhone (GPT-Live asks for the loudspeaker; WebKit
  may route otherwise).
- **Later:** the gateway's own text-to-speech (`/api/audio/speak-stream`) for the on-device
  engine.

## M14: Model and reasoning level (built; verified on the Mac against the maintainer's gateway 2026-10-24)

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
- **Not built:** the Machine tab entry and fast mode. Adding provider keys and the full Models
  settings stay in the official app. ("Make default" came after, as M20.)
- **Checked:** HermesKit tests (switch params, confirm, deferred, refused level, catalog, info);
  the menu in the demo on the iPhone Simulator and the Mac. Not yet tried against a real gateway.

## M15: Edit and undo the last message (built; verified on the Mac against the maintainer's gateway 2026-10-24)

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

## M16: Reactions (built with reply and copy; verified on the Mac against the maintainer's gateway 2026-10-24)

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

## M17: Side questions (built; verified on the Mac against the maintainer's gateway 2026-10-24)

- **You can:** type `/btw <question>` (it's in the `/` menu) to ask about the conversation, also
  while the agent works: the turn isn't interrupted or steered and the question never enters the
  agent's history. The answer shows in a card above the message box (Markdown, scrolls past
  220 pt) with a ✕; several can stack. Cards live for the session: not cached, gone after a
  relaunch or reconnect.
- **Gateway:** `prompt.btw {session_id, text}` → `{task_id}`; a side agent answers from a
  snapshot of the chat and the gateway emits `btw.complete {task_id, question, text}` on the
  session (`text` starts with `error: ` when it failed). An answer arriving before the reply that
  carries its task ID is matched by question; answers to questions asked from another app show
  too.
- **Not as planned:** no separate button; `/btw` in the menu is the action (Hermes's own name).
- **Checked:** HermesKit tests (asking while running, early answer, failures, parsing); the card
  and dismiss in the demo on the Mac and the iPhone Simulator.

## M18: Background tasks (built; verified on the Mac against the maintainer's gateway 2026-10-24)

- **You can:** type `/bg <task>` (or `/background`; it's in the `/` menu) to hand a task to a
  fresh agent that works in the background, also while the chat's agent replies. One bar above the
  message box (spinner; "Working in the background: …", or "2 tasks working in the
  background: … · …") shows what's running; the result
  then joins the chat as its own item ("Background task: …" over the Markdown answer) and counts
  as unread in a chat you're not looking at. A failure becomes a notice.
- **Notification:** when a result arrives and the app isn't in front, a local notification says
  "<Agent> finished a background task" with the task and the start of the answer (permission is
  asked the first time). On iPhone the app disconnects in the background, so a result that lands
  then is missed by this device; it's only noticed while the app is open but inactive.
- **Gateway:** `prompt.background {session_id, text}` → `{task_id}`; the side agent runs as its
  own stored session (session ID = task ID) with this chat's model and tools, and the gateway
  emits `background.complete {task_id, text}` on the chat (`error: …` on failure). A result
  arriving before its task ID is matched to the oldest task still waiting for one.
- **Limits:** results live in this device's transcript (and its offline cache) only: the
  gateway doesn't add them to the chat's history, so a reload (reconnect, undo) drops them, and
  results that arrive while the app is offline are missed. No cancel: the gateway has no call
  for it.
- **Checked:** HermesKit tests (start while running, early result, failures, unread, parsing);
  the row and result item in the demo on the Mac and the iPhone Simulator. The notification was
  built but not seen firing.

## M19: Usage and context (built; verified on the Mac against the maintainer's gateway 2026-10-24)

- **You can:** see how full a chat's context is as a small ring and percentage at the start of
  the model and thinking row under the message box (amber from 80%). Its menu gives the context
  in tokens, this chat's tokens in and out and API calls, how often it was compressed, and
  **Compress Conversation** (between replies). The transcript on screen stays; a notice says
  how far it shrank ("from about 152k to 18.4k tokens").
- **Gateway:** `session.usage {session_id}` (input, output, calls, compressions, and
  `context_used` / `context_max` / `context_percent` / `context_estimated` once a reply has
  run); `message.complete` carries the same `usage`, so the meter follows every reply without
  polling. `session.compress {session_id}` → `{status, removed, before_tokens, after_tokens,
  usage, messages}` (4009 while busy).
- **Not as planned:** no cost. Hermes keeps none for a chat (`session.usage`, `/usage` and the
  official app show tokens only); working it out from price lists would guess at cache reads and
  model switches. `session.context_breakdown` (per-category breakdown) isn't used.
- **Checked:** HermesKit tests (load, follow replies, no context yet, compress, refusal, short
  token counts); the meter and its menu in the demo on the Mac and the iPhone Simulator.

## M20: Agent defaults (built; live gateway untested)

Added 24 October 2026 at the user's pick, after M9–M19 were done.

- **You can:** save a chat's model or thinking level as the agent's own default, from the menus
  under the message box: **Make Default for <agent>** at the top of the model menu (shown when
  the chat runs on another model than the agent's; otherwise "<agent>'s Default" with a seal)
  and at the top of the thinking menu (when a level is set). Other chats with the agent, its
  routines and rooms then use it. A pricier model asks first, as switching does. A notice in
  the chat confirms it.
- **Gateway:** the model goes through `profiles.configure {name, model, provider,
  confirm_expensive_model?}`, the official Bots editor's call (`confirm_required` +
  `confirm_message` writes nothing until resent; `applied.model` says whether it saved). The
  thinking level goes through `config.set {session_id, key: "reasoning", value, scope: "global",
  profile: <agent>}`, which writes `agent.reasoning_effort` in that agent's config and applies
  it to the live chat too. `config.set` is scoped by `profile`, not by the session: without it
  the gateway's main profile would change (the `/reasoning --global` path had that bug; fixed).
- **Agent's default:** from the roster (`profiles.list`'s model and provider in
  `Contact.details`); it updates on the next roster refresh. There's no default thinking level in
  the roster, so the thinking menu always offers the button.
- **Checked:** HermesKit tests (confirm then save, the reasoning call's params, `/reasoning
  --global` carries `profile`); both menus in the iPhone Simulator demo (Forge's demo chat runs
  on another model than its default).

## M21: Keep background results and side answers (built; verified on the Mac against the maintainer's gateway 2026-10-24)

Picked 24 October 2026, before the real-gateway shakedown.

- **You get:** background results that arrive while the app is offline or in the background
  (iPhone) still join the chat; results stay in the chat when it reloads from the gateway
  (reconnect, undo) and across relaunches; side questions, running tasks and results are saved
  with the chat's offline copy. A side answer that can't arrive any more says so ("lost while
  Usual Bot was offline; ask again") instead of spinning.
- **Why it's needed:** the gateway tears a session down 20 s after its last client disconnects
  (`ws_orphan_reap_grace_s`), with its event buffer; side agents' answers sent to it then are
  lost. Background tasks keep running on their own thread and store their conversation as a
  session whose ID is the task ID. Side answers aren't stored anywhere.
- **How:** each chat remembers the newest event `seq` and the gateway's `replay_epoch`. Back on the
  same live session in the same gateway process, `session.events.since {session_id, last_seen}`
  replays the missed `btw.complete` / `background.complete` (if not `truncated`). Otherwise
  waiting side questions are marked lost, and unconfirmed (local) tasks get a notice. Every task
  still waiting is then looked up every 20 s in `GET /api/sessions/{task}/messages?profile=
  &order=latest&limit=5&inline_images=false`: the last stored message, if it's the agent's text
  without tool calls, is the answer. A result delivered twice (live and from the store) joins once.
  Results are kept apart from the transcript (`backgroundResults`, last 50) and put back by time
  whenever the transcript is rebuilt.
- **Checked:** HermesKit tests (replay after a short drop, new session: lost side answer and a
  result from the store, no duplicate, time-ordered reload, cache round trip and old caches).

## M22: Rooms catch up (built where the gateway allows; verified on the Mac against the maintainer's gateway 2026-10-24)

- **You can:** type `/` in a room (at the start or after a space) to pick from every member's
  switched-on skills, each labelled with the members that have it ("Atlas, Forge · Search the
  web"); the pick goes into your message as `/name` for the members to use. Click the room's name
  (⌘I) for a panel listing its members with the model each answers with, and how to change one.
- **Why only skills:** a room message is text to its members (`groups.send` takes text and
  attachments); commands run on one agent's own chat and can't be sent into a room.
- **Model per member:** room members follow their agent's default model (room sessions are
  `follow_profile_config`), shown from the roster; it changes with M20's Make Default in the
  agent's chat.
- **Not possible on legacy (dashboard) gateways, which the app speaks:** room attachments
  (`groups.attachment.upload`/`download` exist only in the canonical gateway's controls) and
  per-member usage (`groups.state` reports only who's working).
- **Checked:** a UI test for the merged skill menu; the menu (mid-message) and the panel in the
  iPhone Simulator demo.

## M23: Bot pictures from Hermes (built; verified on the Mac against the maintainer's gateway 2026-10-26)

- **You see:** a Bot that has a picture in the Hermes desktop app (uploaded or generated there)
  shows it in Usual Bot: in the list, the chat header, rooms, the profile and the ⌥Space panel.
  A Bot with one of the Hermes app's drawn faces, or none, keeps its Usual Bot character.
- **How:** `profiles.list` rows carry `has_avatar`, `ui_meta_revisions['hermes-bots']` and
  `ui_meta['hermes-bots'].imageKind` (`photo` or `shape`); `Contact.picture` keeps them.
  `BotPictures` (HermesKit) reads each picture with `profiles.get_asset {name, asset: "avatar"}`
  (a data URL: PNG, JPEG or WebP, at most 2 MB), keeps it in the offline cache, and
  `AgentAvatar` shows it on the usual circle (the `botPictures` environment value).
- **The drawn face's still:** the desktop app also stores a 160 × 160 PNG of its drawn face as
  the avatar for its own notices (`isBackfilledFacePng` in its `avatar-image.ts`); uploads and
  generated pictures are 256 px. Like the desktop's Bot list, a 160 × 160 PNG counts only when
  `imageKind` is `photo`. In practice every Bot the desktop has shown gets such a still, so
  `has_avatar` is true for nearly every Bot and this rule decides what shows.
- **When pictures update:** the roster refreshes every 5 s, so a picture is read again only
  when its revision changes (the desktop saves its Bot settings with every new picture) and once
  per connection. `profiles.set_asset` alone doesn't bump the revision, so a picture changed
  without the desktop shows after the next reconnect or launch. A failed read waits for the next
  revision or connection. Room pictures (a room's own image) aren't shown.
- **Checked:** HermesKit tests (roster decoding, one read per revision, the face still, removed
  pictures, cached pictures read again); a render of `AgentAvatar` with and without a picture;
  Mac and iPhone Simulator builds. On the Mac against the maintainer's gateway (a temporary
  diagnostic build, 2026-10-26): all 12 Bots reported `has_avatar` with a 160 × 160 PNG still
  (about 3 KB) and no `imageKind`, so all kept their characters as intended. The maintainer then
  gave a Bot a picture in the Hermes app and reported that Usual Bot showed it.

## M24: Secret and sudo prompts (built; live gateway untested)

- **You see:** when a skill needs a secret or a command needs the sudo password, a card in the chat
  (and in the ⌥Space panel) with the environment variable and the gateway's wording, or the
  command, above a masked field, with Skip and Send. The agent shows as Needs you meanwhile.
- **Wire format:** server requests `secret {session_id, env_var, prompt, metadata?}` and
  `sudo {session_id, command}`, both answered `{value}`, where `""` means skipped
  (`tui_gateway/contracts/server_requests.py`, `tui_gateway/agent_callbacks.py`). An error answer
  also ends in an empty value (`server._ask`). `metadata` isn't shown. The gateway waits 300 s for
  a secret and 120 s for a password, then sends `request.cancel` with reason `timeout`. Requests
  still open come back in `session.resume`'s `open_requests`.
- **How:** `SecretPrompt` (one type for both requests) in `ChatThread.secrets`, handled in
  `ChatThread+Secrets.swift`; `SecretCard` in UsualUI. Rooms show no such card.
- **Never 4404:** `AppModel.handle` answers these two with an empty value when no chat can take
  them. With no other client attached, a 4404 settles the request with a JSON error as its value,
  and the gateway would save that as the secret (HermesKit known issues).
- **Keeping the value private:** only `SecretCard`'s `@State` holds it, emptied on send, skip and
  disappearing; a reconnect removes the card too. It isn't in `CachedThread`, and notices name what
  was asked for. `FrameRecorder` blanks `result.value` in outgoing frames. Swift strings can't be
  wiped, so the bytes stay in process memory until they're overwritten.
- **Plain http:** `GatewayAddress.isUnencrypted` is true for `http` off this device outside
  Tailscale (a LAN address, `.local` or a single-label name). The card then warns, and its button
  reads Send Unencrypted. Sending stays possible: such a gateway already carries your sign-in and
  chats this way, and it has no other route. Loopback and Tailscale addresses show no warning.
- **Checked:** HermesKit tests (receiving, answering, skipping, withdrawal, reopened requests,
  other methods still declined, no chat or a malformed request, recorded frames, what counts as
  unencrypted); both cards and the masked field in the iPhone Simulator demo. The 4404 behaviour
  was reproduced by calling the gateway's `server_requests` module directly, with its contract
  registry stubbed. Not tried against a real gateway, and not looked at on the Mac or in the
  ⌥Space panel.
