# UsualUI: components

## Implemented today

RootView owns top-level routing; ContactsSplitView handles selection; ContactList/ContactRow own roster; ThreadPane, Composer and TranscriptView own conversation presentation; RoomPane/NewRoomSheet own rooms; ProfilePanel owns agent profile/routine UI. QuickMessageView is the ⌥Space panel's content.

## What the code doesn't explain

- **Mac and iPhone differ on purpose.** The Mac lays its sidebar out itself and keeps the model row under the message box. iPhone keeps NavigationSplitView and puts those controls in the box (`ComposerLayout`, `ComposerControls`). See 07-known-issues.md for why.
- **iPhone doesn't autofocus the message box,** and scrolling dismisses the keyboard, so the resting pill stays reachable.
- **Attachments are for chats, not rooms.** HEIC, HEIF and TIFF become JPEG because the gateway takes only PNG, JPEG, GIF, WebP and BMP as images. The draft stays if an upload fails.
- **Suggestion menus.** Only letters, digits, `-` and `_` open the `/` menu, so paths don't. iPhone menus that open upward list their items in reverse (system behaviour).
- **Message actions.** The Mac's 104 pt hover slot is always reserved so nothing moves, and the bar stays up 250 ms after the pointer leaves so it can reach the bar. Undo asks no confirmation.
- **`HermesKit.BackgroundTask` is spelled out** because SwiftUI has its own `BackgroundTask`.
- **Calls.** `LiveCall`'s web view stays on screen at 1 pt because WebKit only records and plays from a visible web view. The call ends when the app goes to the background.
- **Dictation.** Real speech on iPhone hasn't been tried.
- **Resources.** `Image(_:bundle:)` reads asset catalogs only, so loose files load through `AvatarArt.resource(_:)`.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
