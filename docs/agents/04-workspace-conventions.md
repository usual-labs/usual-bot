# Usual Bot: shared conventions

## Implemented today

Preserve Swift formatting and platform conditionals. Use local Config/Local.xcconfig setup for developer-specific signing; do not copy private settings. Design avatar material is reference/artwork, not another software package.

Keep software implementation changes and technical backlogs in the owning child. Update this layer when shared contracts, tooling, routing, boundaries or dependency direction changes. Add a project only with a clear source/build owner and an AGENTS.md + docs/agents/ entry. Existing canonical reference documents remain authoritative for their detailed topics.

This public repository holds only software documentation suitable for users and contributors, including technical decisions, reproducible release instructions and artwork provenance. Legal/IP research, marketing/business strategy, launch plans, private internal decisions and maintainer administration or publication-session notes belong outside the checkout. In the Usual workspace their destination is the parent `docs/agents/usual-bot/`, distinct from this repository's `docs/agents/`. Check placement before writing, moving, committing or publishing. Keep public credits and licensing notices in the repo, and keep public build instructions independent of private notes and local scripts.
