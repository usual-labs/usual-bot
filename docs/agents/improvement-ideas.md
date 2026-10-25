# Usual Bot: cross-project improvement ideas

## Planned/aspirational

- **Open: establish a public landing and Markdown blog.** Enables an agent to
  publish source-backed product guidance at a real canonical `/blog` URL. Scope:
  small website plus owned hosting/Git handoff; this is a new deployment boundary,
  not a Swift package feature. See [blog-publishing.md](blog-publishing.md) for
  required source, content, CTA, access, validation and recovery contracts. No
  site/provider/domain choice or implementation has been made in this KB task.

- **Planned: messaging features M9–M19.** Attachments, images in replies, skills and
  slash commands, dictation, voice call, edit/undo, reactions, side questions,
  background tasks, usage, model and reasoning level. One milestone each, in
  [roadmap.md](roadmap.md).

Child-local ideas stay in their package KBs.

- **Keychain without prompts on unsigned Mac builds.** `TokenStore` could use the data-protection
  keychain (`kSecUseDataProtectionKeychain`), which has no per-app ACL prompts, but it needs a
  team-signed app with a keychain access group; ad-hoc builds get `errSecMissingEntitlement`.
  Only worth it together with a migration of the existing login-keychain items.
- **App icon on macOS 15.** `AppIcon` is a full-bleed white square that macOS 26+ and iOS round
  themselves. Before macOS 26, the Mac drew icons exactly as supplied, so on macOS 15 (the
  deployment target) it likely shows as a square. Unverified (no macOS 15 machine checked). An
  Icon Composer `.icon` file (Xcode 26) would give both the new rounded/glass look and correct
  older-system images.
