# Usual Bot: product and gateway decisions

Why the app works the way it does, where the code can't say so. Everything through M23 is built;
`git log` and the changelog hold the history.

Gateway facts come from a Hermes source checkout (`81a55437f3f`, 26 September 2026) and its contract
(`apps/shared/src/gateway-contract.openrpc.json`). The app speaks the dashboard socket (legacy
dialect) and its REST routes. Confirm a call against a real gateway before building on it.

## Scope

- Usual Bot is a messenger for Hermes agents. Settings, provider keys, skill setup and gateway
  administration stay in the official app.
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

## Bot pictures

- `has_avatar` is true for nearly every Bot, because the desktop stores a 160 × 160 PNG of its drawn
  face. That size counts as a picture only when `imageKind` is `photo`. Uploads are 256 px.
- The roster refreshes every 5 s, so a picture is read again only when its revision changes, and
  once per connection. `profiles.set_asset` alone doesn't bump the revision.

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

## Vault

- **Remote clients may use it.** `tui_gateway/methods_vault.py` has no peer or loopback check; its
  docstring's "localhost" is descriptive. With a session authority, `AuthorityConnection.dispatch`
  answers -32601 for `vault.*` and `ws_legacy_fallback.py` lets the interactive grant run the same
  handlers.
- **Every call names `profile`.** Otherwise `_profile_scoped` uses the launch or ticket profile, so
  a call would reach the wrong Bot's vault.
- `VaultItem` has no field for a secret: `vault.list` is metadata, and it stays that way here.

## Not verified

- Agent defaults against a live gateway; they're left out of shakedowns because they change an
  agent's default model everywhere.
- iPhone on a real device beyond sign-in: calls, dictation and GPT-Live audio routing.
- The background task notification firing.
- The vault beyond a loopback client on the legacy dialect: `vault.unlock_prompt` and `vault.code`, a
  real password manager, a client on a remote address, and the authority path. Sign-in, secret cards
  and the background bar were run against a real gateway on the Mac and in the iPhone Simulator,
  and sudo and adding a login on the Mac. Scrolling away from a chat's end was tried only on the Mac.
