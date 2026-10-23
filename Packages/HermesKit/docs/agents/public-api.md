# HermesKit: public api

## Implemented today

Import HermesKit and construct AppModel for app state; supply a SignInPresenter to its signIn flow. Contact and thread models are consumed by UsualUI. Package.swift exports a single HermesKit library; individual internal helpers such as OfflineCache and GatewayConnector are not a separate public product.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
