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
  "id": "com.example.cribble.quick-action",
  "kind": "quick-action",
  "name": "Example Quick Action",
  "permissions": ["read-current-note"],
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

← Back to [[README|Home]] · next: [[Cribble AI]]
