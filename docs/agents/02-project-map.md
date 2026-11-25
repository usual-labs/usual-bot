# Usual Bot: project routing map

## Implemented today

| Project | Path | Responsibility / change here when | Boundary |
|---|---|---|---|
| HermesKit | [Packages/HermesKit](../../Packages/HermesKit/AGENTS.md) | Gateway auth, transport and domain state | Foundation library; no UI ownership |
| UsualUI | [Packages/UsualUI](../../Packages/UsualUI/AGENTS.md) | Native screens and reusable UI | Depends on HermesKit |
| Tailnet | Packages/Tailnet | The iPhone's built-in Tailscale device (TailscaleKit wrapper), used by `App/BuiltInTailscale.swift`; see decisions.md › Built-in Tailscale | Links on both platforms, but TailscaleKit is an iOS-only dependency, from a `usual-labs/tailscalekit-build` release by URL and checksum. No KB of its own |
| Native app shell | App/, NotificationService/, ShareExtension/, Config/, UsualBot.xcodeproj/ | App lifecycle, platform sign-in presenters, the notification and share extensions, signing and Xcode target settings | App composes UsualUI, HermesKit and Tailnet; does not own their domain implementation |
| Gateway plugin | Integrations/usual-bot | The Hermes plugin the app uses (push, Bot browser and terminal, chat context); Python | Installed on the gateway, not built with the app |
| Services | Services/push-relay, Services/updates | The push relay and the TestFlight update check; Cloudflare Workers | Deployed with Wrangler, not built with the app |

Read the chosen child AGENTS.md and KB before editing. Child docs own detailed APIs and local conventions.
