# HermesKit: security access

## Implemented today

Keychain stores tokens keyed by gateway URL; cached transcripts live in protected cache files, not credential storage. Keep Keychain access off the main actor where restore already does so.

Secret and sudo answers go only to the gateway, as the JSON-RPC response to its request. They aren't kept in `ChatThread`, the transcript, notices or `CachedThread`, and `FrameRecorder.redacted` blanks `result.value` in outgoing frames, the one place a recording would catch them. Anything new that answers with `result.value` is covered by that rule; a masked answer in any other shape needs its own. Plain `http` to a private host is allowed by `GatewayAddress`, so `GatewayAddress.isUnencrypted` marks the case where a typed secret could be read on the network (not loopback, not Tailscale) and the card warns before sending.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
