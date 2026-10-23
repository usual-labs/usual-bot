# Usual Bot: workspace overview

## Implemented today

Layer: WORKSPACE. Independent source/build or package boundaries require routing before edits.

Native SwiftUI app shell with two independent Swift packages. App/UsualBotApp.swift creates AppModel, chooses the platform sign-in presenter, composes RootView and restores state.

- **Packages/HermesKit**: Gateway auth, transport and domain state. Foundation library; no UI ownership.
- **Packages/UsualUI**: Native screens and reusable UI. Depends on HermesKit.

## Planned/aspirational

No unimplemented cross-project integration is assumed. A directory grouping alone is not a runtime dependency.
