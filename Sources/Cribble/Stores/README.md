# Stores

Observable state objects that the SwiftUI views bind to. Stores own persistence
and mediate between `Services/` and `Views/`.

| File | Responsibility |
| --- | --- |
| `MarkdownLibraryStore.swift` | The opened-folders library and current selection. |
| `MarkdownLibraryStore+LocalGraph.swift` | Reader-facing local note graph neighborhoods. |
| `MarkdownLibraryStore+Related.swift` | Reader-facing related-note queries over the semantic index. |
| `MarkdownLibraryStore+Tags.swift` | Read-only tag index queries for tags and matching notes. |
| `ReadingAnnotationsStore.swift` | Highlights and reading bookmarks, persisted per file. |
| `ReadingTrailStore.swift` | The reading trail — where you've been, for resume + navigation. |
