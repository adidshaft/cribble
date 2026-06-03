# CribbleTests

Unit and logic tests for the `Cribble` target. `Fixture.swift` provides shared
helpers; fixtures on disk live in [`Fixtures/`](../../Fixtures).

## Reading & Markdown

| Test | Covers |
| --- | --- |
| `FolderScannerTests` | Folder/file discovery and filtering. |
| `FolderPinningTests` | Pinning folders in the library. |
| `DocumentLoaderTests` | Loading + preparing documents. |
| `MarkdownDisplayPreprocessorTests` | Display preprocessing. |
| `RichMarkdownBlockTests` | Fenced-block splitting (code/Mermaid/charts/math). |
| `WikiLinkParserTests` / `LinkIndexTests` | Wiki-link parsing and resolution. |
| `NavigationHistoryTests` | Back/forward navigation. |
| `TaskCheckboxTests` | Task-marker parse/toggle. |

## Reading state

| Test | Covers |
| --- | --- |
| `ReadingAnnotationsStoreTests` | Highlights + bookmarks persistence. |
| `ReadingTrailStoreTests` | Reading trail behavior. |
| `ReadingHighlightAnchorTests` / `HighlightedMarkdownParserOffsetTests` / `TaskHighlightResolutionTests` | Highlight anchoring + offset math. |

## Search, AI & diagnostics

| Test | Covers |
| --- | --- |
| `SemanticSearchIndexTests` | Local semantic search. |
| `PathfinderTests` | Note pathfinding. |
| `UnifiedDiffTests` | Diff parse/apply safety. |
| `ChatHUDLogicTests` | Chat HUD view-model logic. |
| `StreamingUTF8DecoderTests` | UTF-8 chunk-boundary decoding for streaming. |
| `DiagnosticsCenterTests` | Diagnostic report collection. |
| `CribbleUITests` | UI-level smoke coverage. |
