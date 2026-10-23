# HermesKit: conventions and ownership

## Implemented today

Transport and HTTP interfaces permit test fakes. Keep gateway wire protocol in Gateway/Transport, auth in Auth, state orchestration in Stores and domain behavior in Chat/Rooms/Routines. Cache data can be purged; it is not the gateway source of truth.

Preserve the source patterns at the anchors below. Treat placeholder/sample data as such; do not convert it to a product guarantee. Keep secrets out of client bundles and documentation.

## Maintenance rule

Changes belong in their existing owning module. Add a top-level abstraction only when the current structure cannot clearly own the behavior; update this KB in the same turn.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
