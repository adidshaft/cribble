---
aliases: [extensions, plugins, remote intelligence, vps, runners, automation]
keywords: [extension manifest, plugin, remote runner, OpenAI-compatible, VPS, automation, quick action, renderer, importer]
tags: [demo, extensions, intelligence, roadmap]
---
# Extensions & Remote Intelligence

Cribble is local-first, but local-first should not mean small. This note shows
the new foundation for people who want to extend Cribble gently: data-only
manifests now, trusted execution only after a signed/revocable model exists.

## 1. Extension manifests

Open **Settings → Extensions** and use **Create Example** for a personal
extension, or **Create Project Example** when you want the manifest to live in
the active folder's `.cribble/extensions` directory. Cribble can write starter
folders for quick actions, trusted runners, renderer aliases, and import lanes.
The Quick Action template looks like this:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.quick-action",
  "kind": "quick-action",
  "name": "Example Quick Action",
  "permissions": ["read-current-note"],
  "runtime": "declarative",
  "quickActions": [
    {
      "id": "explain-jargon",
      "title": "Explain jargon",
      "icon": "text.magnifyingglass",
      "prompt": "Explain the specialized terms in the current note in plain language."
    }
  ],
  "summary": "Adds a user-authored action to Cribble's Chat HUD command surface.",
  "version": "0.1.0"
}
```

Cribble validates the manifest and lists it in Settings. Use **Check Again** to
reload manifests after editing them, and use the copy-details button on an
installed extension row when you want to paste a review summary into a team
handoff. Use **Copy Proposal** when the idea still needs review before a
manifest exists. API v1 extensions use `"runtime": "declarative"` and Cribble rejects
executable runtimes for now. That boundary keeps the system safe while the
design matures.

Current API v1 permission rules are strict:

- quick actions use exactly `read-current-note`;
- remote runner profiles use exactly `network-openai-compatible`;
- renderer aliases and import lanes request no permissions;
- project-wide reads and proposed file writes are reserved until Cribble has a
  consented review flow for them.

Extension quick actions receive the current note and any files you explicitly
attach for that send. They do not automatically receive related-note or Project
Intelligence context.

## 2. Project-local plugins

Teams can keep extension ideas next to the notes they affect:

```text
Research Folder/
  .cribble/
    extensions/
      case-timeline/
        cribble-extension.json
```

That makes a folder portable: the notes, the reading conventions, and future
automation hooks can travel together. This is the path to use when a team wants
the same prompts, runner profile, renderer aliases, or import lanes to follow a
shared vault.

## 3. Remote intelligence runners

For everyday reading, on-device models are the best default. For heavier work,
you may want a trusted runner somewhere else: a Mac Studio, a private VPS, a
team GPU box, or a hosted OpenAI-compatible service.

Cribble's Intelligence HUD already speaks OpenAI-compatible `/v1` APIs for
local runners like Ollama, llama.cpp, and LM Studio. The extension foundation
turns that into a broader design:

- **Light users** keep everything on-device and never think about endpoints.
- **Power users** can point Cribble at a trusted runner for larger models.
- **Teams** can package a runner profile as an extension manifest with clear
  permissions and setup notes.

## 4. What extensions should become

Good extensions should feel native, inspectable, and reversible:

| Extension kind | Example |
| --- | --- |
| Quick Action | Turn highlighted text into a follow-up question |
| Intelligence Provider | Use a trusted OpenAI-compatible runner |
| Renderer | Map a custom diagram fence to a built-in renderer |
| Importer | Declare import lanes for exported chats, PDFs, or research bundles |

The rule is simple: every extension declares what it wants, Cribble shows that
clearly, user files stay under user control, and secrets live in Keychain — never
in `cribble-extension.json`.

## 5. Copy-ready manifest patterns

These are **declarations**, not executable plugins. Cribble validates them,
lists them in Settings, and only routes supported data-only contributions
through existing safe UI.

### Quick action

Adds a prompt to the Chat HUD empty state and `/` command palette.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.research-actions",
  "name": "Research Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds research-oriented prompts.",
  "permissions": ["read-current-note"],
  "runtime": "declarative",
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

### Trusted remote runner

Adds a preset to the Intelligence HUD model picker. If the URL is not loopback,
Cribble shows a native review sheet before applying the runner. It names the
endpoint, model, extension source, trust label, Keychain state, disable path,
and the fact that note context may leave this Mac.

Do **not** put API keys in the manifest. Add the profile here, then paste the
token into the Intelligence HUD and store it in Keychain when you choose the
runner.

Before sharing a remote runner profile, use
**Settings → Project Intelligence → Copy Review** or
**Help → Copy Remote Runner Setup Review** and write down:

- who owns the endpoint;
- the model id people should select;
- the trust label users will see in Cribble;
- the source extension or review thread people can inspect;
- what note context may leave the Mac;
- where the API key is entered and whether it should be saved to Keychain;
- how to disable the extension or revoke the runner;
- when people should choose the on-device model instead.

Paste the copied review into an issue, PR, or team note before people enable the
runner:

```md
# Remote Runner Setup Review

Runner name:
Endpoint:
Model:
Embeddings:
Trust label:

Context boundary:
Prompts, note excerpts, generated summaries, and embedding requests may leave this Mac for the selected runner.

Approval checklist:
- Endpoint is controlled by the user, team, or trusted vendor.
- Retention policy, logging, and access controls are understood before use.
- Requested note context is appropriate for this runner.
- Secrets stay out of manifests and notes; use Keychain only.
- Disable path is understood before approval.
```

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.team-runner",
  "name": "Team Runner",
  "version": "0.1.0",
  "kind": "intelligence-provider",
  "summary": "Adds a team-controlled OpenAI-compatible runner.",
  "permissions": ["network-openai-compatible"],
  "runtime": "declarative",
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

### Renderer alias

Declares extra fenced-code languages that should map to a built-in renderer.
For example, a `workflow` fence can render through Cribble's bundled Mermaid
renderer without running extension code.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.diagram-aliases",
  "name": "Diagram Aliases",
  "version": "0.1.0",
  "kind": "renderer",
  "summary": "Declares diagram fence aliases.",
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

### Import lane

Declares file types an importer wants to convert into Markdown later. Today the
lane appears in Settings so teams can agree on supported import formats before
Cribble executes converters.

Before writing the manifest, choose **Help → Copy Import Lane Setup Review** or
**File → Import → Copy Review** to paste the pre-install safety contract into a
proposal thread: no converter execution, user-selected files only,
previewed writes, no secrets, native SwiftUI controls, and clean disabling.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.chat-importers",
  "name": "Chat Importers",
  "version": "0.1.0",
  "kind": "importer",
  "summary": "Declares future chat export import lanes.",
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

← Back to [[README|Home]] · next: [[Cribble AI]]
