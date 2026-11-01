# HermesKit: security access

## Implemented today

Keychain stores tokens keyed by gateway URL; cached transcripts live in protected cache files, not credential storage. Keep Keychain access off the main actor where restore already does so.

Secret and sudo answers go only to the gateway, as the JSON-RPC response to its request. They aren't kept in `ChatThread`, the transcript, notices or `CachedThread`, and `FrameRecorder.redacted` blanks `result.value` in outgoing frames, the one place a recording would catch them. Anything new that answers with `result.value` is covered by that rule; a masked answer in any other shape needs its own. Plain `http` to a private host is allowed by `GatewayAddress`, so `GatewayAddress.isUnencrypted` marks the case where a typed secret could be read on the network (not loopback, not Tailscale) and the card warns before sending.

Vault secrets (`vault.add` values, master passwords, login and code answers) are entered, sent and dropped; nothing keeps them. Rules that hold today:

- `vault.list` is metadata and `VaultItem` has no secret field. No method reads a secret back.
- Gateway error text passes `VaultRedaction.scrub` before it's shown: the values just sent, `password=…`-style pairs and card-shaped digit runs become `[hidden]`.
- Notices about a prompt name the site and outcome only. Prompts aren't cached (`CachedThread` doesn't carry them).
- `GatewayAddress.isUnencrypted` (http off this device, outside Tailscale) makes `VaultList` and `ChatThread.answer` refuse to send unless the call passes `allowingUnencrypted`. Unknown state counts as unencrypted. The consent is per send and never stored.
- `FrameRecorder` (Debug, `USUALBOT_RECORD_FRAMES=1`) blanks `result.value` on every outgoing frame and the `secretParams` of `vault.add` and `vault.unlock`; `call(sensitive:)` keeps replies to those calls out of the file.
- Swift `String`s can't be zeroed; clearing means dropping the reference.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`, `Sources/HermesKit/Transport/FrameRecorder.swift`, `Sources/HermesKit/Vault/VaultRedaction.swift`.
