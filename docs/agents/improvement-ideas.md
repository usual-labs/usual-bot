# Usual Bot: cross-project improvement ideas

## Planned/aspirational

- **Hermes features the app doesn't surface yet.** From a Hermes source read (`bf0203a794`,
  22 October 2026); none confirmed against a live gateway. Check each call on the app's
  dashboard socket first.
  - **Older messages in a chat over the resume limit:** search finds them through
    `GET /api/sessions/search`, but a chat the gateway attaches without history (over
    `sessions.max_resume_messages`, 20,000 by default) can't open at one. That needs REST pages
    (`/api/sessions/{id}/messages`, or `/timeline` and `/messages/around`) loaded into the
    transcript. Room logs aren't in the gateway's search at all (they live in the hosted-rooms store).
  - **A template's prompt before saving:** `/api/cron/blueprints` leaves out each template's prompt
    and skills, so New Routine shows them only once Hermes has created the routine. Seeing and
    editing them first needs Hermes to send them in the catalog.
  - **Agent's computer, what's left:** the package install (`display.install`, with its masked sudo
    prompt), the sandbox image switch (`display.switchSandboxImage`), Stop, the clipboard (Hermes
    turns the server's off; sending ours isn't wired) and Tight encoding. The viewer is in.

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
- **Built-in Tailscale before the iPhone app ships.** Its credits need TailscaleKit's BSD-3 notice.
  tsnet uploads the node's logs to Tailscale (logtail), as Tailscale's own clients do: decide
  whether to turn that off or say so. The framework adds about 21 MB to the app.
- **Apple push through a relay.** Notifications under Usual Bot's own icon, for everyone, would need a
  small hosted relay holding the push key, with payloads encrypted to the device and a notification
  service extension to read them.
