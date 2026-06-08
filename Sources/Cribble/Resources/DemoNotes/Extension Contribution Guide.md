---
aliases: [extension contributions, plugin contributions, open source extensions]
keywords: [extensions, plugins, contributors, read-only, least access, native SwiftUI]
tags: [demo, extensions, contributors]
---
# Extension Contribution Guide

Use this note when you want to propose a Cribble extension as an open-source
contribution. Ideas should be open and ambitious. First pull requests should be
small, native, reviewable, and safe around people's notes.

## The rule of thumb

Start with a useful idea. Merge the smallest declarative version that proves it.

- **Read-only first:** begin with a manifest, validation rule, Settings summary,
  copied prompt, DemoNotes example, or review surface.
- **Least reading:** prefer the current note before folder-wide reads.
- **Least writing:** prefer generated artifacts or manifests before source-note
  edits; any source-note edit needs preview/review/cancel.
- **Hard native SwiftUI:** use Settings, sheets, menus, commands, toolbars,
  focused values, system controls, and SF Symbols.
- **No hidden execution:** API v1 extensions are declarative and do not run
  scripts, shells, binaries, daemons, or background code.
- **No secrets in files:** keep keys, tokens, private endpoints, passwords,
  certificates, and signing material out of manifests, examples, fixtures,
  tests, docs, and DemoNotes.
- **Clean disable path:** turning an extension off removes its commands, quick
  actions, renderer aliases, import lanes, runner profiles, and Settings
  summaries without restarting Cribble.

## First proposal

Use **Settings → Extensions → Copy Proposal** or
**Help → Copy Extension Proposal** before opening a code PR.

Answer these in the issue, Discussion, or pull request:

- Who does this help?
- Which repeated folder workflow gets smoother?
- What is the first read-only version?
- What does it read?
- What does it write?
- Does anything leave this Mac?
- Where are secrets stored?
- What native SwiftUI surface does the user review?
- What belongs later, not first PR?

## First PR lanes

| Lane | Good first contribution | Access posture |
| --- | --- | --- |
| Quick action | A prompt in the Chat HUD slash palette | Exactly `read-current-note` |
| Intelligence provider | Local, VPS, or team runner profile | Exactly `network-openai-compatible`; keys in Keychain |
| Renderer | Alias for a built-in renderer | No file access |
| Importer | Declared formats and review copy | No execution; user-selected files only |

## Manifest checks you will hit first

- Quick action ids and icons are safe tokens. Use SF Symbol-style icon names like
  `checklist` or `text.alignleft`; spaces, slashes, and paths are rejected.
- Remote runner `baseURL` and trust `sourceURL` values use HTTPS unless they
  target localhost development.
- Importer `fileExtensions` are bare and unique regardless of case: use `json`
  or `txt`, not `.json`, `*.json`, paths, or both `json` and `JSON`.

For importer ideas, use **Settings → Extensions → Import lanes → Copy Review**
once a lane appears, or **Help → Copy Import Lane Setup Review** /
**File → Import → Copy Review** before adding one. For remote runners, use
**Settings → Project Intelligence → Copy Review** or
**Help → Copy Remote Runner Setup Review**. Paste the copied review into the
proposal so reviewers can see data boundaries, writes, secrets, and revocation.
If Settings shows manifest validation warnings, use
**Settings → Extensions → Copy Warnings** before editing so the exact failure and
next-step checklist can be pasted into the issue, PR, or teammate review.

## Where to read more

- `docs/extension-contributions.md` is the open-source contribution guide.
- `docs/extensions.md` is the manifest reference and executable-readiness gate.
- [[Team Extension Kit]] shows the same rules as a team workflow.
- [[Extensions and Remote Intelligence]] shows current manifest lanes.

Executable plugins are a later product phase. Until signed bundle identity,
process isolation, brokered permissions, native consent, previewed writes,
Keychain-only secrets, revocation, audit trails, and native SwiftUI review
surfaces exist in code and tests, executable ideas stay in the "later, not first
PR" section.

← Back to [[Team Extension Kit]] · [[Extensions and Remote Intelligence]] · [[README|Home]]
