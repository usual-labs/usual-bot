# Usual Bot: app shell

## Implemented today

UsualBotApp uses `WindowGroup(id: "main")` and async model.restore(). macOS has a hidden title bar, background dragging, a 1100x720 default window, the ⌥Space quick panel and a MenuBarExtra. Window tabbing is off (`NSWindow.allowsAutomaticWindowTabbing = false` in `UsualBotApp.init`): the tab bar doesn't fit the hidden title bar, so View and Window have no tab items; File > New Window still opens separate windows. iOS uses the same RootView with `WebAuthSignInPresenter` (an in-app `ASWebAuthenticationSession`; the gateway redirects to the app's 127.0.0.1 listener and the app closes the sheet) and calls `model.setForeground` from `scenePhase`, so the socket closes in the background and reconnects on return.

The Mac entitlements include `files.user-selected.read-write`, to read the files you pick, drop or paste and to save files agents send; iPhone declares `NSCameraUsageDescription` (Shared.xcconfig). Config/Info.plist declares `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` for dictation on both platforms (Xcode doesn't generate the speech key for macOS from a build setting), and the Mac has the `device.audio-input` entitlement. Photos come through the out-of-process picker, so no photo-library permission is needed.

Config/Info.plist allows plain http (gateways on a tailnet or home network); GatewayAddress refuses http to public hosts. `NSLocalNetworkUsageDescription` (Shared.xcconfig) covers gateways on a home network; tailnet addresses need no prompt.

Verified 2026-10-23 in the iPhone 17 Pro simulator against the user's gateway: sign-in, chat list, chats, rooms, profile sheet, keyboard, dark mode and reconnect after backgrounding. On a physical iPhone 15 Pro Max (iOS 27.0.1), verified 2026-10-23: browser sign-in completes, because the in-app `ASWebAuthenticationSession` reaches the app's 127.0.0.1 listener on the device. Afterwards the agents load. The app was signed with the team's wildcard development profile. The first attempt failed with "could not connect to the server" because the phone wasn't on the tailnet. A tailnet gateway is reachable only while Tailscale is on in that device, and an unreachable one now says so (`AppModel.describe(_:for:)`, `GatewayAddress.isTailnet`). Package builds are separate from signing/device acceptance; a device build needs a team, from `Config/Local.xcconfig` (see `Local.xcconfig.example`) or `DEVELOPMENT_TEAM=… -allowProvisioningUpdates` on the xcodebuild command line.

Debug builds started with `USUALBOT_DEMO=1` use `AppModel.demo()` (made-up agents, a room, an approval and routines; never connects) instead of signing in; README screenshots come from it. Launch arguments such as `-selectedContact forge` pick the open chat without overwriting stored settings.

Released Mac builds (`.github/workflows/release.yml`) use bundle ID `labs.usual.UsualBot`
(`BUNDLE_ID_PREFIX=labs.usual`), `MARKETING_VERSION` from the tag without any pre-release suffix and
the run number as `CURRENT_PROJECT_VERSION`, are signed with Developer ID plus the hardened runtime
(no provisioning profile; the entitlements need none), and are notarized and stapled, as is the
`.dmg`. Debug/dev builds keep `dev.usualbot.local` (or the `Local.xcconfig` prefix), so they don't
share settings or the Keychain item's trust with the released app.

Device preferences live in UsualUI’s Settings view. The native shell supplies the Mac-only launch
at login and Quick Message shortcut controls. Shortcut recording suspends this app’s registration;
cancelling or leaving the window restores it, and a refused replacement keeps the previous choice.
The menu bar labels the shortcut macOS accepted, which may be ⌃⌥Space rather than ⌥Space.

Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.

Icon and launch: `App/Assets.xcassets` holds `AppIcon` (the Hermes doodle on white, framed like the
official Hermes icon since 25 October 2026: 104% of the tile wide, the bust running 6% off the
bottom, 3% right of centre; 1024 px
for iPhone and every Mac size; the system rounds it on macOS 26+ and iOS; `ASSETCATALOG_COMPILER_APPICON_NAME
= AppIcon` in `Config/Shared.xcconfig`), and the iPhone launch screen's `LaunchMark` (120 pt) and
`LaunchBackground` (the window colour, light and dark), named by `UILaunchScreen` in `Config/Info.plist`
(the generated launch screen setting is gone). While `AppModel.isRestoring` (a saved gateway at
launch, until `restore()` finishes, including any Keychain prompt), `RootView` shows `SplashView`
(the same mark, centred, ignoring safe areas), so the launch screen runs on into the app instead of
the connect screen flashing. Checked: the built Mac icon (rendered by `NSWorkspace`), the iPhone
launch screen and the sign-in page in the Simulator; the iPhone Home Screen icon wasn't seen (the
Simulator drew every icon blank after a reinstall).

Independence copy is defined in `ConnectView.swift` for sign-in and in
`INFOPLIST_KEY_NSHumanReadableCopyright` (`Config/Shared.xcconfig`) for the Mac About box.
The README and release-notes generation in `.github/workflows/release.yml` also include it.
These locations were checked in source on 26 October 2026; no runtime check was performed.

