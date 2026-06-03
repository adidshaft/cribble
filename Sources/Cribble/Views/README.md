# Views

SwiftUI views. The library lives in the sidebar, documents render in the reader,
and focused tasks open as sheets/overlays. The AI chat surface has its own
sub-folder.

## Shell & reading

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | Root layout (sidebar + reader). |
| `SidebarView.swift` | Folder/file library navigation. |
| `ReaderView.swift` | The rendered Markdown reading surface. |
| `OutlineView.swift` | Document outline / heading navigation. |
| `ReadingTrailPanel.swift` | Reading trail and resume strip. |
| `TaskListView.swift` | Interactive task-list rendering. |
| `SettingsView.swift` | App preferences window. |

## Reading interactions

| File | Responsibility |
| --- | --- |
| `HighlightInteractionOverlay.swift` | Drag-to-highlight overlay + cursor. |
| `HighlightNotePopover.swift` | Notes attached to a highlight. |
| `NotePreviewPopover.swift` | Hover/peek preview of a linked note. |
| `DiagramZoomOverlay.swift` | Full-screen zoom for Mermaid/diagrams. |
| `FolderIconPicker.swift` | Per-folder icon picker. |
| `UnresolvedTargetView.swift` | UI for unresolved wiki links. |

## Sheets

| File | Responsibility |
| --- | --- |
| `AIProviderSheet.swift` | Choose/configure the AI provider. |
| `DiffPreviewSheet.swift` | Review AI-proposed link patches before applying. |
| `PathfinderSheet.swift` | Find a path between two notes. |
| `DiagnosticsReportSheet.swift` | Copy / file a diagnostic report. |

## AI surface

| Folder | Responsibility |
| --- | --- |
| [`ChatHUD/`](ChatHUD) | The Cribble AI chat panel. |
