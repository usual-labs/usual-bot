# Usual Bot: cross-project improvement ideas

## Planned/aspirational

- **Hermes features the app doesn't surface yet.** From a Hermes source read (`bf0203a794`,
  22 October 2026); none confirmed against a live gateway. Check each call on the app's
  dashboard socket first.
  - **Search across chats:** `GET /api/sessions/search`. The app's search matches the contact
    list only.
  - **Playing audio and video:** a delivered non-image file shows as a file to save or share
    (`MediaView`), with no player.
  - **Connected apps:** `connectors.*`, the `connection.request` event, and MCP servers
    (`/api/mcp/*`).
  - **Managing Bots:** `profiles.create`, `PATCH /api/profiles/{name}`, `profiles.set_asset`. The
    roster only writes a Bot's section: no create, rename or picture change.
  - **Routines:** the Routines tab only switches a job on or off. `/api/cron/jobs` also creates,
    edits, runs and deletes, `/{id}/runs` gives history and `/api/cron/blueprints` gives templates.
  - **Live activity:** `status.update`, `todo.updated`, `reasoning.delta`, `tool.progress`,
    `notification.show` and `subagent.*` are ignored.
  - **Rooms:** `groups.rename`, `groups.disband` and `groups.retry`.
  - **Usage across chats:** `usage.bars`, `insights.get`, `/api/analytics/usage`.
  - **Bot desktop:** `display.*` with a ticket for `/api/display/ws` (raw RFB), Take over through
    `display.lease.*`. Largest of these: it needs a VNC viewer in the app.

Child-local ideas stay in their package KBs.

- **Jump to the end when you send.** Scrolled up, a message you send stays out of sight below, as
  `ConversationScroll` only returns to following when you scroll back to the end yourself.
- **Replay switch.** A debug switch that plays sanitized frames through the real channel, so a
  change can be seen working without a gateway. `AppModel.demo()` skips the channel entirely.
- **Contributor vouching, size labels and triage or stale bots.** Worth adding once outside pull
  requests arrive in volume; the repository doesn't have that yet.
- **Keychain without prompts on unsigned Mac builds.** `TokenStore` could use the data-protection
  keychain (`kSecUseDataProtectionKeychain`), which has no per-app ACL prompts, but it needs a
  team-signed app with a keychain access group; ad-hoc builds get `errSecMissingEntitlement`.
  Only worth it together with a migration of the existing login-keychain items.
- **App icon on macOS 15.** `AppIcon` is a full-bleed white square that macOS 26+ and iOS round
  themselves. Before macOS 26, the Mac drew icons exactly as supplied, so on macOS 15 (the
  deployment target) it likely shows as a square. Unverified (no macOS 15 machine checked). An
  Icon Composer `.icon` file (Xcode 26) would give both the new rounded/glass look and correct
  older-system images.
