---
aliases: [extensions, plugins, remote intelligence, vps, runners, automation]
keywords: [extension manifest, plugin, remote runner, OpenAI-compatible, VPS, automation, quick action, renderer, importer]
tags: [demo, extensions, intelligence, roadmap]
---
# Extensions & Remote Intelligence

Cribble is local-first, but local-first should not mean small. This note shows
the new foundation for people who want to extend Cribble gently: simple
manifests first, trusted execution later.

## 1. Extension manifests

Open **Settings → Extensions** and click **Create Example**. Cribble writes a
starter folder in Application Support with a `cribble-extension.json` file:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.quick-action",
  "kind": "quick-action",
  "name": "Example Quick Action",
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "explain-jargon",
      "title": "Explain jargon",
      "icon": "text.magnifyingglass",
      "prompt": "Explain the specialized terms in the current note in plain language."
    }
  ],
  "summary": "Adds a user-authored action to Cribble's future extension command surface.",
  "version": "0.1.0"
}
```

Cribble validates the manifest and lists it in Settings. It does **not** execute
extension code yet. That boundary keeps the system safe while the design matures.

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
automation hooks can travel together.

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
| Renderer | Preview a custom diagram fence |
| Importer | Convert exported chats, PDFs, or research bundles into notes |

The rule is simple: every extension declares what it wants, Cribble shows that
clearly, and user files stay under user control.

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
Cribble shows a warning that note context may leave this Mac.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.team-runner",
  "name": "Team Runner",
  "version": "0.1.0",
  "kind": "intelligence-provider",
  "summary": "Adds a team-controlled OpenAI-compatible runner.",
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

### Renderer alias

Declares extra fenced-code languages that should map to a built-in renderer in
the future. Today this is inspectable metadata only.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.diagram-aliases",
  "name": "Diagram Aliases",
  "version": "0.1.0",
  "kind": "renderer",
  "summary": "Declares diagram fence aliases.",
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

Declares file types an importer wants to convert into Markdown later. Today it
is inspectable metadata only.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.chat-importers",
  "name": "Chat Importers",
  "version": "0.1.0",
  "kind": "importer",
  "summary": "Declares future chat export import lanes.",
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
