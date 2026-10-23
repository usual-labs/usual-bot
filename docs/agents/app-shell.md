# Usual Bot: app shell

## Implemented today

UsualBotApp uses `WindowGroup(id: "main")` and async model.restore(). macOS has a hidden title bar, background dragging, a 1100x720 default window, the ⌥Space quick panel and a MenuBarExtra. iOS uses the same RootView with `WebAuthSignInPresenter` (an in-app `ASWebAuthenticationSession`; the gateway redirects to the app's 127.0.0.1 listener and the app closes the sheet) and calls `model.setForeground` from `scenePhase`, so the socket closes in the background and reconnects on return.

Config/Info.plist allows plain http (gateways on a tailnet or home network); GatewayAddress refuses http to public hosts. `NSLocalNetworkUsageDescription` (Shared.xcconfig) covers gateways on a home network; tailnet addresses need no prompt.

Verified 2026-10-23 in the iPhone 17 Pro simulator against the user's gateway: sign-in, chat list, chats, rooms, profile sheet, keyboard, dark mode and reconnect after backgrounding. Not yet verified on a physical iPhone: the simulator shares the Mac's network, so it doesn't prove the in-app browser can reach the loopback listener on a device. Package builds are separate from signing/device acceptance; a device build needs `Config/Local.xcconfig` (see `Local.xcconfig.example`).

Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.
