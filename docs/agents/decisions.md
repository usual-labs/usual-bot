# Usual Bot: product and gateway decisions

Why the app works the way it does, where the code can't say so. Everything through M23 is built;
`git log` and the changelog hold the history.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its contract
(`apps/shared/src/gateway-contract.openrpc.json`). The app speaks the Webapp ([canonical](canonical-protocol.md))
and the dashboard socket (legacy). Confirm a call against a real gateway before building on it.

## Scope

- **The app needs iOS 26 and macOS 26,** so it can use the system's own controls and Liquid Glass
  everywhere without a second look for older systems. It also removes a launch failure on iOS 18:
  the iOS 26 SDK links WebKit's Swift library, which iOS 18 doesn't have.
- Usual Bot is a messenger for Hermes agents. Agent configuration, provider keys, skill setup and
  gateway administration stay in the official app, except what the developer chose to bring in: an
  agent's routines, its MCP servers (the Apps tab), and making, renaming and deleting Bots.
  Device-local preferences belong in Usual Bot.
- **User-facing text calls them Bots,** never agents, to match New, Rename and Delete Bot, Hermes's
  own Bot Mode and Bot Chat, and the Grok-style naming of Create. "Agent" stays in code, logs,
  developer docs, Hermes's product name (Hermes Agent) and text sent to the model.
- Fast mode isn't built. Only a message that starts with a command runs it; a `/skill` later in the
  text is sent as written, as in the official app.

## Messages

- **PDFs go through `file.attach`**, as the official Bot Chat does. `pdf.attach` needs `pdftoppm` on
  the gateway and sends only page images. Limits are 25 MB per image (the gateway's) and 50 MB per file.
- **Gateway files load through `/api/fs/read-data-url?profile=`.** `/api/media` serves only the
  default profile's image folders.
- **Audio and video download whole through `/api/fs/download?profile=`, then play from a file.**
  `AVPlayer` can't send the bearer token, the data URL route caps at 16 MB and base64s everything,
  and the official app's `/api/files/stream` follows the file browser's rules, not a profile's.
  An `AVAssetResourceLoader` could stream with Range requests, but SSH-backed profiles stream
  without Range support, so it would need a whole-file fallback anyway. Copies live in a
  per-process temporary folder (a Mac's temporary folder is shared by every copy of the app
  running); sign-out and the next launch delete them.
- **A voice memo's transcript is the `text_to_speech` call's `text`.** Live, `tool.complete`
  names the files the call made; `session.history` keeps only the arguments, so calls pair with
  a reply's audio in order and only when the counts match. Rooms carry no tool calls, so their
  voice replies have no transcript. Voice style also comes from `[[audio_as_voice]]` (hidden, as
  the gateway hides it) or the tool's default `tts_<date>_<time>` name.
- **Agents often name images in plain text.** `MEDIA:` lines appear only when Hermes tells an agent
  the surface renders them, and sessions the desktop app didn't create may get terminal
  instructions. So an absolute path ending in an image type also becomes an image.
- **Undo is `session.undo`, then `session.history`.** Edit is undo plus an ordinary send, as the Ink
  TUI's `/retry` does. An edit keeps text and `@file:` references; images must be attached again.
  `truncate_before_row_id` (rewinding further back) isn't used.
- **Reactions are display-only in Hermes.** The agent's model never sees them, and rooms have no
  reaction call.
- **Send while a reply runs still steers; Queue is the second button.** The official app follows
  Hermes's `display.busy_input_mode`, whose default is `interrupt` (the terminal's is `queue`).
  Following either would change what Send has always done here without anyone asking, and
  interrupting on Send loses work. So Send steers, Queue (⌥Return) queues, and there's no setting.
- **The queue is the gateway's, not the app's.** Hermes keeps one FIFO per chat and runs it with
  no app attached, which is the point on an iPhone that gets locked. So there's no queue on the
  dashboard, whose queue can't be listed or taken back: the button is hidden there, not faked.
  Attachments aren't queued (uploads are staged for the next message, not a later one).
- **Stop holds the queue.** Hermes starts the next queued message the moment a reply is
  interrupted, which reads as Stop not working (the official app parks its queue for the same
  reason). The app takes the queued messages back first and keeps them on the device, in the
  offline cache, until Resume.
- **A goal is Hermes's state, shown and never kept here.** `/goal` sets a standing goal on the
  chat's session; after each turn an auxiliary model judges it (done, blocked, wait, continue) and
  the gateway admits the next turn itself, with no app attached. The app reads it
  (`session.control.read`, `session.control.update`) and changes it only through
  `session.control`. It never calls `session.automation`: that marks the session as driven by its
  viewer, and the gateway then stops judging and continuing it.
- **Hermes's "paused" reads "stopped" here, with its reason.** Hermes has no stopped state: you,
  the turn budget and a "blocked" verdict all pause. The bar says which. Stop Goal is
  `goal.pause`, then taking back any continuation already queued, then interrupting the reply,
  in that order: an interrupted reply that said anything is judged like any other and the next
  turn starts at once. Pausing alone would let the reply run on, which isn't what Stop means.
  Continue is `goal.resume` (which resets the budget) and Clear is `goal.clear`.
- **The message box's Stop doesn't stop a goal.** It ends one reply, as it always has, and the
  goal carries on; the chat says so, and the button's label does while a goal works. Making it
  stop the goal too would leave no way to cut one reply short.
- **"Not running" is a state of its own.** A goal can be active with nothing running and nothing
  queued (a reply stopped before any text, a failed turn, a gateway restart: seen on the
  throwaway gateway). Showing that as working would be a lie, so it has its own words and
  Continue.
- **A goal's own turns are a line in the chat, not a message.** Hermes stores its continuation
  prompt as a user row; the app shows "Carried on with the goal" there, by the prompt's wording,
  so it also holds for the one Continue sends from here. Undo therefore goes back past them.
- **`/goal` and `/subgoal` run while a reply does**, as Hermes allows; other commands still wait.
  What they print is left out when the goal bar already shows the change. A new goal typed
  mid-reply is refused here, in the app's words, instead of with Hermes's line about `/stop`.
- **No form for setting a goal, and no editing of added criteria.** `/goal <words>` from the
  message box is the way in; criteria added with `/subgoal` show in the bar. A sheet for either
  wasn't small.
- **A goal ending by itself notifies like a background task** (the same setting), only while the
  app is connected: Hermes has no hook the push plugin could send it from.
- **Rooms have no goals.** A goal belongs to one session and its queue; a room's turns are run by
  the room.
- **Loops and heartbeats aren't shown.** They share the goal's calls and snapshot
  (`session.control`'s `loop` and `heartbeat`) and would be the same kind of bar.
- **Rooms and the ⌥Space panel don't queue.** A room message already runs as its own task per
  member beside the replies under way, so there's nothing to wait behind. The panel is for one
  message and its answer; what it sends to a busy Bot steers, as before.

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
- A chat's usage meter shows tokens, never cost: Hermes keeps no cost for a chat, and working one
  out from price lists would guess at cache reads and model switches.
- **Settings › Usage shows only what Hermes reports,** from `GET /api/analytics/usage?days&profile`,
  one call per Bot, since each profile keeps its own store. Cost appears when Hermes has one: the
  provider's `actual_cost`, else Hermes's `estimated_cost`, labelled as an estimate. Background work
  (`by_task`) adds to the sessions' counts (Hermes never writes it into them) but has no days, so
  the chart leaves it out. Periods are the official app's 7, 30 and 90 days.
- **Not used for usage:** `usage.bars` is the Nous subscription's dollar meter (`agent.billing_usage`),
  and `insights.get` counts sessions and messages only.
- **Rooms have no row of their own.** A member's room turns run in a `bot_room` session in that
  member's profile, so they're in its Bot's numbers and can't be told apart in the report.
- **No per-chat split.** The report has none; `/api/sessions` rows carry lifetime totals per session
  but not by day, so a "by chat" list would disagree with the period. The chat keeps its own meter.

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
- **On the dashboard, Dismiss is `groups.stop`.** `groups.discard` isn't on its method table, and a
  retryable task blocks the room (`driver_status.blocked`). `groups.stop` cancels every stoppable task
  in the room, retryable ones included (`_STOPPABLE_STATUSES` in Hermes's `hosted_room_service.py`),
  so it's a real dismissal, not a local hide. It also stops other members' turns, and the retry card
  says so while any are running, waiting or stopped. Source finding; not run against a gateway.
- **Whose retry it is is a guess.** A `retry` action carries only `task_id`. The card names the member
  who left `member_activity` as the retry appeared, and only when exactly one did; otherwise it says
  "A reply". The guess isn't cached, so after a relaunch the card is unnamed.
- **A room's lead, routing, purpose and notes are one record,** Hermes's room "context", read from
  `groups.state` and saved whole by `groups.context` (`gateway/hosted_room_context.py`, v0.23.1).
  So Room Settings is one sheet, and a change of lead sends the purpose and notes as they are.
  `groups.create` takes none of it: New Room creates, then sets the routing, and a refusal there is
  said in the room, which exists by then. A lead exists only while routing is `lead`.
- **What the gateway takes is read, not assumed.** No `context` in `groups.state` means no room
  settings (the panel says they need Hermes 0.23); a context without `routing` means purpose and
  notes only, and routing keys aren't sent, as the canonical listener refuses keys it doesn't know;
  `driver_status.routing_modes` lists the choices, and without it they're everyone and a lead.
  New Room has no room to read, so it takes the modes from a room already read, else from
  `groups.capabilities.methods`: `groups.context` for a lead, and `groups.continue` for `auto`,
  which came in the same Hermes change. That last step is an inference.
- **Routing applies to every message the app sends,** because each goes out as a new thread:
  Hermes skips the lead and the router for an `@name`, `@all`, a routine's post and a message in a
  thread already going (`routes_through_lead`).
- **"X is picking who answers…" is worked out from the log.** The lead's routing turn shows in
  `member_activity` as an ordinary running turn, so `RoomState.choosingLead` applies Hermes's rule
  to the newest message until its `room.assignment` lands. `auto` shows nothing while it picks:
  the room isn't `working` during the router's call.
- **Continue is for the newest message only.** `groups.continue` reopens a discussion paused at
  its cap (`room.activity` `bounded`), up to `max_continues` times. Hermes would take one past a
  later message in another thread; the app shows one conversation, so a later message or a stop
  ends the offer. The card isn't shown beside a retry or an approval, and isn't a needs-you state.
  **Leave It** hides it on this device until the app restarts: Hermes has no call to decline one.
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

- **Push goes through Usual's own relay, sealed for each device.** ntfy and Pushover arrived late or
  under another app's icon, so the developer chose Apple's push under Usual Bot's own name. Apple's
  key belongs to the app's signer, so a relay we run (`Services/push-relay`, a Cloudflare Worker and
  D1 at `push.usual.dev`) holds it. The gateway plugin (`Integrations/hermes-push`) seals each
  notification with a key that only that device and its gateway have, and the app's notification
  extension opens it. The relay and Apple see a generic "New message" and which device it's for,
  never the text, the Bot or the gateway. This replaces the earlier rule that a relay of ours would
  break "Private".
- **The gateway keeps the choices; the relay keeps only addresses.** Each device's choices, muted
  chats and keys live in `~/.hermes/usual-push/settings.json`, shared by all profiles. The relay's D1
  holds the APNs token, its environment and hashes of two secrets: the device's own, to update or
  remove its row, and the send key that lets its gateway push to it. There are no accounts. A
  gateway can push only to devices that handed it a send key.
- **No Firebase.** Its messaging is free, but it needs Google's SDK in the app, which breaks
  "no third-party packages", and it adds Google as another party that sees every push. A deployed
  Worker reaches APNs over HTTP/2 itself. Local `wrangler dev` can't, so test on a deployed Worker.
- **Every device hears every message, unless that chat is open on one of them.** An open chat means
  a window in front with that chat selected, or the quick panel. It quiets every device, so reading
  on the Mac keeps the iPhone still. Another chat's message still notifies, even inside the app; this
  replaces the earlier rule that nothing notified while you were at the app. On the device itself,
  `willPresent` also hides a push for the chat on screen, as the gateway may not know yet.
- **The app reports the open chat every roster tick, and "none" once,** and the plugin forgets an
  entry after 15 s, so a crash can't silence pushes. Repeating "none" would let a Mac in the
  background overrule the iPhone in your hand.
- **Muting is per device and per chat, and everything starts on.** Settings › Notifications lists
  Bots; the plugin skips a device whose `muted` holds the chat. Messages, "needs you", previews and
  sound are per device too, taken from that device's Alerts switches.
- **A hidden Bot is quiet on every device, except in rooms.** Hiding is the official app's
  `ui_meta['hermes-bots'].hidden`, which Hermes keeps in the profile's `profile.yaml`; the plugin
  reads it there before each push from that Bot's own chat, rather than each app muting it, so a Bot
  hidden in the official app is quiet too and showing it again doesn't undo a mute you chose. Rooms
  aren't hidden, so a hidden member's room replies still notify. A gateway with plugin 0.2.0 still
  pushes for hidden Bots until it's reinstalled. The official app shows a Bot again by writing
  `hidden: false`, and so does this one.
- **Once the gateway pushes to a device, its own alerts cover only background tasks,** or each
  message would arrive twice. A build without push keeps local alerts for everything.
- **Push is off unless the build sets `USUAL_PUSH = YES`.** It needs a paid team with Push
  Notifications on for the bundle ID, so CI, unsigned and forked builds go without, and say so in
  Settings. Our key reaches only `labs.usual.UsualBot`; a fork runs its own relay.
- **Builds ship only through TestFlight, on the Mac and the iPhone.** Xcode makes the distribution
  profiles itself there, push included. The notarized GitHub download and its Homebrew cask would
  have needed two hand-made Developer ID profiles to carry push, so the developer retired both after
  0.3.0. The entitlements say "development" and exporting for
  TestFlight makes them production, so the app reads which service it's on from its own profile
  (`PushRelay.appleEnvironment`) instead of a build setting that could disagree.
- **TestFlight builds learn about newer ones from App Store Connect, through `bot.usual.dev`.** An
  app can't ask TestFlight, and builds upload nightly, so a hand-published version file would lag or
  name builds still processing. The Worker (`Services/updates`) asks App Store Connect with an API
  key held as Worker secrets (a team key with `ASC_ISSUER_ID`, or an individual key without it),
  caches the answer for an hour, and the app checks every
  6 hours. It reports the newest processed build (internal testers) until `BETA_GROUP` names the
  external group. Only builds with `USUAL_UPDATES = YES` (`scripts/testflight.sh`) ask, so forks, CI
  and local builds never contact it. Build numbers are the upload time, so they compare as numbers.
  Deployed 2026-11-09 with an individual key; `GET /v1/latest` answered the processed 0.5.0 build
  for both platforms. A Debug build with `USUAL_UPDATES=YES` showed the banner from the live service
  on the Mac and in the iPhone Simulator, Later hid it, and Settings › About kept the link. Unverified: that `filter[betaGroups]` narrows `/v1/builds` as expected, and
  that `itms-beta://` opens the app's page in TestFlight on the Mac.
- **The relay's rate limits are a ceiling, not a guard.** Cloudflare's rate-limit binding counts per
  location and per instance, so bursts get through: on 2026-11-05, 40 sign-ups in a row from one
  address all passed, and 4 of 80 sent at once were turned away. They stop a sustained flood of
  sign-ups (by address, IPv6 by /64) or of pushes to one device. A strict limit would need a
  Durable Object or a Cloudflare WAF rule on the zone.
- **Signing out takes the device off the gateway** before the sign-in is revoked, or it would keep
  showing a gateway's messages after leaving it. A device whose relay address changed sends it
  again on the next refresh.
- **`post_llm_call` is the reply signal.** `platform` tells a person's chat (`tui`) from helpers
  (`subagent`) and rooms (`bot_room`). It doesn't name the room, and the member session's title
  doesn't either: Hermes retitles it after the first message. So the plugin takes the room from that
  member's `on_room_member_activity`, which can land just after the reply, hence a short wait.
- **"Needs you" for an iPhone-only user may be short-lived.** With no client attached the gateway
  doesn't wait on a prompt, so answering often means having the app, on any device, connected.
- A catch-up alert is the rise in `unreadCount` on attach, so no new state is cached. A running turn
  waits for `message.complete`.

## Read state

- **A Bot Chat's read time is Hermes's `sessions.last_read_at`,** the official app's Mark as Read, so
  reading on one device clears the count on the others (`ReadSync`). The count stays the app's own:
  replies after the later of this device's last look and that time. Hermes's own `unread` is a
  yes/no that your messages set too, as does `last_activity_at` moving mid-turn. The official app
  never reads it for Bots (a Bot Chat is hidden, so its dot is per window), so the two apps don't
  agree there.
- **A write needs a `request_id` and the chat's `expected_revision`** (`GET …/mutation-snapshot`)
  and moves that revision, which the chat's other edits share. A write that lost a race (409
  `revision_conflict`) is tried once more.
- **Reading it back costs the whole record.** `GET /api/sessions/{id}` sends the system prompt too
  (about 90 KB on the developer's gateway), and lists leave hidden chats out. `sessions.changed`
  comes at most every 2 s, on any session change, naming none, so the app looks only at chats unread
  here: the snapshot first, the record only when the revision moved.
- **Only while you're looking.** `visibleContactID` is set only while a window has you, so a Mac left
  on a chat doesn't mark replies read.
- **Rooms stay per device:** `hosted_rooms` has no read position and no field to keep one in.
- A gateway answering 400, 404, 405 or 422, or a record without `last_read_at`, turns sharing off
  until the next connection.

## Bot pictures

- `has_avatar` is true for nearly every Bot, because the desktop stores a 160 × 160 PNG of its drawn
  face. That size counts as a picture only when `imageKind` is `photo`. Uploads are 256 px.
- The roster refreshes every 5 s, so a picture is read again only when its revision changes, and
  once per connection. `profiles.set_asset` alone doesn't bump the revision, so a picture change
  also writes `imageKind` (`photo`, or `shape` when removed) through `profiles.configure`, as the
  desktop's `saveBotMeta` does. That write is what makes other clients read the new picture.

## Managing Bots

- **Create asks only for a name, a picture and what it's for,** like Grok's Create New Bot. It sends
  what the desktop's Bot Mode sends: `profiles.create` with the slugged name as the profile ID,
  `share_auth: true`, a composed `SOUL.md` and the description, then the title in
  `ui_meta['hermes-bots']`. No `clone_from`, so the Bot gets Hermes's bundled skills and the launch
  profile's provider keys and model (`mirror_credentials`). `setup.runtime_check` on the new profile
  says whether it can reply; if not, the sheet says so instead of opening a chat that fails. No
  introduction turn: it would spend a model call.
- **Names follow the desktop's `slugifyProfileName`** (`BotName.slug`), so a Bot made here gets the
  same ID it would there. Validation checks the ID against Hermes's rule, its reserved names and the
  roster.
- **Rename changes the title, never the profile ID,** as the desktop's Edit Bot does. Changing the
  ID (`PATCH /api/profiles/{name}`) stops the Bot's gateway and moves its folder, and every piece of
  client state is keyed by it. An ID renamed elsewhere shows up in the roster's `previous_names`;
  `AppModel.followProfileChanges` moves the chat, cache, picture, section, lists and open selection
  to the new ID (`renamedAgents` maps old IDs for views still holding one). Hermes never forgets an
  old ID and lets a new profile take one, so several rows can list the same old ID: the chat goes to
  the row holding its Bot Chat, else the one with its name, else nowhere.
- **Delete is REST only** (`DELETE /api/profiles/{name}`; no socket method). It takes the whole
  profile folder, so the sheet lists what goes and asks for the name typed, as `hermes profile
  delete` does. The default profile can't be deleted. Rooms keep a deleted member: Hermes freezes a
  room's roster, so the sheet says the Bot stays listed but can't answer, and leaves the room alone.
- **Roster holds.** A Bot just made, renamed, re-pictured or deleted is held over the next three
  5 s roster reads (`RosterHolds`), or a read from before the change would undo it on screen. A Bot
  that leaves the roster without a hold is forgotten locally: chat, cache entry, picture and
  section.

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

## Pinned chats

- **A Bot's pin is the official app's `pinned` in `ui_meta['hermes-bots']`,** so a Bot pinned in
  either app is pinned in both. A room's pin stays on the device, as in the official app, which
  keeps it with its own list of rooms. `SidebarSections` saves a pin through the same queue and
  holds as a section move, so the two can't overwrite each other's write of `hermes-bots`.
- **Pinned chats are tiles above the sections, as in Grok,** not rows with a pin as in the official
  app. A tile has no preview, so its badge carries what's waiting.
- **A pinned chat keeps its section but isn't listed in it,** so folding a section can't hide a
  chat you pinned, and unpinning puts it back. Its menu leaves out the section items and it can't
  be dragged, since moving it would show nothing. Deleting a section still asks when only pinned
  chats are filed under it.
- **Search and the rail have no tiles.** They list pinned chats first as rows; a search marks them
  with a pin, and the rail draws a line under them.

## Search

- **The device first, the gateway for chats it doesn't hold.** Online, every agent with a Bot Chat
  is attached at connect with its whole history (up to `sessions.max_resume_messages`), and each
  room's log is read in full, so the device's own search is nearly complete and instant. The
  gateway (`GET /api/sessions/search`, one call per profile, at most four at once, 350 ms after
  typing stops) is asked only for Bot Chats not yet loaded whole: before they attach, or attached
  without history (`historyOmitted`). It returns one hit per conversation, so it adds at most one
  "Earlier" result per Bot, after the device's dated ones. Hits from other sessions (Telegram,
  CLI, cron, room plumbing) are dropped: the app can't show those chats. Opening one attaches the
  chat and finds the message by the snippet's words; a chat attached without history can't open
  at it. Offline, it's the cache's last 60 items per chat and no rooms, and search says so.
- **Only your and the agents' text,** not tool steps, command output, background results or the
  turns Hermes starts itself, and a reply's quote is left out because the quoted message has its
  own hit.
- **Newest first across every chat, up to 50.** Messages carry the gateway's time (or when they
  arrived). Those without one, from a cache written before times were kept, come after, chats in
  order of last activity.

## Masked prompts

- **Never answer `secret`, `sudo` or `vault.*` with 4404.** With no other client attached, Hermes
  takes the error as the answer (HermesKit known issues). Without a card, answer `{"value": ""}`,
  which is Hermes's skip. Rooms show no cards, so their requests get the skip too. On the
  [Webapp](canonical-protocol.md) they get no answer at all: any answer settles them for every app.
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
- **Templates create through `POST /api/cron/blueprints/instantiate`, not `/api/cron/jobs`.**
  `GET /api/cron/blueprints` sends each template's fields and schedule template but not its prompt
  or skills (`blueprint_catalog_entry` in `cron/blueprint_catalog.py`), so only Hermes can fill the
  prompt. The form asks the fields, shows the schedule they make (worked out as `_resolve_schedule`
  does) and the Results choice in place of the `deliver` field; the created routine then opens with
  Edit for everything else. This is the official dashboard's and desktop app's path too.
- **Skills a template can't load are named after it's created.** The job it returns lists them, and
  `/api/skills` says which are missing or off. Hermes skips a skill it can't load and runs anyway
  (`_load_cron_skill_parts`), so the routine stays, with a note saying how to fix it. Templates
  declare no tools or connected apps; their prompts tell the agent what to do without them.

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
- **Out of scope:** toolsets, the plugin catalog, per-tool switches (`tools.configure`), editing a
  server, env values for a custom program, and the whole-map `PUT /api/mcp/servers`. Rooms have no
  apps view; apps belong to an agent, from its chat.

## Connected apps (connectors)

- **Connectors aren't MCP servers.** They're accounts at the Nous Portal's tool gateway (Gmail,
  Slack, Notion…), used through Hermes's own tools, and need a Nous Portal identity on the gateway
  (`connectors_available`). One `manage_connections` call can also ask for MCP servers
  (`kind: "mcp"`), so the chat card covers both. Read from Hermes `bf0203a794`:
  `tools/connectors/{operation,run,managed,mcp,contract}.py`, `tui_gateway/methods_connectors*.py`,
  `tui_gateway/contracts/connectors*.py`, and the desktop's `connector-tool.tsx`.
- **The card is an event, not a server request.** `connection.request` opens it and every
  `connection.update` carries all rows with a `seq`; older frames are dropped. The turn waits on the
  operation (5 minutes, `OPERATION_DEADLINE_SECONDS`), not on an answer to us, so there's no 4404 to
  worry about. Answers: `connection.respond` with a session owner (`skipped` for Not now, `approved`
  for an MCP install/enable and for running a failed MCP row again, `settled_by: continue` for a
  list's Done); Try Again on a hosted row is `connectors.connect` `{reconnect: true}`, which mints a
  fresh link. The card never claims an app connected; Hermes's watcher does.
- **One card per chat, kept offline.** Hermes allows one open operation per session. The card stays
  through a drop with its buttons off, since a sign-in may be under way; on reattach
  `pending_connection` restores it, and its absence ends it with a notice (the outcome isn't known).
- **When it ends, it becomes notices,** like approvals: connected, Not now, and what didn't connect
  and why (time, a stopped reply, going on without it). History has no card to rebuild: Hermes keeps
  only the tool row, without its result, so an earlier request shows as a `manage_connections` step.
- **iPhone uses the system sign-in sheet** (`WebAuthenticationSession`), not Safari as the MCP page
  does: no page ever returns to the app, so the card cancels the sheet once Hermes reports the app
  connected. Hosted connectors sign in on the internet, so a tailnet gateway needs no VPN for them;
  an MCP row's provider still returns to the gateway's own callback.
- **No reason line.** The payload carries no "why"; the card shows MCP setup notes (`instructions`)
  when there are any, and the agent's reply above says why.
- **Not here:** rows Hermes wants credentials typed for (`required_env`) and catalog plugin or skill
  rows say to finish in the Hermes app; a list card (`display`, desktop sessions only) has only Done,
  and apps are connected from the Apps page. Named accounts (aliases) and renaming aren't offered.
- **Rooms show no card.** Room members run without `connection_callback` (only
  `agent_factory._agent_cbs` sets it), so Hermes puts the link in the member's reply instead.
- **The Apps page** uses account-owned `connectors.list`, `connectors.catalog`, `connectors.accounts`,
  `connectors.connect` and `connectors.accounts.remove`, each with `profile`, and polls
  `connectors.operation.status` every 2 s: account frames are broadcast without links and the model
  needs no global-event routing. Disconnect removes every live account of that app from the Nous
  Portal, so it says it affects every agent. Hidden when `available` is false or the gate says 4031.

## A Bot's browser

- **The browser view comes from the `usual-browser` plugin, not Hermes.** Hermes has no way to watch
  a headless real-profile browser (`browser.use_real_profile`). Its Bot Screen is a Linux desktop
  only. The plugin's dashboard route attaches to that browser's DevTools port and streams CDP
  screencast frames. A plugin route keeps it working without changes to Hermes; the cost is that it
  checks sign-in with a private Hermes function (`_ws_auth_ok`), which an update could change.
- **Watch only.** Input is a later step; the feed ignores what the app sends.
- **Text and frames are told apart by their first byte.** `ScreenSocket` hands over text and binary
  messages alike, as bytes. The feed's text is always a JSON object (`{`), and JPEG and PNG never
  start with one.
- **The Plugins sheet guides, it doesn't administer.** The developer asked for a home for the
  browser and computer setup (November 2026): a puzzle-piece button in the Mac sidebar's footer,
  between the gateway and Settings, not a Settings tab (tried, and turned down). Mac only; the rail
  leaves it out, keeping Expand Sidebar and Settings. It reads the plugin's status (404 means no plugin,
  `BotBrowser.hasPlugin`) and `display.status` per Bot, and offers commands to copy; it never sets
  `browser.use_real_profile` or installs anything, as gateway administration stays in Hermes. The
  copied `hermes … config set browser.use_real_profile true` hasn't been run against a gateway, and
  the headless requirement has no command here. It lists every Usual gateway plugin (push from
  `PushSettings.phase`, browser from `BotBrowser.hasPlugin`). **Ask a Bot** (the developer's pick
  over an app-side shell, SSH or a setup route in our plugin) fills the chosen Bot's box with the
  steps through `ChatThread.prefill` and opens its chat; it never sends. The request tells the Bot
  to stop if its terminal is sandboxed, and to restart the gateway last, since the restart drops
  the chat. Not yet run with a real Bot.
- **The Browser button shows only for a Bot whose status says `available`**: real profile on and
  headless. A gateway without the plugin answers 404, so the button stays hidden.

## Not verified

- Goals ran against a throwaway Hermes 0.23.1 gateway with a stand-in model and a stand-in judge,
  from a script on its socket (`canonical-protocol.md`), and in the app only in the demo. Not run:
  the app itself on a real gateway; anything on the dashboard, whose goal calls and events are
  from the source only (it ends a reply before judging it, which `isCheckingGoal` covers); an
  approval or question during a goal's turn; a goal parked on a background process; quality
  gates and contracts (`/goal gate`, `/goal draft`), which the bar doesn't show; and the official
  app showing the same goal.
- The message queue ran against a throwaway Hermes 0.23.1 gateway with a stand-in model, from a
  script on its socket (`canonical-protocol.md`), and in the app only in the demo, on the Mac and
  in the iPhone Simulator. Not run: the app itself on a real gateway, an iPhone device, a queued
  message behind an approval, the official app showing the same queue, and `queue_full`.
- Read state: its routes were run on the developer's gateway on 2026-11-08 by a script signed in
  the app's way (native PKCE on the dashboard): the snapshot, a PATCH on a hidden Bot Chat, a stale
  revision's 409 and `sessions.changed` on the dashboard socket. The app itself hasn't: a Mac and an
  iPhone clearing each other's counts is untested.
- The Browser view hasn't run in the app against a real gateway: the plugin's feed and `BotBrowser`
  were each tested on their own (`BotBrowserTests`, and a script client on the developer's gateway).

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
- Notifications through the relay were run on the developer's gateway on 2026-11-05: sealed replies
  reached a Mac and an iPhone and opened in the extension, an open chat on either kept both quiet,
  and muting a Bot on one device left the other hearing it. Not yet run: a room approval, a `/bg`
  task, a routine's message and Apple rotating a token. TestFlight builds of 0.3.0 on the same Mac
  and iPhone moved themselves to Apple's production service and got their tests the same day. iOS
  background check-ins can't be forced in the Simulator, so `BackgroundLink` has only run through
  unit tests of `AppModel.checkIn`.
- Apps against a real gateway: nothing in the Apps tab has run against one, by design, since it
  changes real agents. The routes, bodies and flow states are read from source and run against fakes
  and the demo. Unknown: whether the native sign-in's bearer passes `_require_token` on `/auth` and
  `/oauth/flows` (it should, as `native_http_principal`), how long a real test or catalog install
  takes, and `reload.mcp` on either dialect.
- Routines against a real gateway: create, edit, delete, Run Now and past runs have run only against
  fakes shaped from the Hermes source and in the demo, never on a gateway, because each costs money
  or changes a real agent. The iPhone layout of the routine sheets hasn't been looked at. Templates
  (`/api/cron/blueprints` and `/instantiate`) were run on a real gateway on the Mac: the catalog,
  creating from one, a bad time's message, Run Now and Delete.
- Managing Bots ran on a real gateway (Hermes `bf0203a794`) on the Mac, with throwaway Bots: create
  (it chats at once), rename, picture, remove picture, delete (about 2 s) and renames by `hermes
  profile rename` with the chat open. Unknown: delete while that Bot is replying, whether
  `share_auth` copies sign-ins the way the desktop expects, a room turn addressed to a deleted
  member, the picture in the official app, and the iPhone sheets on a gateway.
- The vault beyond a loopback client on the legacy dialect: `vault.unlock_prompt` and `vault.code`, a
  real password manager, a client on a remote address, and the authority path. Sign-in, secret cards
  and the background bar were run against a real gateway on the Mac and in the iPhone Simulator,
  and sudo and adding a login on the Mac. Scrolling away from a chat's end was tried only on the Mac.
