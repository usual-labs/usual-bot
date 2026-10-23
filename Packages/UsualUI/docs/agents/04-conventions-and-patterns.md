# UsualUI: conventions and ownership

## Implemented today

Keep transport/model mutations in HermesKit and presentation in feature folders. RootView composes feature views. Conditional macOS code supplies the hidden-titlebar-oriented controls while iPhone uses collapsing NavigationSplitView behavior.

Preserve the source patterns at the anchors below. Treat placeholder/sample data as such; do not convert it to a product guarantee. Keep secrets out of client bundles and documentation.

## Maintenance rule

Changes belong in their existing owning module. Add a top-level abstraction only when the current structure cannot clearly own the behavior; update this KB in the same turn.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
