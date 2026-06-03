# Models

Plain value types (mostly `struct`/`enum`) shared across services and views.
These hold no behavior beyond derivation — the engine lives in `Services/`.

| File | Models |
| --- | --- |
| `MarkdownDocument.swift` | A loaded, parsed Markdown file ready to render. |
| `MarkdownNode.swift` | Tree nodes for the folder/file library. |
| `AppSettings.swift` | User preferences (theme, reader, AI provider). |
| `FileSortMode.swift` | Name / created / updated sort options. |
| `ReaderFontSizePreset.swift` | XXS–XXL reader text sizes. |
| `WikiLink.swift` | A parsed `[[wiki link]]` reference. |
| `UnresolvedTarget.swift` | A wiki link that did not resolve to a file. |
| `LinkedFileSummary.swift` | Summary of an inbound/outbound linked file. |
| `ReadingAnnotation.swift` | A highlight or reading bookmark. |
| `PathfinderRequest.swift` | Input for the note pathfinder feature. |
