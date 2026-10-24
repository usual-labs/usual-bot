# HermesKit: known issues

## Implemented today: source-supported limitations

Implemented mitigation: gateway approval requests can fail immediately if client capabilities are missing → GatewayConnector explicitly calls client.capabilities with server_requests true after ready → retain this handshake → keep protocol tests around approval flows. This is source-backed mitigation, not a fresh live-gateway check.

## The offline cache can't be written while the Mac is locked (seen 2026-10-24)

`OfflineCache.save` writes with `.completeFileProtection`. On macOS 27 that write fails with
NSCocoaError 513 ("Creating a temporary file via mktemp failed … errno 1") while the screen is
locked (`IOConsoleLocked` true), so `OfflineCacheTests.roundTripsAndDeletes` fails then and passes
once unlocked. The app's cache save fails the same way if it runs while locked (the previous
snapshot stays). Run the HermesKit tests with the Mac unlocked; whether the app should fall back
to `.completeUntilFirstUserAuthentication` on the Mac is open.

## Side-agent answers can go to a torn-down session (source finding, 2026-10-24)

The gateway reaps a session 20 s after its last WebSocket client leaves (`ws_orphan_reap_grace_s`,
`HERMES_TUI_WS_ORPHAN_REAP_GRACE_S`) and frees its replay ring. `btw.complete` and
`background.complete` emitted to it afterwards reach no one, and the app reattaches to a new live
session. Background answers are recovered from the task's stored session (`ChatThread+Recovery`);
side answers can't be (Hermes doesn't store them) and show as lost. iPhone apps close the socket in
the background, so this is the common case there.

