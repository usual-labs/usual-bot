# HermesKit: user and caller surface

## Implemented today

Public model types in Sources/HermesKit include AppModel, Contact, ChatThread, RoomThread, Routine and authentication/address types. AppModel exposes restore/signIn, `setForeground(_:)` (closes the socket while the app is in the background and reconnects on return, reattaching every chat; the iOS app calls it from `scenePhase`) and per-contact thread/room/routine operations. GatewayConnector mints a WebSocket ticket, opens /api/ws, waits for gateway.ready, then advertises server_requests capabilities. JSONRPCChannel owns socket requests and responses. OfflineCache persists a Codable roster/thread snapshot; KeychainTokenStore persists token sets per gateway.



Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
