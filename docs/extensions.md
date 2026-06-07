# Cribble Extensions

Cribble extensions are currently declarative. They let users and teams describe
safe contributions in `cribble-extension.json` files, and Cribble validates those
manifests before showing their capabilities in the app.

API v1 does not execute extension code. Executable plugins will require a
separate trust model before they are supported.

## Where Extensions Live

User extensions live in:

```text
~/Library/Application Support/Cribble/Extensions/
```

Project extensions live inside an opened note folder:

```text
Your Notes/
  .cribble/
    extensions/
      your-extension/
        cribble-extension.json
```

Project extensions win over user extensions with the same id. This lets a folder
carry its own conventions without permanently changing the user's global setup.

## Create A Starter

Open **Settings > Extensions > Create Example** to write a starter manifest into
the user extensions folder. Templates are available for:

- quick actions;
- OpenAI-compatible remote runners;
- renderer aliases;
- import lanes.

## Manifest Shape

Every extension folder needs a `cribble-extension.json` file:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.research-actions",
  "name": "Research Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds research-oriented prompts.",
  "runtime": "declarative",
  "trust": {
    "developerName": "Example Team",
    "signingIdentifier": "com.example.cribble.research-actions",
    "teamIdentifier": "ABCDE12345",
    "sourceURL": "https://example.com/cribble-extension/source"
  },
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "extract-claims",
      "title": "Extract claims",
      "icon": "checklist",
      "prompt": "Extract the factual claims from the current note and list what evidence each claim needs."
    }
  ]
}
```

Required fields:

- `apiVersion`: currently `1`.
- `id`: reverse-DNS style id with at least three parts, such as `com.example.cribble.tool`.
- `name`: human-readable name shown in Settings.
- `version`: extension version string.
- `kind`: one of `quick-action`, `intelligence-provider`, `renderer`, or `importer`.
- `summary`: short user-facing explanation.
- `runtime`: use `declarative`.

Optional fields:

- `homepage`: `http` or `https` URL.
- `trust`: developer identity metadata Cribble can show now and compare against
  future signed executable bundles.
- `permissions`: typed permission strings.

`entrypoint` is intentionally unused for API v1. Manifests that request
`"runtime": "executable"` are rejected.

## Trust Model For Future Executable Plugins

Cribble's extension system starts with declarative manifests because those are
inspectable, reversible, and easy to keep local-first. Executable plugins should
not be added until the product can make trust visible and enforceable.

Before Cribble accepts `"runtime": "executable"`, the plugin surface should
require:

- signed plugin bundles with a stable developer identity;
- a first-run consent sheet that names the plugin, developer, requested
  permissions, network destinations, and note-folder access;
- a sandboxed process boundary instead of loading third-party code into the app;
- per-permission enforcement, including separate approval for file writes,
  project-wide reads, network access, and remote intelligence calls;
- Keychain-only secret storage, with no secrets in manifests or plugin folders;
- a revocation path in Settings that disables the plugin, clears cached trust,
  and stops background work;
- a visible audit log for file edits, remote calls, and generated artifacts.

### Executable Readiness Gates

Treat executable plugins as a separate product phase, not an incremental toggle.
A proposal is not ready to merge runtime execution until it can show evidence
for every gate below:

| Gate | Required proof |
| --- | --- |
| Signed bundle identity | The bundle signature matches the manifest `trust.signingIdentifier`, optional Apple Team ID, and a stable source/release URL. |
| Process isolation | Third-party code runs outside the Cribble app process with a narrow IPC protocol and no ambient access to note folders. |
| Permission broker | Reads, writes, network calls, remote-runner use, and generated artifacts are mediated by Cribble, not direct plugin syscalls. |
| Native consent | A SwiftUI review sheet names developer identity, requested permissions, data boundary, network destinations, writes, and disable/revoke path before first use. |
| Previewed writes | Source-note edits and generated files use the same preview/review/cancel pattern as AI proposals and import lanes. |
| Secret handling | API keys, tokens, certificates, and private endpoints stay in Keychain or user-entered runtime settings, never in manifests or plugin bundles. |
| Revocation | Settings can disable the plugin, clear remembered trust, stop background work, and remove contributed commands/lanes without restart. |
| Audit trail | Users and maintainers can copy a report of file reads, proposed writes, network destinations, generated artifacts, and plugin errors without leaking secrets. |
| Native UI | Any user-facing surface is SwiftUI, system controls, menus, toolbars, sheets, Settings, or commands; web views and custom chrome need explicit maintainer approval. |

Until those gates exist in code and tests, executable proposals should ship as
declarative manifests, validation improvements, native review surfaces, or
copied proposal/review templates.

API v1 validates the shape of `entrypoint` paths so manifests can evolve without
breaking compatibility, but executable entrypoints are not launched. It also
validates optional `trust` declarations:

- `developerName`: human-readable developer or team name.
- `signingIdentifier`: reverse-DNS bundle identifier expected for future signed code.
- `teamIdentifier`: optional 10-character Apple Team ID.
- `sourceURL`: optional `http` or `https` URL for the extension source or release page.

Cribble also keeps a local trust-decision store for future executable plugins.
Settings can revoke or clear a remembered trust decision for manifests that
declare trust metadata. This does not enable executable plugins in API v1; it
only establishes the consent and revocation path ahead of code execution.

## Kinds

### Quick Action

Quick actions add prompts to the Chat HUD empty state and slash-command palette.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.research-actions",
  "name": "Research Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds research-oriented prompts.",
  "runtime": "declarative",
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "extract-claims",
      "title": "Extract claims",
      "icon": "checklist",
      "prompt": "Extract the factual claims from the current note and list what evidence each claim needs."
    }
  ]
}
```

### Intelligence Provider

Provider profiles add OpenAI-compatible runner presets to the Intelligence HUD.
They can point to local runners or trusted remote machines.

Never put API keys in a manifest. Users enter keys in the Intelligence HUD and
can store them in Keychain.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.team-runner",
  "name": "Team Runner",
  "version": "0.1.0",
  "kind": "intelligence-provider",
  "summary": "Adds a team-controlled OpenAI-compatible runner.",
  "runtime": "declarative",
  "permissions": ["network-openai-compatible"],
  "intelligenceProviders": [
    {
      "id": "research-gpu",
      "title": "Research GPU",
      "baseURL": "https://ai.example.com/v1",
      "modelID": "qwen3-32b",
      "embeddingModelID": "text-embedding-3-small",
      "trustLabel": "Team-controlled VPS"
    }
  ]
}
```

### Renderer

Renderer extensions map extra fenced-code languages onto existing built-in
renderers. For example, a team can make `workflow` fences render through the
bundled Mermaid renderer.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.diagram-aliases",
  "name": "Diagram Aliases",
  "version": "0.1.0",
  "kind": "renderer",
  "summary": "Maps team diagram fences to built-in renderers.",
  "runtime": "declarative",
  "renderers": [
    {
      "id": "workflow-diagrams",
      "title": "Workflow Diagrams",
      "languages": ["workflow", "flowchart"],
      "builtInRenderer": "mermaid"
    }
  ]
}
```

Supported built-in renderer ids:

- `mermaid`
- `graphviz`
- `chart`
- `math`
- `markdown`

### Importer

Importer extensions declare file types a future converter intends to turn into
Markdown. Today they appear as import lanes in Settings so teams can agree on
formats before converter execution exists. The File > Import command can choose
a matching file and show which enabled lane it would use.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.chat-importers",
  "name": "Chat Importers",
  "version": "0.1.0",
  "kind": "importer",
  "summary": "Declares chat export import lanes.",
  "runtime": "declarative",
  "importers": [
    {
      "id": "chat-export",
      "title": "Chat Export",
      "fileExtensions": ["json", "txt"],
      "outputFormat": "markdown"
    }
  ]
}
```

## Permissions

Known permission strings:

- `read-current-note`
- `read-project-notes`
- `propose-file-changes`
- `network-openai-compatible`

Permissions are shown to users in Settings. They are not a bypass: API v1 still
routes every contribution through Cribble's existing safe surfaces.

Permission rules are intentionally narrow in API v1:

- quick-action extensions that contribute prompts must request exactly
  `read-current-note`; when run, they receive the current note plus any
  user-selected attachments for that send, but not automatic related-note or
  Project Intelligence context;
- intelligence-provider extensions that contribute remote runner profiles must
  request exactly `network-openai-compatible`;
- renderer and importer extensions must not request permissions because they
  are declarative aliases or lanes only;
- `read-project-notes` is reserved for a future consented project-scope API and
  is rejected by API v1 manifests;
- `propose-file-changes` is reserved for a future preview/review capability and
  is rejected by API v1 manifests.

## Validation Rules

Cribble rejects manifests that:

- use an unsupported `apiVersion`;
- use an id that is not reverse-DNS shaped;
- request `"runtime": "executable"`;
- use a non-HTTP homepage;
- point `entrypoint` outside the extension folder;
- include secret-looking fields or values such as API keys, bearer tokens,
  passwords, private keys, authorization headers, or token query strings;
- request permissions that do not match the extension kind or API v1 safety
  boundary;
- declare contributions under the wrong `kind`;
- duplicate contribution ids within a manifest;
- use unsafe language, importer, or contribution tokens.

## Designing A Good Extension

Good Cribble extensions should be:

- inspectable: a user can understand the manifest without reading code;
- reversible: disabling the extension removes its contributions;
- local-first: secrets stay out of manifests and source notes stay under user control;
- narrow: one extension kind per manifest;
- helpful immediately: provide a clear title, summary, and practical contribution.

## Open Source Extension Contribution Guide

Cribble welcomes extension ideas, but the contribution bar is deliberately
strict because extensions sit close to people's notes. Contributors should feel
free to propose ambitious workflows, while implementation should start from the
smallest native, reviewable surface that proves the value.

For the standalone contributor on-ramp, start with
[`extension-contributions.md`](extension-contributions.md). This API reference
keeps the same rules inline so manifest authors can review them without leaving
the page.

Start with an idea before a runtime. A good proposal should explain:

- who the extension helps;
- which repeated workflow it makes smoother;
- what the first read-only version would expose in Cribble;
- what data it needs to read, write, or send over the network;
- what native SwiftUI surface users would review before anything changes.

### Idea Proposal Template

Use this shape for issues, Discussions, or early pull requests. It keeps
ambitious ideas welcome while making the first mergeable step concrete:

GitHub also includes an **Extension proposal** issue template with these same
sections. Prefer that template before opening a code PR for a new extension
surface.

```markdown
## Extension idea

Audience:
Workflow:
Why Cribble:

## First read-only version

Manifest kind:
What appears in Cribble:
What user reviews before anything changes:

## Data contract

Reads:
Writes:
Network:
Secrets:
Disable behavior:

## Native Mac surface

SwiftUI surface:
System controls/SF Symbols:
Settings or command entry point:
Non-native UI needed? If yes, explain maintainer approval:

## Later, not first PR

What would need executable code:
What would need project-wide reads:
What would need source-note writes:
```

Fill `Reads`, `Writes`, `Network`, and `Secrets` with `none` when possible. If
they are not `none`, describe the smallest scope and the user-visible consent or
review surface.

Default rules for extension pull requests:

- **Read-only first.** New extension capabilities should start as manifest
  validation, settings visibility, command discovery, previews, or copied
  prompts. Do not add source-note writes as part of a first version.
- **Least writing.** When a write is truly necessary, prefer writing a new
  project-local manifest or generated artifact over editing user notes. Any note
  edit must go through an explicit preview/review flow and be easy to cancel.
- **Least reading.** Request `read-current-note` before `read-project-notes`.
  Project-wide access needs a specific user-facing reason and should avoid
  retaining full note bodies longer than needed.
- **No hidden execution.** API v1 contributions stay declarative. Do not run
  scripts, shell commands, bundled binaries, background daemons, or network
  calls from an extension PR.
- **No secrets in files.** Manifests, examples, fixtures, and docs must never
  contain API keys, tokens, private endpoints, passwords, certificates, or
  signing credentials. Use Keychain-backed app flows for secrets.
- **Native SwiftUI only for UI.** Extension UI work should use standard SwiftUI
  controls, Settings sections, sheets, menus, commands, toolbars, focused
  values, and system symbols. Avoid web views, custom chrome, non-native
  component frameworks, or visual patterns that fight macOS.
- **Data before abstraction.** Add a typed manifest field, validation rule,
  setting, demo note, or focused test before introducing a new runtime layer.
- **Disable cleanly.** Turning an extension off should remove its contribution
  from menus, HUDs, settings summaries, import lanes, renderer aliases, and
  provider lists without restarting the app.
- **Document the trust story.** Any remote runner, importer, renderer, or future
  executable proposal must explain what it reads, what it writes, whether it
  touches the network, how secrets are stored, and how a user revokes it.

### First Extension PR Recipe

Use this as the copy-paste shape for a first extension contribution:

1. Pick one manifest kind: quick action, intelligence provider, renderer, or
   importer.
2. Start from **Settings > Extensions > Create Project Example** so the manifest
   lives in `.cribble/extensions` beside the notes it affects.
3. Keep the first PR declarative and read-only. Prove the workflow through a
   manifest, validation rule, Settings affordance, DemoNotes example, or copied
   prompt before proposing runtime execution.
4. Include this checklist in the pull request:
   `reads`, `writes`, `network`, `secrets`, `disable behavior`.
5. Paste the copied extension details from Settings into the PR so reviewers can
   inspect id, kind, permissions, runtime, trust metadata, and contributions
   without checking out the branch.
6. For importer ideas, use **File > Import > Copy Review** before creating or
   adapting a manifest. Paste that pre-install review into the issue or PR so
   reviewers can see the no-execution, user-selected-files, previewed-writes,
   no-secrets, native SwiftUI, and clean-disable boundaries up front.
7. For support or release handoff, use **Help > Copy Diagnostic Report** after
   reloading extensions. The report includes installed/enabled counts, validation
   warnings, manifest summaries, permissions, and contribution titles without
   including API keys from Keychain.
8. Add or update focused tests when validation, discovery, disabled-state
   filtering, renderer aliases, importer lanes, provider profiles, or quick
   action routing changes.

Good first extension contributions include:

- new declarative template examples;
- stricter manifest validation and clearer validation errors;
- Settings summaries that make extension permissions easier to review;
- DemoNotes examples for team workflows;
- read-only renderer aliases and import-lane declarations;
- tests proving disabled extensions contribute nothing.

Discuss broader ideas early. A strong proposal can be creative and ambitious,
but the first merged step should preserve Cribble's local-first, reader-first,
native Mac defaults.

For an interactive tour, open the bundled DemoNotes library and read
`Extensions and Remote Intelligence.md`.
