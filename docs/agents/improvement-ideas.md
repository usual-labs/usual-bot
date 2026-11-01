# Usual Bot: cross-project improvement ideas

## Planned/aspirational

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
- **Built-in Tailscale on iPhone (working spike 2026-11-01, branch `spike/built-in-tailscale`, not merged).** Reaches a tailnet
  gateway without the Tailscale VPN on. TailscaleKit (`swift/` in `tailscale/libtailscale`, BSD-3)
  runs a userspace node inside the app with a SOCKS5 loopback proxy. Code: `Packages/Tailnet`
  (node lifecycle, proxied session, device name and address, LocalAPI logout through the
  loopback port because TailscaleKit's `logout()` isn't public); `AppModel(session:)` and
  `reconnect()` in HermesKit; `App/BuiltInTailscale.swift` (on/off in `UserDefaults`
  `builtInTailscale`, the Tailscale sign-in sheet, the gateway menu's Tailscale section: the switch,
  status, Sign In to Tailscale…, Sign Out of Tailscale); `TailnetSignInPresenter` (gateway sign-in
  in an in-app web view through the proxy, since `ASWebAuthenticationSession` loads pages outside
  the app). The node stops in the background and starts on return: iOS cut a suspended node's
  sockets and its UDP receivers and link monitor never recovered (DERP-only, errors in a loop).
  Evidence on an iPhone 15 Pro Max (iOS 27.0.1) with the VPN off: Tailscale sign-in in the system
  sheet; gateway traffic from the app's own tailnet address; with saved keys the node runs about
  1 s after launch or return (two background cycles logged, no socket errors); gateway sign-in
  through the web view and the new menu reported working by the maintainer. Simulator demo checked
  for the header and menu layout. Builds: iPhone, Simulator, Mac (skips the iOS-only framework via
  a platform-conditional dependency); HermesKit and UsualUI tests and lint pass. Before shipping:
  the framework isn't in git, so CI and contributors can't build (pick vendoring, a release
  asset or a build step; Go is needed to build it); it was built for iOS 18.1 while the app
  targets 18.0 (linker warning); it adds 21 MB (36 MB Debug app); the connect screen has no
  switch yet, so a new user can't turn it on before signing in; tsnet uploads node logs to
  Tailscale (logtail) like Tailscale's own clients; Google sign-in may refuse an in-app web view.
  Zero-code alternative: Tailscale's VPN On Demand can start the VPN when a `*.ts.net` name is
  resolved.
