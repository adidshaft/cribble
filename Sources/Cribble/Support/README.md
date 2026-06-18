# Support

Cross-cutting helpers and extensions used throughout the app.

| File | Responsibility |
| --- | --- |
| `MarkdownDisplayPreprocessor.swift` | Prepares raw Markdown for the renderer. |
| `CalloutBlock.swift` | Parses Obsidian-style callout/admonition blockquotes. |
| `CalloutStyle.swift` | Maps callout types to native symbols and semantic accents. |
| `RichMarkdownBlock.swift` | Splits a document into rich fenced blocks (code, Mermaid, charts, math). |
| `ReaderTypographyEnvironment.swift` | Reader fonts, sizing, and spacing (Roobert + Monaco). |
| `CompatibilityStyles.swift` | Liquid Glass on macOS 26+ with native fallbacks. |
| `DiagnosticsCenter.swift` | Collects diagnostic info for user reports. |
| `GitHubReport.swift` | Builds prefilled GitHub issue / PR report links. |
| `Slugger.swift` | Heading → slug/anchor conversion. |
| `CollectionExtensions.swift` / `URLExtensions.swift` | Small standard-library conveniences. |
| `SPMBundleAccessorFix.swift` | Works with `CribbleBundleRedirect` to resolve `Bundle.module`. |
