# HermesKit: security access

## Implemented today

Keychain stores tokens keyed by gateway URL; cached transcripts live in protected cache files, not credential storage. Keep Keychain access off the main actor where restore already does so.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
