`docs/agents/` is this layer's persistent agent memory and authoritative maintained reference for how this code behaves; code is the source of truth.

## Knowledge index

- [01-overview.md](docs/agents/01-overview.md) — UsualUI: purpose and current flow.
- [02-surface-area.md](docs/agents/02-surface-area.md) — UsualUI: user and caller surface.
- [03-architecture-and-stack.md](docs/agents/03-architecture-and-stack.md) — UsualUI: architecture and tooling.
- [04-conventions-and-patterns.md](docs/agents/04-conventions-and-patterns.md) — UsualUI: conventions and ownership.
- [05-folder-structure.md](docs/agents/05-folder-structure.md) — UsualUI: practical source map.
- [06-improvement-ideas.md](docs/agents/06-improvement-ideas.md) — UsualUI: improvement ideas.
- [07-known-issues.md](docs/agents/07-known-issues.md) — UsualUI: known issues.
- [components.md](docs/agents/components.md) — UsualUI: components.
- [design-system.md](docs/agents/design-system.md) — UsualUI: design system.
- [public-api.md](docs/agents/public-api.md) — UsualUI: public api.

## Operating protocol

- BEFORE thinking about or making ANY change, read the relevant `docs/agents/` files and always skim `07-known-issues.md`.
- AFTER any change or new learning, update the relevant KB files in the SAME turn before finishing. Record non-obvious bugs and gotchas in `07-known-issues.md`; deferred improvements in `06-improvement-ideas.md`; behavior, architecture, structure and conventions in the matching state file. Rewrite stale state rather than appending history.
- Update workspace KBs only when relationships, boundaries, project routing or shared conventions change.
- Code is the source of truth. If code and the KB disagree, fix the KB. Distinguish implemented behavior from planned/aspirational intent, and source evidence from runtime verification.
- Triggers: changed product behavior, architectural boundary, folder convention, tooling, UI direction, added/removed cross-project link, debugged issue or spotted improvement.
- Do not run browser tests unless explicitly requested. Keep changes focused, use YAGNI, and keep files below 500 lines where practical. Report meaningful behavior/setup/deployment changes after implementation.
