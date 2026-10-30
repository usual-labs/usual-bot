# Usual Bot: cross-project improvement ideas

## Planned/aspirational

Child-local ideas stay in their package KBs.

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
