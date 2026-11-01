# Usual Bot: project routing map

## Implemented today

| Project | Path | Responsibility / change here when | Boundary |
|---|---|---|---|
| HermesKit | [Packages/HermesKit](../../Packages/HermesKit/AGENTS.md) | Gateway auth, transport and domain state | Foundation library; no UI ownership |
| UsualUI | [Packages/UsualUI](../../Packages/UsualUI/AGENTS.md) | Native screens and reusable UI | Depends on HermesKit |
| Tailnet (spike branch `spike/built-in-tailscale`) | Packages/Tailnet | The iPhone's built-in Tailscale device (TailscaleKit wrapper); see improvement-ideas.md | iOS only; TailscaleKit.xcframework is built locally, not in git |
| Native app shell | App/, Config/, UsualBot.xcodeproj/ | App lifecycle, platform sign-in presenters, signing and Xcode target settings | App composes UsualUI and HermesKit; does not own their domain implementation |

Read the chosen child AGENTS.md and KB before editing. Child docs own detailed APIs and local conventions.
