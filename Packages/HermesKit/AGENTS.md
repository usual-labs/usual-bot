`docs/agents/` holds what the code can't show; code is the source of truth. The root `AGENTS.md` has the documentation rules, surfaces and traps.

## Knowledge index

- [01-overview.md](docs/agents/01-overview.md) — HermesKit: purpose and current flow.
- [02-surface-area.md](docs/agents/02-surface-area.md) — HermesKit: user and caller surface.
- [03-architecture-and-stack.md](docs/agents/03-architecture-and-stack.md) — HermesKit: architecture and tooling.
- [04-conventions-and-patterns.md](docs/agents/04-conventions-and-patterns.md) — HermesKit: conventions and ownership.
- [05-folder-structure.md](docs/agents/05-folder-structure.md) — HermesKit: practical source map.
- [06-improvement-ideas.md](docs/agents/06-improvement-ideas.md) — HermesKit: improvement ideas.
- [07-known-issues.md](docs/agents/07-known-issues.md) — HermesKit: known issues.
- [integrations.md](docs/agents/integrations.md) — HermesKit: integrations.
- [public-api.md](docs/agents/public-api.md) — HermesKit: public api.
- [security-access.md](docs/agents/security-access.md) — HermesKit: security access.

## Operating protocol

- Before changing something, read the KB files for that area and skim `07-known-issues.md`.
- Record non-obvious bugs and gotchas in `07-known-issues.md`, deferred improvements in `06-improvement-ideas.md`, and changed decisions in the file that holds them, in the same turn. Most changes need neither.
- Update workspace KBs only when relationships, boundaries, project routing or shared conventions change.
- Code is the source of truth. If code and the KB disagree, fix the KB. Distinguish implemented behavior from planned intent, and source evidence from runtime verification.
- Do not run browser tests unless explicitly requested. Keep changes focused, use YAGNI, and keep files below 500 lines where practical. Report meaningful behavior/setup/deployment changes after implementation.
