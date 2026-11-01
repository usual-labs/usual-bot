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
- **Built-in Tailscale on iPhone (working, branch `built-in-tailscale`, not merged).** Reaches a
  tailnet gateway without the Tailscale VPN on. TailscaleKit (`swift/` in `tailscale/libtailscale`,
  BSD-3) runs a userspace node inside the app with a SOCKS5 loopback proxy. iPhone only on purpose:
  that costs one platform condition in `Packages/Tailnet` and an `#if os(iOS)` around the app's
  Tailscale file, while a linked-but-off Mac build would need a universal macOS slice (Tailscale's
  `make macos` builds Apple silicon only; the Mac release is universal), ship about 20 MB unused,
  and put the Go framework in the notarized Mac release. Code: `Packages/Tailnet`
  (node lifecycle, proxied session, device name and address, LocalAPI logout through the
  loopback port because TailscaleKit's `logout()` isn't public); `AppModel(session:)` and
  `reconnect()` in HermesKit; `App/BuiltInTailscale.swift` (on/off in `UserDefaults`
  `builtInTailscale`, the Tailscale sign-in sheet, the connect screen's switch, the gateway menu's
  Tailscale section: switch, status, Sign In to Tailscale…, Sign Out of Tailscale);
  `TailnetSignInPresenter` (gateway sign-in in an in-app web view through the proxy, since
  `ASWebAuthenticationSession` loads pages outside the app). Google refuses sign-in in web views
  inside apps (`disallowed_useragent`), so a navigation to `accounts.google.com` ends that attempt
  with an alert and the gateway's later sign-ins use the system sheet, which needs the Tailscale
  VPN for that sign-in; tokens then refresh through the built-in device. Fully VPN-free Google
  sign-in would mean posing as Safari, which Google's policy forbids. The Google hand-off is
  untested (no Google-backed gateway). The node stops in the background and starts on return:
  iOS cut a suspended node's sockets and its UDP receivers and link monitor never recovered
  (DERP-only, errors in a loop). Evidence on an iPhone 15 Pro Max (iOS 27.0.1) with the VPN off:
  Tailscale sign-in in the system sheet; gateway traffic from the app's own tailnet address;
  with saved keys the node runs about 1 s after launch or return (two background cycles logged,
  no socket errors); gateway sign-in through the web view and the gateway menu reported working
  by the maintainer. Simulator checked for the header, menu and connect-screen switch. Builds:
  iPhone, Simulator, Mac (skips the iOS-only framework via a platform-conditional dependency);
  HermesKit and UsualUI tests and lint pass. Before shipping: CI hasn't run on this branch (not pushed);
  it adds 21 MB (36 MB Debug app); tsnet uploads node logs to Tailscale (logtail) like
  Tailscale's own clients; the Google hand-off is untested; if the iPhone app is ever
  distributed, its credits need TailscaleKit's BSD-3 notice. Framework (decided and published
  2026-11-01): `Packages/Tailnet/Package.swift` downloads `TailscaleKit.xcframework.zip` from the
  `libtailscale-ac7ed43` release of `usual-labs/tailscalekit-build` (checkout
  `../tailscalekit-build`) by URL and checksum. That repo's manually run workflow builds a
  libtailscale commit for an iOS minimum (18.0 here; TailscaleKit's own project says 18.1,
  overridden with `XCODE_XCCONFIG_FILE`), zips it with libtailscale's LICENSE, attests it and
  publishes an immutable release (the repo allows GitHub-owned actions only). Verified: the
  release zip matched its notes' checksum, its attestation names the repo's `build.yml` on main,
  and Xcode downloaded it and built the app for Simulator, Mac and iPhone; it ran on the iPhone.
  To update Tailscale, run that workflow (trial first) and copy the new URL and checksum.
  Tailscale publishes no prebuilt TailscaleKit; the only prebuilt found (`indiagrams/tunnelless`,
  a patched fork without attestation) says not to depend on it. Committing the framework (69 MB
  per version) and building from source in every build (Go 1.27) were rejected. Zero-code
  alternative: Tailscale's VPN On Demand can start the VPN when a `*.ts.net` name is resolved.
