# UsualUI: components

## Implemented today

RootView owns top-level routing; ContactsSplitView handles selection; ContactList/ContactRow own roster; ThreadPane, Composer and TranscriptView own conversation presentation; RoomPane/NewRoomSheet own rooms; ProfilePanel owns agent profile/routine UI.

On the Mac, ContactsSplitView lays the sidebar out itself (an HStack, not NavigationSplitView): the list's width is stored in `@AppStorage("sidebarWidth")` (78–380 pt), a drag edge resizes it live, and under 220 pt the list renders as the 78 pt avatar rail (`ContactRow(compact: true)`), snapping to the rail or back to 300 pt when the drag ends. A window that leaves the chat under 360 pt shows the rail too. Search and New Room are Liquid Glass circles in the sidebar's top row, level with the window buttons. iPhone keeps NavigationSplitView. QuickMessageView (QuickMessage/) is the ⌥Space panel's content.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
