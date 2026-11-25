# Usual Bot: cross-project improvement ideas

## Planned/aspirational

- **Split `RootView.swift` (about 840 lines).** `ContactsSplitView` and its Mac layout, search jumps and
  sidebar footer share the file with `RootView`; moving `ContactsSplitView` to its own file is the
  obvious first cut.
- **Keep read-state revisions across launches.** Seeing another device's Mark as Unread means
  reading every Bot Chat's whole record (about 90 KB each) once per launch, as `ReadSync` keeps
  revisions only in memory. Saving them with the offline cache would make a launch cost snapshots.
- **Gateways on two tailnets.** The iPhone's built-in Tailscale is one device in one tailnet, so two
  gateways must share it or one must be reachable without it. A second tailnet needs its own
  Tailscale login and state on disk, and a way to pick the device per gateway.
- **Hermes features the app doesn't surface yet.** From a Hermes source read (`bf0203a794`,
  22 October 2026); none confirmed against a live gateway. Check each call on the gateway's
  Webapp first.
  - **Older messages in a chat over the resume limit:** search finds them through
    `GET /api/sessions/search`, but a chat the gateway attaches without history (over
    `sessions.max_resume_messages`, 20,000 by default) can't open at one. That needs REST pages
    (`/api/sessions/{id}/messages`, or `/timeline` and `/messages/around`) loaded into the
    transcript. Room logs aren't in the gateway's search at all (they live in the hosted-rooms store).
  - **A template's prompt before saving:** `/api/cron/blueprints` leaves out each template's prompt
    and skills, so New Routine shows them only once Hermes has created the routine. Seeing and
    editing them first needs Hermes to send them in the catalog.
  - **Read Aloud in the Bot's own voice:** Read Aloud speaks with the device's voice only. Gateway
    calls already speak through the profile's voice (`GatewaySpeaker`), so Read Aloud could too.
    Left out because it can bill the gateway's owner. If added, it's a choice in Settings › Voice
    that says it may cost money, never the default, and the device's voice stays the fallback
    offline.
  - **Agent's computer, what's left:** the package install (`display.install`, with its masked sudo
    prompt), the sandbox image switch (`display.switchSandboxImage`), Stop, the clipboard (Hermes
    turns the server's off; sending ours isn't wired) and Tight encoding. The viewer is in.

  - **Rooms, what's left:** the demo can't show a paused discussion (no gateway to pause one), so
    the Continue card is seen only with a temporary change to the demo's events. A room's routine
    target (`deliver: room:<id>@<profile>`) isn't shown, and a routine's post reads as yours.
    `auto` routing shows nothing while the gateway picks.

Child-local ideas stay in their package KBs.

- **Replay switch.** A debug switch that plays sanitized frames through the real channel, so a
  change can be seen working without a gateway. `AppModel.demo()` skips the channel entirely.
- **Contributor vouching, size labels and triage or stale bots.** Worth adding once outside pull
  requests arrive in volume; the repository doesn't have that yet.
- **Keychain without prompts on unsigned Mac builds.** `TokenStore` could use the data-protection
  keychain (`kSecUseDataProtectionKeychain`), which has no per-app ACL prompts, but it needs a
  team-signed app with a keychain access group; ad-hoc builds get `errSecMissingEntitlement`.
  Only worth it together with a migration of the existing login-keychain items.
- **Shared items the extension leaves for the app (iPhone).** The extension now sends itself when
  it can (`decisions.md`, Sharing from other apps); what it leaves still waits for the app to be
  in front. A local notification from the extension ("Open Usual Bot to send this to Forge") that
  opens the app on a tap would close that gap for built-in Tailscale, rooms and large files.
- **Goals: more than the bar.** Not built: a plainer way to set one than `/goal`; adding and
  removing criteria (`subgoal.add`, `subgoal.remove`); showing a contract and quality gates;
  pausing without stopping the reply; a push when a goal ends with the app closed (Hermes fires no
  hook at the judge's verdict, so the plugin has nothing to send it from); and bars for `/loop`
  and `/heartbeat`, which come in the same `session.control` snapshot.
- **Paths in a reply that open.** Bots name files in the text (`ops/outreach/notes.md`) that the user
  can't open; the plugin's chat context only asks them to send such files on a `MEDIA:` line too.
  The app could make a path in a code span tappable, load it the way `MEDIA:` files load, and
  resolve a relative one against the Bot's workspace as widgets do. A folder would need a file list.
- **Widgets in rooms that talk back.** Hermes has no hidden room turn, and a room's message goes to
  members, so `window.hermes.canSend` is false in rooms. It would need a hidden `groups` send and a
  rule for which member answers.
- **Queue: a choice of what Send does.** Someone who always queues has to press Queue each time; a
  setting would follow Hermes's `busy_input_mode`.
