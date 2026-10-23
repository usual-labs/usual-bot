# UsualUI: design system

## Implemented today

Theme.swift centralizes light/dark surface, ink, border, selected-row, user-bubble, danger, status and agent palette colors. Chat text (replies, your bubbles, quotes, list items) gets its typography from `messageFont()`: 14 pt, 6 pt line spacing, light weight in dark mode. Markdown blocks sit 14 pt apart so paragraphs stay distinct from the line spacing. Don't add per-view `.lineSpacing`. Native SwiftUI layout and NavigationSplitView provide platform adaptation. Preserve labels and actionable buttons; do not convert approval/clarification cards into decorative status text.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
