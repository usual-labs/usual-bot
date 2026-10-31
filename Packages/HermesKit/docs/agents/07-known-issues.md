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

## Declining a one-string request hands the agent a JSON error (source finding, 2026-10-31)

- Symptom: `secret`, `sudo` and the other requests answered with one string (`ValueResult`) don't
  end as "skipped" when the app declines them with 4404 and is the only client attached.
- Cause: `server_requests._decline` doesn't check the method. When every answering client has
  declined, it settles the request with `{"value": <JSON error about Hermes Desktop>}`. `_ask`
  returns that, and `secret_cb` skips only on an empty value, so it would save the JSON as the
  secret; sudo would get it as the password. Reproduced by calling `resolve_response` directly with
  the contract registry stubbed (Hermes `bf0203a794`); the saving step is read from source, not run.
- Fix here: `AppModel.handle` never declines `secret` or `sudo`: without a chat, or for a malformed
  request, it answers `{"value": ""}`. That skip beats any other attached app, which only matters
  in the moment before a chat attaches, since a session this app joined has a chat.
- Still open: the three `vault.*` requests are declined with 4404, so they can hit the same thing
  until they're handled. The lasting fix is in Hermes: limit that settlement to window-owned
  requests.

## A prompt answered in another app stays on screen (source finding, 2026-10-31)

The gateway sends `request.cancel` when a request times out or is cancelled, not when another client
answers it (`server_requests.resolve_response`). A secret, sudo or clarify card answered in the
official app stays here until the next reconnect. Answering it then does nothing: the gateway
drops the response, and the app's notice still says it was sent.
