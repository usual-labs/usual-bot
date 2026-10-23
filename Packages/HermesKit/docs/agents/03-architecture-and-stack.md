# HermesKit: architecture and tooling

## Implemented today

Swift tools 6.0, iOS 18/macOS 15 minimums, Foundation/Observation/CryptoKit/Security. AppModel is MainActor observable state. Tokens use device-only Keychain accessibility; a hashed per-gateway filename stores protected cache data in the Caches directory. UserDefaults remembers the gateway address. Backoff doubles from 300ms to a 15s cap.

Manifests/lockfiles: `Package.swift`. Package manager: see build manifest / parent tooling.

No environment-variable references were found by the direct source-reference scan; check external host configuration separately.

Test source examples: `Tests/HermesKitTests/AuthSessionTests.swift`, `Tests/HermesKitTests/ChatThreadTests.swift`, `Tests/HermesKitTests/JSONRPCChannelTests.swift`, `Tests/HermesKitTests/RoomTests.swift`, `Tests/HermesKitTests/Fakes.swift`, `Tests/HermesKitTests/ContactTests.swift`, `Tests/HermesKitTests/BotChatTests.swift`, `Tests/HermesKitTests/ThreadStateTests.swift`.

Commands/configuration describe available tooling, not successful execution. No builds, tests, migrations or provider calls were run for this documentation change.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
