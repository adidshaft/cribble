# Open Source Extension Contributions

Cribble welcomes extension ideas from contributors. The idea space should be
open: research workflows, team runners, renderer aliases, importer lanes,
support tools, accessibility helpers, and folder-specific conventions are all
worth discussing.

The first mergeable implementation is intentionally strict. Extensions sit close
to people's notes, so every contribution must start from the smallest native,
reviewable surface that proves the workflow without surprising the user.

## Ground Rules

- **Read-only first.** First versions should be declarative manifests,
  validation rules, Settings summaries, command discovery, preview surfaces,
  DemoNotes examples, or copied prompts. Do not write source notes in the first
  PR.
- **Least reading.** Prefer `read-current-note` over broader folder access.
  Project-wide reads need a specific user-facing reason, a visible consent
  boundary, and tests proving the access is required.
- **Least writing.** If a write is required, prefer a new project-local manifest
  or generated artifact. Source-note edits must use explicit preview/review/cancel
  UI and be easy to abandon.
- **Hard native SwiftUI condition.** User-facing extension UI must use native
  SwiftUI surfaces: Settings, sheets, menus, commands, toolbars, focused values,
  system controls, and SF Symbols. Avoid web views, custom chrome, Electron-style
  panels, or non-native component frameworks; they require
  explicit maintainer approval before implementation.
- **No hidden execution.** API v1 extensions are declarative. Do not add shell
  commands, scripts, bundled binaries, background daemons, or runtime code
  execution from an extension PR.
- **No secrets in files.** Manifests, docs, examples, fixtures, tests, and
  DemoNotes must not contain API keys, tokens, passwords, private endpoints,
  certificates, or signing credentials. Secrets belong in Keychain-backed app
  flows.
- **Clean disable path.** Disabling an extension must remove its commands,
  quick actions, renderer aliases, import lanes, runner profiles, and Settings
  summaries without restarting Cribble.

## Idea-First Proposal

Use **Help > Copy Extension Proposal** or the GitHub **Extension proposal**
issue template before opening a code PR. A strong proposal should answer:

- who the extension helps;
- which repeated folder workflow it improves;
- what the first read-only version exposes in Cribble;
- what it reads, writes, sends over the network, or stores;
- what native SwiftUI surface the user reviews before anything changes;
- what belongs in a later executable phase, not the first PR.

Good ideas can be ambitious. The first implementation should still be boring in
the best way: declarative, inspectable, reversible, and easy to test.

## First PR Recipe

1. Pick exactly one manifest kind: `quick-action`, `intelligence-provider`,
   `renderer`, or `importer`.
2. Start from **Settings > Extensions > Create Project Example** so the manifest
   lives in `.cribble/extensions` beside the notes it affects.
3. Keep `runtime` set to `declarative`.
4. Fill in `trust.developerName`, `trust.signingIdentifier`, and `sourceURL`
   when known so reviewers can see who is proposing the capability.
5. Paste copied extension details from Settings into the PR.
6. Include a short data contract:
   `reads`, `writes`, `network`, `secrets`, `disable behavior`.
7. Add focused tests for validation, discovery, disabled-state filtering,
   summaries, renderer aliases, importer lanes, provider profiles, or quick
   action routing when those behaviors change.

## Lane Defaults

| Lane | First contribution | Access posture |
| --- | --- | --- |
| Quick action | A useful prompt in the Chat HUD slash palette | Exactly `read-current-note` |
| Intelligence provider | A local, VPS, or team OpenAI-compatible runner profile | Exactly `network-openai-compatible`; API keys in Keychain |
| Renderer | A safe alias for an existing built-in renderer | No file access |
| Importer | Declared file extensions and review copy for a future converter | No execution; user-selected files only |

Importer proposals must use **Help > Copy Import Lane Setup Review** or
**File > Import > Copy Review** before adding or adapting a manifest.
Remote-runner proposals must use **Help > Copy Remote Runner Setup Review** so
ownership, retention, logging, access controls, Keychain handling, and
revocation are visible.

## Executable Plugins

Executable plugins are not supported by API v1. Keep executable ideas in the
proposal's "Later, not first PR" section until Cribble has signed bundle
identity, process isolation, brokered permissions, native consent, previewed
writes, Keychain-only secrets, revocation, audit trails, and native SwiftUI
review surfaces in code and tests.

The readiness gates start with signed bundle identity, process isolation, and a
Cribble permission broker before any executable runtime can merge.

See [extensions.md](extensions.md) for the full manifest reference and executable
readiness gates.
