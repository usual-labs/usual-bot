# Usual Bot: product and gateway decisions

Why the app works the way it does, where the code can't say so. Everything through M23 is built;
`git log` and the changelog hold the history.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its contract
(`apps/shared/src/gateway-contract.openrpc.json`). The app speaks the dashboard socket (legacy
dialect) and its REST routes. Confirm a call against a real gateway before building on it.

## Scope

- Usual Bot is a messenger for Hermes agents. Agent configuration, provider keys, skill setup and
  gateway administration stay in the official app, except two the developer chose to bring in: an
  agent's routines and its MCP servers (the Apps tab).
  Device-local preferences belong in Usual Bot.
- Fast mode isn't built. Only a message that starts with a command runs it; a `/skill` later in the
  text is sent as written, as in the official app.

## Messages

- **PDFs go through `file.attach`**, as the official Bot Chat does. `pdf.attach` needs `pdftoppm` on
  the gateway and sends only page images. Limits are 25 MB per image (the gateway's) and 50 MB per file.
- **Gateway files load through `/api/fs/read-data-url?profile=`.** `/api/media` serves only the
  default profile's image folders.
- **Agents often name images in plain text.** `MEDIA:` lines appear only when Hermes tells an agent
  the surface renders them, and sessions the desktop app didn't create may get terminal
  instructions. So an absolute path ending in an image type also becomes an image.
- **Undo is `session.undo`, then `session.history`.** Edit is undo plus an ordinary send, as the Ink
  TUI's `/retry` does. An edit keeps text and `@file:` references; images must be attached again.
  `truncate_before_row_id` (rewinding further back) isn't used.
- **Reactions are display-only in Hermes.** The agent's model never sees them, and rooms have no
  reaction call.

## Commands

- The `/` menu offers skills, quick and plugin commands, and the built-ins the official app offers
  (`commands[name].desktop` null). It leaves out what would switch, rename or split the one Bot
  Chat, and what only styles a terminal (`notInMessenger`).
- Built-ins `command.dispatch` refuses go through `slash.exec`. `/reasoning` is handled by the app,
  because the command worker wouldn't reach the live chat.

## Model and thinking

- A pick changes one chat: `config.set` with `--session` leaves config.yaml alone. On a Bot Chat the
  gateway still records the pick, so it survives resume.
- There's no way back to the provider's default thinking level, so the menu shows "Default" with
  nothing ticked.
- **Agent defaults use `profiles.configure` and `config.set … scope: global`.** `config.set` is scoped
  by `profile`, not by session: without `profile` it changes the gateway's main profile.
- Usage shows tokens, never cost. Hermes keeps no cost for a chat, and working one out from price
  lists would guess at cache reads and model switches.

## Side questions and background tasks

- The gateway tears a session down 20 s after its last client leaves (`ws_orphan_reap_grace_s`),
  with its event buffer. Side answers aren't stored anywhere. Background tasks store their
  conversation as a session whose ID is the task ID.
- So recovery replays with `session.events.since` when it's the same live session and gateway
  process. Otherwise waiting side questions are marked lost, and each waiting task is looked up
  every 20 s in its stored session.
- Answers can beat the reply carrying their task ID: side answers match by question, background
  results by the oldest task still waiting.
- Turns Hermes starts itself (a process or subagent finishing, an internal notification) are stored
  as user rows so the model reads them. `GatewayTurn` shows them by `display_kind`, and by wording
  for untyped rows. An unknown kind stays a message, so nothing you wrote can disappear. A live card
  on `message.start` is handled but hasn't been seen on a real gateway.
- **A turn started on another device gets its message when it ends.** `message.start` doesn't carry
  the prompt, so a watching device has only the reply until then. Hermes's Desktop also reads it back
  (`owner_forward.py`), and the turn is stored before `message.complete`. Only the message is put in,
  as a reload would scroll you to the end. A turn that failed or stopped isn't looked up, and a steer
  from another device still isn't shown.
- Background results aren't in the gateway's history, so the app keeps them apart and puts them back
  by time whenever the transcript is rebuilt. There's no cancel, because the gateway has no call for it.

## Voice

- **Dictation uses `SFSpeechRecognizer`,** not `SpeechAnalyzer`, which would need a second code path
  for macOS 15 / iOS 18 plus asset downloads.
- **GPT-Live runs in WebKit** (a hidden web view, `live-call.html`), so the app keeps no third-party
  dependency. The app, not the page, exchanges the SDP offer, so neither the sign-in nor the OpenAI
  key reaches the page.
- Choosing GPT-Live where the gateway can't run it shows the gateway's reason rather than falling back.

## Rooms

- A room message is text to its members, so `/` offers members' skills and no commands: commands run
  on one agent's own chat.
- Room members follow their agent's default model (`follow_profile_config`).
- Legacy gateways have no room attachments and no per-member usage.
- **No live activity in rooms.** Members run on hidden sessions, so no tool or helper events reach a
  client; rooms keep "X is replying…" from `driver_status.member_activity`.
- **Retry, no discard.** `groups.discard` isn't on the dashboard socket's method table. A retryable
  task blocks the room (`driver_status.blocked`), so Try Again is the only way out here, and the room
  shows Needs you.
- **"Delete" is `groups.disband`,** which stops the room and then tombstones it. A room list read
  before an edit landed is thrown away (`roomEdits`), or it would bring the room or its old name back.

## Live activity

- **Nothing here is cached.** `ThreadState` leaves `live` and its keyed notices out of `CodingKeys`.
- **A to-do list lasts as long as its turn.** Resume sends `todo_state` for a finished chat too, and an
  unfinished list from a turn that's over is stale, so it's only restored while running. The revision
  survives the turn: snapshots can arrive out of order.
- **Helpers can outlive a turn.** `delegate_task` may run in the background: the turn completes while
  `subagent.*` keeps coming, and Hermes starts a follow-up turn when it ends. So helpers are followed
  with no turn running. A turn that's stopped or fails takes its helpers with it, or a helper whose
  `subagent.complete` never comes would stay listed.
- **`reasoning.available` is ignored.** With no reasoning, Hermes sends the reply's own text through
  it. Only `reasoning.delta` counts, and that needs `show_reasoning` on.
- **`thinking.delta` is mostly spinner frames.** Only the explained waits Hermes's own app shows pass
  `LiveActivity.waitText`. `tool.generating` and `tool.output_risk` are ignored.

## Notifications

- **Push goes through the user's own ntfy or Pushover, sent by a gateway plugin.** Apple's push needs a
  key held by whoever signs the app, so a signed public release could only offer it through a relay
  we'd run, which breaks "Private" and "Small". The app stays a client: Hermes has no push of its own,
  and its ntfy platform is a separate two-way chat that doesn't mirror Bot Chats.
- **A Pushover link takes two taps.** Its `url` only shows inside the expanded message; ntfy's `click`
  runs on the first tap. Pushover has no way to open another app directly.
- **The plugin's settings are the one piece of gateway setup in the app,** because they only serve
  this app. `Integrations/hermes-push` holds them in `~/.hermes/usual-push/`, shared by all profiles.
- **`post_llm_call` is the reply signal.** `platform` tells a person's chat (`tui`) from helpers
  (`subagent`) and rooms (`bot_room`). It doesn't name the room, and the member session's title
  doesn't either: Hermes retitles it after the first message. So the plugin takes the room from that
  member's `on_room_member_activity`, which can land just after the reply, hence a short wait.
- **Nothing notifies while you're at the app, on any device.** A window in front or the quick panel
  counts; a Mac with its screen asleep doesn't, or leaving it in front would silence your phone. The
  developer asked for this over per-chat alerts, which were too noisy, so on iPhone another chat's
  request waits until you see the list.
- **The app reports focus every roster tick, and once when it's lost,** and the plugin forgets it
  after 15 s, so a crash can't silence pushes. Repeating "not focused" would let a Mac in the
  background overrule the iPhone in your hand.
- **Mac alerts stay local, iPhone leaves them to push once it's set up.** Otherwise an iPhone hears
  each one twice. A Mac can get both when the service's Mac app is installed too.
- **"Needs you" for an iPhone-only user may be short-lived.** With no client attached the gateway
  doesn't wait on a prompt, so answering often means having the app, on any device, connected.
- A catch-up alert is the rise in `unreadCount` on attach, so no new state is cached. A running turn
  waits for `message.complete`.

## Bot pictures

- `has_avatar` is true for nearly every Bot, because the desktop stores a 160 × 160 PNG of its drawn
  face. That size counts as a picture only when `imageKind` is `photo`. Uploads are 256 px.
- The roster refreshes every 5 s, so a picture is read again only when its revision changes, and
  once per connection. `profiles.set_asset` alone doesn't bump the revision.

## Sidebar sections

- **The official app's model, so both clients see the same groups.** A Bot's section is
  `sectionId` and `sectionName` in `ui_meta['hermes-bots']`, and the name rides along so a client
  that never saw the section can rebuild it. The list of sections, their order, empty sections and
  folding stay on each device, and so does a room's section, which Hermes doesn't sync either.
- **A write replaces all of `hermes-bots`,** so `BotMetaWrite` reads it raw, changes the two fields
  and sends it back with its revision. `ProfileRow.BotMeta` drops fields it doesn't know, so it
  can't be the source of a write.
- **The gateway's word settles everything.** A move holds over the 5 s roster read until the roster
  shows it, or for two reads after the write. A write that fails drops the move, and the next read
  puts the Bot, and if need be its section, back where the gateway says.
- **A rename of a section with Bots in it is several writes.** While the Bots disagree, the local
  name stays, as in the official app.
- **Sections come from a chat's menu, not from New Room's `+`:** a section starts with something in
  it. Heading actions are a `…` button on iPhone because list headers there have no context menu.
- **Search and the ⌥Space panel stay flat,** and the rail shows lines instead of headings and folds
  nothing, because it has no heading to unfold with.

## Search

- **Search reads what the app holds, not the gateway.** `GET /api/sessions/search` searches one
  profile per call, returns one hit per conversation with no message ID or time, and includes
  sessions from other platforms that the app can't show. Online, that's nearly everything: every
  agent with a Bot Chat is attached at connect with its whole history, and each room's log is read
  in full. Offline, it's the cache's last 60 items per chat and no rooms. A chat whose history
  Hermes wouldn't send (`historyOmitted`) has only what arrived since.
- **Only your and the agents' text,** not tool steps, command output, background results or the
  turns Hermes starts itself, and a reply's quote is left out because the quoted message has its
  own hit.
- **Newest first across every chat, up to 50.** Messages carry the gateway's time (or when they
  arrived). Those without one, from a cache written before times were kept, come after, chats in
  order of last activity.

## Masked prompts

- **Never answer `secret`, `sudo` or `vault.*` with 4404.** With no other client attached, Hermes
  takes the error as the answer (HermesKit known issues). Without a card, answer `{"value": ""}`,
  which is Hermes's skip. Rooms show no cards, so their requests get the skip too.
- A typed value lives only in the card's state and leaves it on send, skip or disappearing. It isn't
  cached, notices name what was asked for, and the frame recorder blanks it. Swift strings can't be
  wiped, so the bytes stay in process memory until they're overwritten.
- **Plain http means off this device and outside Tailscale** (`GatewayAddress.isUnencrypted`). A
  `100.64.0.0/10` address doesn't prove Tailscale, but a warning on every send to a normal tailnet
  gateway teaches people to click through it. Secrets warn and the button says Send Unencrypted;
  sending stays possible, as such a gateway already carries the sign-in and chats that way. Vault
  secrets need Send it anyway ticked for each send, and the model enforces that, not only the view.

## Routines

- **Usual Bot creates and edits routines,** a decision that narrows "gateway administration" in
  Scope: a routine is something you ask an agent for, so it belongs in the messenger. Only the name,
  prompt, schedule and delivery are editable; scripts, skills, models and other fields stay in Hermes.
- **Edits send only what changed.** `PUT /api/cron/jobs/{id}` re-parses any `schedule` it gets, which
  resets the next run, so an unchanged schedule isn't sent. A `deliver` Usual Bot didn't set (Telegram,
  `origin`, several targets) is kept unless you pick one of the two choices.
- **"Post in this chat" is `bot-chat:<profile>`.** In `cron/scheduler_delivery.py` the output becomes
  an inbound turn in that profile's Bot Chat, the chat Usual Bot shows, so the agent replies to it and
  that costs a turn. If the profile's gateway isn't running, the gateway queues it. Verified in the
  source only.
- **Presets write cron expressions** ("0 9 * * 1-5"), and the list reads them back in plain words.
  Custom text goes to the gateway as typed, and its 400 message is shown as is: it lists the forms
  it accepts.
- **Run Now on a paused routine turns it back on.** The trigger route passes `force`, which resumes
  the job as it claims the run. The detail says so before you press it.

## Vault

- **Remote clients may use it.** `tui_gateway/methods_vault.py` has no peer or loopback check; its
  docstring's "localhost" is descriptive. With a session authority, `AuthorityConnection.dispatch`
  answers -32601 for `vault.*` and `ws_legacy_fallback.py` lets the interactive grant run the same
  handlers.
- **Every call names `profile`.** Otherwise `_profile_scoped` uses the launch or ticket profile, so
  a call would reach the wrong Bot's vault.
- `VaultItem` has no field for a secret: `vault.list` is metadata, and it stays that way here.

## Apps (MCP servers)

- **Dashboard routes, not RPC.** `/api/mcp/servers`, `/catalog`, `/catalog/install`, `/oauth/flows`
  through `AuthSession.json`, each with `?profile=`. Read from Hermes `bf0203a794`
  (`hermes_cli/web_routers/mcp.py`).
- **Changes apply to the next session unless you apply them.** The routes write config; a running
  chat keeps its tools. Apply to the Open Chat sends `reload.mcp` `{session_id, confirm: true}` on the
  agent's attached chat, offered only while one is attached. It never sends `always`, which would turn
  off Hermes's cost warning for good. The cost: the prompt cache is dropped, so the next reply sends
  the whole conversation again. The two dialects differ: the authority reconciles only that profile's
  servers and refreshes every chat of the profile (`gateway/session_ancillary.py`); the legacy
  handler tears down and rediscovers every MCP server in the process, cutting other chats' running
  MCP calls. A sign-in doesn't ask to apply: Hermes reconnects the server itself when the flow's
  profile is the gateway's own (`reconnect_live`).
- **Sign-in opens the system browser** through `openURL`, on Mac and iPhone alike, and the list asks
  `/oauth/flows/{id}` every 2 s until `approved` or `error` (or 16 minutes; Hermes drops a flow after
  15). Cancel sends `DELETE`. Not `ASWebAuthenticationSession`: the provider redirects to the
  gateway's own `/api/mcp/oauth/callback/<name>`, not to an app scheme, so that session would never
  complete and would sit on the gateway's "Authorization received" page until cancelled.
- **The list doesn't probe servers.** Testing starts each server on the gateway, so tool counts come
  from a test, run when you open an app or press Test Connection, and last for the app session.
- **Secrets.** Bearer tokens and catalog keys go only in the request body and aren't kept or logged.
  Errors pass `VaultRedaction.scrub` with the values just sent. The gateway masks env values in the
  list; `MCPServer` keeps only the names. On an unencrypted address (`GatewayAddress.isUnencrypted`)
  the model refuses to send a token or key without that send's consent, as the vault does. Every
  catalog key shows in a secure field, since the catalog doesn't say which are secret.
- **Out of scope:** Nous-hosted connectors (they need a Nous login), toolsets, the plugin catalog,
  per-tool switches (`tools.configure`), editing a server, env values for a custom program, and the
  whole-map `PUT /api/mcp/servers`. Rooms have no apps view; apps belong to an agent, from its chat.

## Not verified

- These live activity cases have only run from fakes, never from a real turn: provider waits,
  compression status, `tool.progress` (MCP tools only), `notification.show`, `reasoning.delta`, and a
  helper still running when its turn ends (in live runs it finished first). To-do lists, helpers and
  all three room actions have run through `AppModel` on a live dashboard socket, but not in the real
  app window: its UI was checked in the demo.
- Sections against a live gateway: `profiles.configure` is confirmed from the Hermes source only,
  never run on the app's dashboard socket. Dragging between sections and Esc in the name field
  haven't been run, because both need the real pointer or keyboard on the Mac.
- Agent defaults against a live gateway; they're left out of shakedowns because they change an
  agent's default model everywhere.
- iPhone on a real device beyond sign-in: calls, dictation and GPT-Live audio routing.
- Notifications on a real gateway. A reply, a question and a room reply ran through the plugin on a
  live throwaway dashboard, with a fake ntfy service and the session token, not the app's own
  sign-in. Send Test from the app has reached an iPhone through real Pushover and real ntfy; ntfy's
  arrived late, though its server had the message at once, so the delay is between ntfy and the
  phone. Tapping an ntfy alert opened its chat on iPhone. Not yet seen on real devices: pushes held
  while focused, released when a Mac's screen sleeps, or held by the quick panel. Not yet run: a
  real approval (Hermes didn't flag the commands tried), a room approval, a
  `/bg` task (it may notify twice on the Mac), and a routine's message. iOS background check-ins
  can't be forced in the Simulator, so `BackgroundLink` has only run through unit tests of
  `AppModel.checkIn`.
- Apps against a real gateway: nothing in the Apps tab has run against one, by design, since it
  changes real agents. The routes, bodies and flow states are read from source and run against fakes
  and the demo. Unknown: whether the native sign-in's bearer passes `_require_token` on `/auth` and
  `/oauth/flows` (it should, as `native_http_principal`), how long a real test or catalog install
  takes, and `reload.mcp` on either dialect.
- Routines against a real gateway: create, edit, delete, Run Now and past runs have run only against
  fakes shaped from the Hermes source and in the demo, never on a gateway, because each costs money
  or changes a real agent. The iPhone layout of the routine sheets hasn't been looked at.
- The vault beyond a loopback client on the legacy dialect: `vault.unlock_prompt` and `vault.code`, a
  real password manager, a client on a remote address, and the authority path. Sign-in, secret cards
  and the background bar were run against a real gateway on the Mac and in the iPhone Simulator,
  and sudo and adding a login on the Mac. Scrolling away from a chat's end was tried only on the Mac.
