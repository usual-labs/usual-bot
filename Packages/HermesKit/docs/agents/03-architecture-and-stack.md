# HermesKit: architecture and tooling

## Implemented today

Swift tools 6.2, iOS 26/macOS 26 minimums. Apple frameworks only (Foundation, Observation, CryptoKit, Security, Network, Compression, ImageIO and others), no UI frameworks. AppModel is MainActor observable state. Tokens use device-only Keychain accessibility; a hashed per-gateway filename stores protected cache data in the Caches directory, and unsent drafts (`Drafts`) under the same name in Application Support, excluded from backups. UserDefaults remembers the saved gateways (up to two). Backoff doubles from 300ms to a 15s cap.

Manifests/lockfiles: `Package.swift`. Package manager: see build manifest / parent tooling.

Debug-only environment switches: `USUALBOT_RECORD_FRAMES` (`FrameRecorder`) and `USUALBOT_DEMO_PLUGIN_UPDATE` (the demo's plugin update).

Test source examples: `Tests/HermesKitTests/AuthSessionTests.swift`, `Tests/HermesKitTests/ChatThreadTests.swift`, `Tests/HermesKitTests/JSONRPCChannelTests.swift`, `Tests/HermesKitTests/RoomTests.swift`, `Tests/HermesKitTests/Fakes.swift`, `Tests/HermesKitTests/ContactTests.swift`, `Tests/HermesKitTests/BotChatTests.swift`, `Tests/HermesKitTests/ThreadStateTests.swift`.

Commands/configuration describe available tooling, not successful execution. No builds, tests, migrations or provider calls were run for this documentation change.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
