# Usual Bot: workspace overview

## Implemented today

Layer: WORKSPACE. Independent source/build or package boundaries require routing before edits.

Native SwiftUI app shell with three Swift packages. App/UsualBotApp.swift creates AppModel, chooses the platform sign-in presenter, composes RootView and restores state.

- **Packages/HermesKit**: Gateway auth, transport and domain state. Foundation library; no UI ownership.
- **Packages/UsualUI**: Native screens and reusable UI. Depends on HermesKit.
- **Packages/Tailnet**: The iPhone's built-in Tailscale device; no UI.

Outside the app build: `Integrations/usual-bot` (the Hermes plugin, run on the gateway) and `Services/` (Cloudflare Workers for push and update checks).

## Planned/aspirational

No unimplemented cross-project integration is assumed. A directory grouping alone is not a runtime dependency.
