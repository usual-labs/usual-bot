`docs/agents/` holds what the code can't show; code is the source of truth.

## What Usual Bot won't compromise on

- **Small.** A messenger for Hermes agents, not a second Hermes app. Settings, skill setup and gateway administration stay in the official app.
- **Native and dependency-free.** SwiftUI on Mac and iPhone, with no third-party packages.
- **Private.** Tokens and conversations stay on the device and the user's own gateway.
- **Plain.** Text in the app says what happened and what to do next.
- **Independent.** Usual Bot isn't affiliated with Nous Research, and says so.

## Ways to hurt yourself

1. **Writing to a real gateway.** Its agents, models and skills are the developer's real ones: a test message costs money, and Make Default changes an agent everywhere. Use the demo (`USUALBOT_DEMO=1`) or the fakes, and a real gateway only when the change depends on it and the developer agrees.
2. **Touching real credentials and chats.** Never print, commit or clear the saved sign-in. Frames from `USUALBOT_RECORD_FRAMES=1` and the offline cache hold real conversations. Examples use `100.101.102.103` and `hermes.example.com`.
3. **Stopping the wrong process.** Stop only a PID you captured when you started it. The developer may be running the app.
4. **Renaming the CI job.** `name: build` is the required status check on `main`.

## Hit every surface

The likely defect is a change that works where you tested and is missing elsewhere. Before calling UI work done, walk this list and say which entries applied:

- **Places:** Mac window, iPhone, ⌥Space panel, menu bar, notifications.
- **Chats and rooms:** a feature in one usually has a decision to make in the other, even if it's "not here".
- **States:** light and dark, VoiceOver, offline and reconnecting, a reply running.
- **Demo:** new behaviour shows in `AppModel.demo()` where it makes sense.
- **Reverse states:** a way in needs a way out and a way to see it.
- **Docs:** the matching guide and the changelog's Unreleased section, when users would notice.

## Verifying

- Run `scripts/check.sh --fast` while you work and `scripts/check.sh` before you push. It runs what CI runs. Keep the Mac unlocked: `OfflineCache` can't write while it's locked.
- To see a change in the app, use the `test-usual-bot` skill.
- Fix a flaky test by finding the race; don't retry it. A logic bug gets a test that fails first, and a purely visual bug gets before and after screenshots instead of a test.

## Pull requests

- Open one only when the developer asks. One request is one pull request.
- Follow the template. State what you couldn't check, and end with the model and harness that did the work.
- Check each bot finding against the source. Fix the real ones, and dismiss the rest with a written reason.

## Knowledge index

- [01-workspace-overview.md](docs/agents/01-workspace-overview.md) — Usual Bot: workspace overview.
- [02-project-map.md](docs/agents/02-project-map.md) — Usual Bot: project routing map.
- [03-cross-project-architecture.md](docs/agents/03-cross-project-architecture.md) — Usual Bot: cross-project architecture.
- [04-workspace-conventions.md](docs/agents/04-workspace-conventions.md) — Usual Bot: shared conventions.
- [05-workspace-structure.md](docs/agents/05-workspace-structure.md) — Usual Bot: workspace structure.
- [app-shell.md](docs/agents/app-shell.md) — Usual Bot: app shell.
- [improvement-ideas.md](docs/agents/improvement-ideas.md) — Usual Bot: cross-project improvement ideas.
- [decisions.md](docs/agents/decisions.md) — Usual Bot: product and gateway decisions, and what isn't verified.
- [known-issues.md](docs/agents/known-issues.md) — Usual Bot: cross-project known issues.

## Documentation placement

- **The rule, whenever you write docs:** if it's solely about the Usual Bot software, it goes in this repository; otherwise it goes in the root Usual folder (the parent workspace; private Usual Bot notes in its `docs/agents/usual-bot/`).
- This is a public open-source repository. Keep only documentation solely about the Usual Bot software and appropriate for users or contributors: implementation, architecture, behavior, APIs, setup, testing, releases and guides. Technical decisions and artwork provenance belong with that software.
- Legal/IP reviews, trademark research, business/marketing strategy, launch plans, private internal decisions and maintainer account or publication-session records belong outside this repository. In the maintainer's Usual workspace, put private Usual Bot notes in the parent `docs/agents/usual-bot/` directory, not this repository's `docs/agents/`. In a standalone clone, keep those notes outside the checkout.
- Check placement before creating, moving, committing or publishing documentation. Keep public credits and licensing notices with the software; public build instructions must work without private notes or local maintainer scripts.

## Documentation

Most code changes need no KB change. Agents can read the code.

- Before adding a paragraph, ask what a maintainer would get wrong without it. If the code answers that, leave it out.
- Keep decisions and their reasons, constraints across components, traps, and what hasn't been verified. Don't enumerate types or methods, narrate control flow, catalog files or summarize pull requests.
- A local reason the code can't show goes in a short comment beside it.
- When a decision changes, rewrite or remove the text. Don't append.
- Don't commit plans, research or scratch notes. A merged pull request is the record of the work.

## Operating protocol

- Start with `02-project-map.md`, then read the target child project's `AGENTS.md`.
- Before changing something, read the KB files for that area and skim its known issues.
- Record non-obvious bugs and gotchas in `known-issues.md`, deferred improvements in `improvement-ideas.md`, and changed decisions in the file that holds them, in the same turn.
- Update workspace KBs only when relationships, boundaries, project routing or shared conventions change.
- Code is the source of truth. If code and the KB disagree, fix the KB. Distinguish implemented behavior from planned intent, and source evidence from runtime verification.
- Do not run browser tests unless explicitly requested. Keep changes focused, use YAGNI, and keep files below 500 lines where practical. Report meaningful behavior/setup/deployment changes after implementation.
