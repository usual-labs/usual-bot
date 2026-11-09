# Usual Bot: the canonical protocol (the gateway's Webapp)

Why the app speaks the gateway's own listener, and what it has to do there that the dashboard
didn't need. Hermes facts come from a source checkout (`b200f5bc60`, v0.22.7) and a throwaway gateway
run from it with a stand-in model.

## Why

- **Routines and other Bots can only post into a canonical Bot Chat.** Cron's `deliver: bot-chat` and
  Bot-to-Bot messages find the chat's live owner with `find_canonical_live_owner`
  (`tools/bot_live_delivery.py`). The dashboard holds an open Bot Chat as an owner of its own, so
  while the app is connected there the delivery has nowhere to go. On the Webapp the same delivery
  runs as a live turn in the open chat.
- **One translator, not a second chat.** `CanonicalProtocol` and `JSONRPCChannel+Canonical` turn the
  canonical protocol into the legacy shapes, so `ChatThread`, `RoomThread` and the UI have one path.
  The legacy dialect is unchanged.

## Decisions

- **Every call about a session carries its `profile`** (`CanonicalProtocol.profileRouted`). Without
  it a Bot other than the gateway's launch profile answers `not_found` or `permission_denied`. Other
  methods have closed key sets and refuse a key they don't know, `client.capabilities` included.
- **Fences come from everywhere and only move forward.** `revision` and `execution_generation` change
  on every turn and edit; they're read from results, refusal `data`, every event's envelope,
  `session.info` and `session.updated`. An exact retry's receipt replays older numbers. A mutation
  is retried once on `revision_conflict` or `stale_generation`.
- **Approvals and questions are events** answered by `approval.respond` and `clarify.respond` with
  the turn's generation; `*.settled` withdraws them. The app asks one question per card. Hermes can
  batch them (`canonical_clarify_batch`), but that needs `clarify_batch` on `prompt.submit` and
  `clarify.lock`, and the per-question form works.
- **Never answer a request the app doesn't show.** The canonical owner
  (`gateway/session_server_requests.py`) settles a request on any response, an error included, for
  every attached app: there's no 4404 vote as on the dashboard. So no decline, and no skip without
  a card; the official app still gets to answer.
- **A Bot Chat is made with `session.create` and its title,** which finds or creates under the
  gateway's lock, with `source: "tui"` so the push plugin's reply hook counts it.
- **A steer is sent again only on `delivered: false`.** A plain `rejected` can follow delivery
  (`CanonicalCorrectionAck` in Hermes's contract), so the app says it couldn't confirm instead.
  Stop is retried once on `stale_generation`: the gateway moves the generation when it takes a
  message, before the turn's first event.
- **Attaching mid-reply reads the replay frames** for the reply so far and for approvals and
  questions asked since the snapshot. What arrives between that read and the attach is still lost,
  the same window the dashboard has. Hermes keeps a session's last 512 frames (fewer when they're
  large), and asking from further back returns none, only `truncated`: so the read starts 511 frames
  back, then 127. A turn longer than that shows its reply so far from partway.
- **Images ride with the message.** `image.attach_bytes` only stages a file; the paths go as
  `prompt.submit`'s `attachments`. Taking one back is local.
- **Undo rewinds to your last message.** There's no `session.undo`: the app reads `session.history`
  and rewinds to the newest row `GatewayTurn` reads as yours, skipping routine results and other
  rows Hermes starts itself.
- **Closing detaches this app's subscription only** (`session.detach`). A `session.replay_gap`
  detaches too; the next roster refresh attaches again with a fresh snapshot.
- **Rooms dismiss with `groups.discard`** when the retry action offers only discard, which needs the
  turn's `member_id` and `execution_generation`. It leaves the room's other replies running.

## Traps

- **The push plugin's request hooks see `platform: "local"`** for every chat the gateway owns, a
  terminal's or an editor's included; `hermes_cli.plugin_session.session_surface()` says which app
  (`tui`, `desktop`, `cli`, `acp`). The session's stored `source` is `local` too. Reply hooks see the
  app. A thread a hook starts sees the gateway's main Hermes home, not the profile's, so resolve the
  profile inside the hook.
- `message.delta` with `text: null` ends one stretch of streamed text. A queued message taken back
  sends `message.complete` with `outcome: cancelled` and no `status`: no turn ended.
- `tool.complete` sends its result as JSON text and failure as `is_error`.
- **A routine's turn starts with `message.start {}`**, without the delivered text or its kind. The
  app learns what it was from `session.history` once the turn ends (`finishTurnElsewhere`).
- **Attaching while Hermes runs a turn it started** (a routine's result, another Bot's message): the
  snapshot holds the text twice, as the stored row with its `display_kind` and as the running
  admission's `text`, with no submission id linking them. `legacySnapshot` matches the newest user
  row with a display kind by text; otherwise the message shows again as yours.

## Not verified

- Verified in the Mac app against a throwaway gateway with Claude, over plain `http` on a tailnet
  (`tailscale serve --tcp`): sign-in, a reply, an approval, a question, a routine's result arriving
  in the open chat, Bot-to-Bot messages both ways, steering, stopping, undo, reopening mid-turn and
  a two-Bot room. Not against the developer's gateway.
- iPhone, Tailscale Serve over `https`, and Built-in Tailscale with a `.ts.net` name.
- Room retry and discard (they need a member's turn to fail), and room approvals.
- `clarify.settled` gives no reason, so a question that timed out shows no notice.
