# Cribble (app target)

The macOS app. Cribble is a local-first Markdown **reader**: it renders folders
of `.md` files beautifully, connects them with wiki links, and layers private,
preview-first AI on top — without ever becoming an editor.

## Architecture at a glance

```
App/         App entry point, menu commands, icon + update plumbing
Models/      Plain value types — documents, settings, annotations, links
Services/    The engine — scanning, parsing, link indexing, AI, intelligence
  ├ LocalLLM/      On-device + CLI chat engines and model catalog
  └ Intelligence/  Background workspace analysis, graphs, vectors, artifacts
Stores/      Observable state that the UI binds to (library, annotations, trail)
Support/     Cross-cutting helpers (typography, diagnostics, slugging, compat)
Views/       SwiftUI views — sidebar, reader, sheets, and the AI HUDs
  ├ ChatHUD/        The Cribble AI chat panel
  └ IntelligenceHUD/ The background-intelligence surface
Resources/   Bundled assets (DemoNotes library, Mermaid runtime)
```

## Data flow

1. **Scan** — `FolderScanner` walks an opened folder for folders + `.md` files.
2. **Load** — `DocumentLoader` reads a file; `FrontMatterParser` and the
   Markdown pipeline turn it into a `MarkdownDocument`.
3. **Index** — `LinkIndex` resolves wiki links; `SemanticSearchIndex` and the
   `Intelligence` services build search + graph data in the background.
4. **Render** — `Views` present the document with rich blocks, while `Stores`
   hold reading state (bookmarks, highlights, trail, library).
5. **Assist** — `AIService` / `LocalLLM` answer questions and propose links as
   reviewable patches; nothing touches disk without a preview.

## Principles enforced here

- **Read-only.** No code path writes user files except through a reviewed diff.
- **Local-first.** No network calls outside explicit AI provider requests.
- **Native.** SwiftUI + AppKit interop, system materials, no heavy custom chrome.
