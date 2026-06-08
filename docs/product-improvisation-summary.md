# Product Improvisation Summary

Date: 2026-06-08
Branch: `codex/product-improvisation-night`

This is the short, human-readable version of the longer
[`product-improvisation-night-report.md`](product-improvisation-night-report.md).
For a scannable keep/stop/defer view, see
[`product-improvisation-readiness-checkpoint.md`](product-improvisation-readiness-checkpoint.md).

## What Changed

Cribble is no longer just a native Markdown reader with isolated AI features. It
now reads more like a local-first Mac knowledge workspace:

- **Start faster:** Welcome, Help, DemoNotes, shortcuts, and starter checklists
  now point beginners to the right first action, including direct decision-log
  templates, research-review templates, and team workflow routes.
- **Work daily:** New Note, Today notes, Tasks, Copy Markdown, Copy Markdown
  Link, Copy Wiki Link, Reading Trail summaries, Decision Log, and reviewed AI
  proposals make capture, rationale, research paths, and handoff feel native.
- **Use intelligence safely:** Project Intelligence has preflight review,
  source-grounded artifacts, Ask answers, copyable Markdown handoffs, diagnostics,
  Settings controls, and clear local-vs-remote boundaries.
- **Bring stronger compute when needed:** local/VPS/team OpenAI-compatible
  runners can be configured with Keychain secrets, data-boundary warnings,
  consent review, and copied approval checklists from Help, Settings, preflight,
  or the Intelligence HUD.
- **Start an extension ecosystem:** `cribble-extension.json` manifests now cover
  quick actions, remote runner profiles, renderer aliases, and import-lane
  declarations without executing extension code, with Settings-first proposal,
  import-lane review, and Project Intelligence review routes plus Help fallbacks
  and a dedicated open-source extension contribution guide for contributors.
- **Stay smooth in bigger folders:** scanner guardrails now skip more generated
  dependency and tool-cache folders, while copyable diagnostics/review summaries
  keep support and contributor loops precise.

## Strongest Product Signal

The branch has four strong bets:

| Bet | Why It Matters |
| --- | --- |
| Native onboarding | Users can recover from confusion through Help, DemoNotes, starter checklists, and role-based tour entries. |
| Review-first AI | AI can suggest notes, tasks, links, indexes, and intelligence artifacts without silently writing user files. |
| Safe extensibility | Contributors can propose useful extensions while API v1 stays declarative, read-only first, least-access, and native SwiftUI. |
| Trusted remote intelligence | Advanced users can use their own VPS/team runner without hiding that note context may leave the Mac. |
| Zero-file handoff | Users can copy trails, diffs, tasks, diagnostics, extension warnings, and intelligence artifacts before creating or changing files. |

## Extension Rules

The extension path is intentionally strict:

- API v1 loads declarative manifests only.
- First contributions should be read-only.
- Permissions must request the least possible access.
- Writes must go through preview/review/cancel.
- Secrets stay out of manifests, examples, fixtures, docs, and notes.
- User-facing UI must be native SwiftUI with system controls and SF Symbols.
- Web views, custom chrome, Electron-style panels, and executable plugins are
  deferred until a signed, sandboxed, revocable trust model exists.
- Executable plugin work now has explicit readiness gates in `docs/extensions.md`:
  signed identity, process isolation, brokered permissions, native consent,
  previewed writes, Keychain-only secrets, revocation, audit trail, and native UI.
- `docs/extension-contributions.md` is the standalone contributor on-ramp:
  ideas stay open, while first PRs must be read-only, least-access,
  least-writing, no-hidden-execution, cleanly disableable, and native SwiftUI.
- DemoNotes and Help expose an in-app Extension Contribution Guide so the same
  contributor rules are discoverable without leaving Cribble.
- The welcome Start With grid has a Contribute tile for extension authors and
  open-source contributors.
- Settings > Extensions can copy exact validation warnings with Check Again and
  contribution-guide next steps, so extension authors can paste reviewable
  failures into issues or PRs.
- Settings > Extensions copied dashboard summaries include Contribution Guide,
  Copy Warnings, extension proposal, import-lane Copy Review, and
  Project Intelligence review routes, so pasted status reports keep
  contributors oriented.
- Settings > Extensions now shows least-writing as its own starter rule beside
  read-only first, least access, and native Mac UI.

## What Was Verified

Focused validation passed across the newest work:

- DemoNotes copy and seeded intelligence artifacts.
- Decision Log DemoNotes workflow for rationale, evidence, review boundaries,
  and follow-up tasks.
- Help-copy template for new Decision Log entries.
- Help-copy template for evidence-heavy Research Review briefs.
- Import setup Copy Review boundaries.
- Extension dashboard and proposal summaries.
- Open-source extension contribution guide links and strict first-PR rules.
- Bundled Extension Contribution Guide note and native Help entry.
- Welcome Contribute tile for the extension contribution guide.
- Product readiness checkpoint with keep, stop, defer, and verification sections.
- Help-copy template for product readiness checkpoints and maintainer handoffs.
- Grouped Help menu sections for DemoNotes, guides, extension settings,
  copyable templates, diagnostics, and GitHub actions.
- Remote-runner consent and handoff checklists.
- Help-copy templates for extension proposals, import lane setup reviews, and
  remote-runner setup reviews, with Settings-native Copy Review routes for
  installed import lanes and Project Intelligence handoffs.
- Remote Project Intelligence preflight copy review for team/VPS runner starts.
- Diagnostics that distinguish local runners from remote runners before asking
  for Keychain credential recovery, and route remote credential issues through
  Help > Copy Remote Runner Setup Review.
- Diagnostics next actions, visible recovery strip, and exact extension review
  routes for contribution guide, proposal, import-lane, and remote-runner
  handoffs.
- Settings extension summaries that preserve the same native review routes for
  issues, PRs, and team chats.
- Settings Project Intelligence controls for performance, disk budget, chat
  context, Remote Guide, and Copy Review.
- Intelligence artifact and Ask answer Markdown handoffs.
- Reading Trail Copy Summary from both the panel and native Help menu.
- Extension validation Copy Warnings.
- Folder scanner skips for `.gradle`, `.terraform`, `.turbo`, `coverage`, and
  `vendor` to keep broad code folders lighter.

Full `swift test` passed after the latest broad Help command, Decision Log
DemoNotes, remote-runner, diagnostics, and report work: 235 XCTest tests and 43
Swift Testing tests, 0 failures. Newer Reading Trail, extension warning, remote
runner guide, and scanner slices were then covered by focused tests.

## Intentionally Not Done

These are deliberately deferred:

- No executable plugin runtime.
- No hidden extension execution.
- No signed bundle loading yet.
- No importer converter execution yet.
- No broad source-note writes outside explicit preview/review flows.

That restraint is part of the product direction: make Cribble broader without
making it slippery or unsafe.

## Next Best Bets

1. Keep polishing DemoNotes around real team workflows.
2. Design signed executable extension support only after the sandbox, trust,
   audit, and revocation model is concrete.
3. Continue reducing build/test warning noise so support reports stay readable.
