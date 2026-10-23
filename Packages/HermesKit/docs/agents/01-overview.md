# HermesKit: purpose and current flow

## Implemented today

Swift package implementing authenticated Hermes gateway sessions, roster, chat, rooms, routines, approval/clarification requests and cached client state. AppModel restores saved credentials/cache, signs in and maintains gateway connectivity.

Layer: SINGLE PROJECT. Types: library-CLI. This layer has its own source and build/package boundary.

## Implemented today — boundaries and observed gaps

No additional product roadmap is asserted by this KB. Future work requires a separate scoped decision.

This inspection establishes source behavior, not deployment, device, provider or end-to-end acceptance.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
