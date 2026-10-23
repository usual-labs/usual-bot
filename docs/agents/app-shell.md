# Usual Bot: app shell

## Implemented today

UsualBotApp uses `WindowGroup(id: "main")` and async model.restore(). macOS has a hidden title bar, background dragging, a 1100x720 default window, the ⌥Space quick panel and a MenuBarExtra. iOS uses the same RootView with `WebAuthSignInPresenter` (an in-app `ASWebAuthenticationSession`; the gateway redirects to the app's 127.0.0.1 listener and the app closes the sheet) and calls `model.setForeground` from `scenePhase`, so the socket closes in the background and reconnects on return.

The Mac entitlements include `files.user-selected.read-only` for files you pick, drop or paste; iPhone declares `NSCameraUsageDescription` (Shared.xcconfig). Photos come through the out-of-process picker, so no photo-library permission is needed.

Config/Info.plist allows plain http (gateways on a tailnet or home network); GatewayAddress refuses http to public hosts. `NSLocalNetworkUsageDescription` (Shared.xcconfig) covers gateways on a home network; tailnet addresses need no prompt.

Verified 2026-10-23 in the iPhone 17 Pro simulator against the user's gateway: sign-in, chat list, chats, rooms, profile sheet, keyboard, dark mode and reconnect after backgrounding. On a physical iPhone 15 Pro Max (iOS 27.0.1), verified 2026-10-23: browser sign-in completes, because the in-app `ASWebAuthenticationSession` reaches the app's 127.0.0.1 listener on the device. Afterwards the agents load. The app was signed with the team's wildcard development profile. The first attempt failed with "could not connect to the server" because the phone wasn't on the tailnet. A tailnet gateway is reachable only while Tailscale is on in that device, and an unreachable one now says so (`AppModel.describe(_:for:)`, `GatewayAddress.isTailnet`). Package builds are separate from signing/device acceptance; a device build needs a team, from `Config/Local.xcconfig` (see `Local.xcconfig.example`) or `DEVELOPMENT_TEAM=… -allowProvisioningUpdates` on the xcodebuild command line.

Debug builds started with `USUALBOT_DEMO=1` use `AppModel.demo()` (made-up agents, a room, an approval and routines; never connects) instead of signing in; README screenshots come from it. Launch arguments such as `-selectedContact forge` pick the open chat without overwriting stored settings.

Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.
