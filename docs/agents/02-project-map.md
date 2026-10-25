# Usual Bot: project routing map

## Implemented today

| Project | Path | Responsibility / change here when | Boundary |
|---|---|---|---|
| HermesKit | [Packages/HermesKit](../../Packages/HermesKit/AGENTS.md) | Gateway auth, transport and domain state | Foundation library; no UI ownership |
| UsualUI | [Packages/UsualUI](../../Packages/UsualUI/AGENTS.md) | Native screens and reusable UI | Depends on HermesKit |
| Native app shell | App/, Config/, UsualBot.xcodeproj/ | App lifecycle, platform sign-in presenters, signing and Xcode target settings | App composes UsualUI and HermesKit; does not own their domain implementation |

Read the chosen child AGENTS.md and KB before editing. Child docs own detailed APIs and local conventions.

## Editorial publication boundary

No landing-site project is present in this source inventory. Read [blog-publishing.md](blog-publishing.md) before preparing a marketing post; it records current product context and the missing website/Git/hosting prerequisite. The sibling Usual UI site is a separate product, not an assumed publication destination.
