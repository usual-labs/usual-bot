# UsualUI: architecture and tooling

## Implemented today

Swift tools 6.0; SwiftUI and local ../HermesKit package dependency. Resources are processed by the package target. @Bindable observes AppModel and @State owns selection/sheet/profile UI state.

Manifests/lockfiles: `Package.swift`. Package manager: see build manifest / parent tooling.

No environment-variable references were found by the direct source-reference scan; check external host configuration separately.

Test source examples: `Tests/UsualUITests/ThreadViewTests.swift`, `Tests/UsualUITests/ThemeTests.swift`.

Commands/configuration describe available tooling, not successful execution. No builds, tests, migrations or provider calls were run for this documentation change.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
