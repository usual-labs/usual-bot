# UsualUI: design system

## Implemented today

Theme.swift centralizes light/dark surface, ink, border, selected-row, user-bubble, danger, status and agent palette colors. Native SwiftUI layout and NavigationSplitView provide platform adaptation. Preserve labels and actionable buttons; do not convert approval/clarification cards into decorative status text.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
