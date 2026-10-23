# UsualUI: public api

## Implemented today

The package exports the UsualUI library; the app imports RootView(model:presenter:). Public Theme/RGB helpers support styling and parsing. HermesKit remains the domain/state dependency; views are not a separate persistence API.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
