---
aliases: [decisions, decision log, ADR, product signal]
keywords: [decision, log, team, review, rationale, project intelligence]
tags: [demo, workflow, team]
---
# Decision Log

Use this note when a team needs to remember why something changed, not just what
changed. It is intentionally plain Markdown so it works for one person, a small
team, or an open-source contributor reading the folder later.

## Decision entry template

Use **Help → Copy Decision Entry Template** to copy this block into your own
notes:

```markdown
## YYYY-MM-DD - Decision title

Status: proposed | accepted | reversed
Owner:

Context:

Decision:

Evidence:
- [[Research Review]]
- [[Tasks and Intelligence]]

Follow-up:
- [ ] Add task
- [ ] Review in Project Intelligence

Review boundary:
- What did Cribble read?
- What may leave this Mac?
- What can be disabled or reverted?
```

## Example

## 2026-06-08 — Keep extension API v1 declarative

Status: accepted
Owner: Cribble maintainers

Context:

Cribble should let people add useful folder-specific behavior without turning
the app into an unsafe automation host.

Decision:

Extension API v1 accepts declarative manifests only: quick actions, remote runner
profiles, renderer aliases, and import-lane declarations. Executable plugins wait
for a signed, sandboxed, revocable trust model.

Evidence:

- [[Team Extension Kit]] defines the contributor review checklist.
- [[Extensions and Remote Intelligence]] shows the current manifest lanes.
- **Help → Copy Extension Proposal** gives contributors a read-only-first shape.
- `docs/extensions.md` lists executable readiness gates before any runtime
  execution can merge.

Follow-up:

- [ ] Keep importers declarative until preview/review/cancel writes are designed.
- [ ] Use **File → Import → Copy Review** for importer proposals.
- [ ] Use **Help → Copy Remote Runner Setup Review** before enabling a team VPS.

## How Cribble helps

- Use **File → Copy Markdown Link** to cite the decision in a PR, issue, or chat.
- Use **Help → Copy Decision Entry Template** when a decision should survive the
  week.
- Use **AI → Extract Tasks from Current Note** to turn follow-up bullets into a
  reviewed `Tasks.md` proposal.
- Use **Project Intelligence** later to ask whether newer notes contradict this
  decision.
- Keep the decision readable without a plugin, database, or account.

← Back to [[Workflow Playbook]] · [[Research Review]] · [[Team Extension Kit]]
