# HermesKit: integrations

## Implemented today

The gateway owns remote identities, conversations and routines. HTTP authentication produces ticketed WebSocket access. Never expose token sets or raw recorded frames in docs; test fixtures are test evidence only.

Vault methods used over `/api/ws`, always with `profile`: `vault.list`, `vault.add`, `vault.remove`, `vault.sources`, `vault.source.set`, `vault.unlock`, `vault.lock`. Server requests answered: `vault.unlock_prompt`, `vault.save_login`, `vault.code`, as `{"value": …}`. A -32601 reply means that gateway's Hermes has no vault.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
