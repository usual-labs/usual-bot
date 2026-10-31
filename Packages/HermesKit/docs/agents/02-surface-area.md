# HermesKit: user and caller surface

## Implemented today

Public model types in Sources/HermesKit include AppModel, Contact, ChatThread, RoomThread, Routine and authentication/address types. GatewayConnector mints a WebSocket ticket, opens /api/ws, waits for gateway.ready, then advertises server_requests capabilities. JSONRPCChannel owns socket requests and responses. OfflineCache persists a Codable roster/thread snapshot; KeychainTokenStore persists token sets per gateway. `AppModel.demo()` (Debug only) never connects.

## Rules the code depends on

- **`send` routes in order:** `/btw` and `/bg` first, so they work mid-turn, then known commands, then ordinary text. Unknown `/words` go out as text.
- **Commands:** `run` tries `command.dispatch`; a 4018 falls back to `slash.exec`.
- **A failed upload sends nothing** and takes queued images back with `image.detach`.
- **Optimistic changes revert with a notice on failure** (reactions, skill switches, thinking level).
- **Recovery** decides what can be lost when the chat attaches, because the chat takes new work from that moment. `attach` passes `rejoined` only for the same live session and epoch with `lastSeq > 0`. Product reasons are in the root `decisions.md`.
- **The SDP for GPT-Live passes byte-exact.** Delegated speech is an ordinary send with `surface: voice-live` and `voice_context`.
- **`CachedThread`'s newer fields are optional,** so older caches load.
- **`setForeground(false)` closes the socket;** returning reattaches every chat. iOS calls it from `scenePhase`.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
