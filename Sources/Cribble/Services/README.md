# Services

The engine. Pure-ish logic that turns folders of Markdown into rendered,
connected, searchable documents — and powers AI features. Most files here are
unit-tested in [`Tests/CribbleTests`](../../../Tests/CribbleTests).

## Reading pipeline

| File | Responsibility |
| --- | --- |
| `FolderScanner.swift` | Walks a folder for sub-folders and `.md` files. |
| `DocumentLoader.swift` | Reads a file and prepares it for display. |
| `FrontMatterParser.swift` | Parses YAML front matter (aliases, tags, keywords). |
| `WikiLinkParser.swift` | Extracts `[[Note]]`, `[[Note#Heading]]`, `[[Note|Label]]`. |
| `LinkIndex.swift` | Resolves wiki links across the library to real files. |
| `TaskCheckbox.swift` | Parses and toggles `- [ ]` / `- [x]` task markers. |
| `FileChangeMonitor.swift` | Watches files on disk and triggers auto-reload. |

## Search & AI

| File | Responsibility |
| --- | --- |
| `SemanticSearchIndex.swift` | Local embedding-based semantic search. |
| `AIService.swift` | Provider-agnostic AI link suggestions (preview-first). |
| `UnifiedDiff.swift` | Parse + safely apply unified diffs from AI output. |
| [`LocalLLM/`](LocalLLM) | On-device (MLX) and CLI chat engines + model catalog. |
| [`Intelligence/`](Intelligence) | Background workspace analysis, graphs, vectors. |

> **Safety boundary:** AI tooling runs read-only and returns diffs. Files are
> only changed after the user approves a native patch preview.
