# UsualUI: user and caller surface

## Implemented today

RootView receives AppModel and a SignInPresenter. Signed-out/signing-in state renders ConnectView; signed-in state renders ContactsSplitView, routing selected agents to threads and rooms to RoomPane. Creation of rooms delegates to AppModel; approval, question and secret cards delegate to thread state. This package does not implement its own gateway transport or credential store.



Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
