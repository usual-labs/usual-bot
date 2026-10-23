# Usual Bot: app shell

## Implemented today

UsualBotApp uses WindowGroup and async model.restore(). macOS has hidden title bar, background dragging, 1100x720 default window and sidebar commands; other platforms use the same RootView through the appropriate presenter. Package builds are separate from signing/device acceptance.

Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.
