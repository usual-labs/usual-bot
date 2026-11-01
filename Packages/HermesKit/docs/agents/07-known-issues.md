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

## Declining a masked prompt hands the agent a JSON error (confirmed live, 2026-10-31)

- Symptom: with Usual Bot the only client attached, a 4404 on `secret`, `sudo` or a `vault.*` request
  doesn't end as "skipped". The agent's request gets an error string as the answer.
- Cause: `server_requests._decline` doesn't check the method. When every answering client has
  declined, it settles the request with `{"value": <JSON error about Hermes Desktop>}`, `_ask` returns
  that, and callers skip only on an empty value.
- Seen on a real gateway (Hermes `bf0203a794`, legacy dialect, a throwaway profile): the JSON was
  saved in the profile's `.env`, so the skill treated the variable as set and never asked again; and
  `sudo` received it on stdin, with a stand-in `sudo` recording it. A real `sudo` would count a
  failed attempt. Read from source, not run: for an unlock it goes to `backend.unlock(master)`, a failed
  attempt on the real password manager, and a code is typed into the page's code field.
  `vault.save_login` is harmless only by luck (no `password`, so `None`).
- Fix: `AppModel.handle` never declines `secret`, `sudo` or the three vault methods. Without a chat,
  or for a malformed request, it answers `{"value": ""}`, which is Hermes's skip; `attach` does the
  same for an unreadable open request. That skip beats any other attached app, which only matters in
  the moment before a chat attaches, since a session this app joined has a chat.
- Prevention: `vaultRequestsWithNoCardAreSkippedAndNeverDeclined`,
  `aVaultRequestItCantReadIsSkippedInItsChat` and the secret prompt tests fail if a masked method
  reaches the 4404 fallback (checked by reverting the routing). The lasting fix is in Hermes: limit
  that settlement to window-owned requests.
- Cleaning up: releases up to 0.3.0 can have left that JSON in a profile's `.env`. Removing the
  line lets the skill ask again.

## A prompt answered in another app stays on screen (source finding, 2026-10-31)

The gateway sends `request.cancel` when a request times out or is cancelled, not when another client
answers it (`server_requests.resolve_response`). A secret, sudo or clarify card answered in the
official app stays here until the next reconnect. Answering it then does nothing: the gateway
drops the response, and the app's notice still says it was sent.

## Authority turns send no vault prompts (source finding, 2026-10-31)

Only the legacy turn path installs the vault callbacks; `gateway/` installs none, so an authority
turn reports `prompt_unavailable` or `unlock_unavailable` to the agent. The vault tab still applies
there through the legacy fallback, which hasn't been tried live.

## A test recording socket frames must not run in parallel (fixed 2026-10-31)

`FrameRecorder.observer` is a global test seam, so parallel tests saw each other's frames and
`secretsAreNeverRecorded` failed at random. Those tests live in the `.serialized`
`VaultRecordingTests` suite.
