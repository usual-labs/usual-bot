# Usual Bot: roadmap after 0.1

Planned, not built. Milestones M0–M8 (through the 0.1.0 tag) are done; see `app-shell.md` and the
package KBs for what exists. Each milestone below runs and can be demoed on its own, ships with
tests, the demo mode (`AppModel.demo()`) and the KBs updated, and is checked on Mac and iPhone.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its
contract (`apps/shared/src/gateway-contract.openrpc.json`). The maintainer's gateway
(`e04614af7bb`, 23 October 2026) was checked only for the audio routes and attachment methods.
None of it has been exercised from this app yet; each milestone starts by confirming its calls
against a real gateway. All of them are on the dashboard socket (legacy dialect) or its REST
routes.

## M9: Attachments

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

## M10: Images in replies

- **You can:** see images an agent made or found (screenshots, generated images, charts) inline in
  its reply, tap to view full size, and save or share them.
- **Gateway:** `GET /api/media?path=…` returns a gateway-local image as a base64 data URL,
  auth-gated and limited to the media roots.
- **App:** find image references in replies (Markdown images and media paths; confirm the exact
  form first), load them through `AuthSession` (Bearer token, so not `AsyncImage`), cache them,
  and show a full-size viewer.
- **Done when:** a reply with a generated image shows it inline on both platforms, and a path
  outside the media roots shows a quiet placeholder instead of an error.

## M11: Skills and slash commands

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

## M12: Dictation

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

## M14: Edit and undo the last message

- **You can:** edit your last message and send it again, or undo it, while the agent is idle.
- **Gateway:** `session.undo {session_id}` drops the last user turn and everything after it;
  editing is undo, then submitting the new text.
- **App:** a context menu on your last bubble; the transcript reloads from the gateway afterwards.
- **Done when:** undo removes the turn on every attached app, and edit gives a fresh reply.

## M15: Reactions

- **You can:** react to a message with an emoji (one per author, tapping the same one removes it)
  and see the agent's reactions.
- **Gateway:** `message.react {session_id, row_id | newest_role, emoji | null, author}` returns
  the row's reactions. `row_id` comes from `session.history`, which carries durable row IDs.
- **App:** keep `row_id` on transcript items; a reaction bar on long-press and right-click;
  reaction badges under bubbles.
- **Open:** how reactions appear in history, and whether agents see or add them.

## M16: Side questions

- **You can:** ask a quick question about the conversation while the agent works, without
  interrupting it or adding to its history (Hermes's `/btw`).
- **Gateway:** `prompt.btw {session_id, text}`; the answer arrives as a `btw.complete` event.
- **App:** a "Side question" action in the message box; the answer appears as a dismissible card
  above the box, not in the transcript.

## M17: Background tasks

- **You can:** hand an agent a task that runs on a fresh agent in the background while you keep
  chatting, and get its result back in the chat.
- **Gateway:** `prompt.background {session_id, text}`; the result arrives as `background.complete`.
- **App:** a "Run in background" action; a status row while it runs; the result as a notice the
  chat keeps, and a notification on iPhone when the app is in the background (local only; push
  stays out of scope).

## M18: Usage and context

- **You can:** see how full the chat's context is and what it has cost, and compress it when it
  gets full.
- **Gateway:** `session.usage {session_id}` (tokens, context, cost), `session.context_breakdown`,
  `session.compress`.
- **App:** a small context meter in the profile panel's Machine tab or the chat header menu, with
  a Compress action.
