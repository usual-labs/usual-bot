# HermesKit: practical source map

## Implemented today

- `Package.swift` — library target and platform minimums
- `Sources/HermesKit/Stores/AppModel.swift` — state orchestration
- `Sources/HermesKit/Stores/OfflineCache.swift` — offline cache
- `Sources/HermesKit/Auth/TokenStore.swift` — Keychain
- `Sources/HermesKit/Chat/SecretPrompt.swift`, `Chat/ChatThread+Secrets.swift` — masked secret and sudo prompts
- `Sources/HermesKit/Transport/GatewayConnection.swift` — connection handshake
- `Sources/HermesKit/Transport/JSONRPCChannel.swift` — RPC
- `Sources/HermesKit/Transport/FrameRecorder.swift` — Debug frame recording, with redaction
- `Sources/HermesKit/Gateway/GatewayAddress.swift` — address validation
- `Sources/HermesKit/Vault/` — vault list, items, drafts and error scrubbing
- `Sources/HermesKit/Chat/VaultPrompt.swift`, `Chat/ChatThread+Vault.swift` — in-chat vault prompts

No local database schema/migration files were found in this layer; that does not imply dependencies or remote systems lack persistence.

Build output, dependencies and caches are not source owners. Do not introduce assumed API, jobs, migrations or shared-package folders merely because another product has them. Put new behavior next to the relevant source owner above; update the map when introducing a necessary new boundary.
