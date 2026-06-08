# Product Improvisation Readiness Checkpoint

Date: 2026-06-08
Branch: `codex/product-improvisation-night`

This checkpoint is the scannable "where are we?" view for the product
improvisation branch. The long record is
[`product-improvisation-night-report.md`](product-improvisation-night-report.md);
the shorter narrative is
[`product-improvisation-summary.md`](product-improvisation-summary.md).
Use **Help > Copy Product Readiness Checkpoint** in the app when you need a
pasteable checkpoint for a pull request, release note, or maintainer handoff.

## Strong Product Signal

Cribble now has a clearer shape:

- A beginner can open DemoNotes, follow Help entries, copy starter templates,
  create notes safely, and understand the local-first AI boundary.
- A daily user can collect tasks, open Today, copy Markdown/wiki links, resume
  reading, and use Project Intelligence without hidden source-note writes.
- A power user can configure local, VPS, or team OpenAI-compatible intelligence
  runners with consent, Keychain secrets, diagnostics redaction, and revocation.
- A contributor can propose extensions through declarative manifests, copied
  proposals, in-app guides, and strict read-only/least-access/native-SwiftUI
  rules before executable plugins exist.

## Ready To Keep

These areas have enough product shape, tests, and documentation to keep as the
branch foundation:

| Area | Why keep it |
| --- | --- |
| DemoNotes onboarding | It now teaches basics, AI, tasks, research review, decisions, remote intelligence, and extension contribution rules from inside the app. |
| Native Help commands | Help recovers onboarding, contributor guides, starter templates, import-lane review, remote-runner review, and extension settings without requiring users to remember file paths. |
| Declarative extension API v1 | It opens a plugin ecosystem while avoiding hidden execution, source-note writes, and broad ambient access. |
| Remote runner review | It makes VPS/team intelligence useful while naming what may leave the Mac and where secrets live, with copyable review text from setup and preflight. |
| Diagnostics and handoffs | Copied reports, Settings summaries, and Markdown handoffs make support, PR review, and team sharing easier without leaking credentials, while preserving exact contribution, import, and remote-runner review routes. |

## Stop Conditions

Stop broadening the branch when a proposed change would require any of these
without a separate design phase:

- executable plugin runtime;
- signed bundle loading;
- scripts, shells, binaries, daemons, or background extension code;
- broad project reads without a consent boundary;
- source-note writes without preview/review/cancel;
- secrets in manifests, docs, examples, fixtures, tests, or DemoNotes;
- non-native extension UI without explicit maintainer approval;
- remote intelligence that hides retention, logging, endpoint ownership, or
  revocation.

Those are not small polish items. They are new trust-model work.

## Keep Going Only If

The next change should be small, native, and tied to one of these signals:

- faster first-minute onboarding;
- clearer local-vs-remote AI boundaries;
- safer extension proposal/review loops;
- better copied handoffs for teams and maintainers;
- reduced warning/noise in build, test, diagnostics, or support reports;
- copied diagnostics or Settings summaries that preserve native review routes;
- measurable refresh/indexing smoothness.

## Verification Snapshot

- Full `swift test` previously passed on this branch with 235 XCTest tests and
  43 Swift Testing tests, 0 failures.
- Later focused tests passed for Decision Log, Research Review, Extension
  Contribution Guide, executable readiness gates, remote-runner reviews,
  diagnostics, Settings summary review routes, and DemoNotes seeded artifacts.
- Known residual noise: intermittent CoreData XPC messages in broad macOS test
  runs. They have not failed tests.

## Not Done On Purpose

- No executable plugin runtime.
- No hidden extension execution.
- No signed bundle loading.
- No importer converter execution.
- No broad source-note writes outside explicit preview/review flows.

The branch should keep favoring smooth native affordances over a larger,
harder-to-trust automation surface.
