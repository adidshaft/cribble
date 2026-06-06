import SwiftUI
import Textual

/// Renders a run of GFM task-list items as interactive checkboxes — a real
/// tappable checkbox (no list bullet, no literal `[ ]` text), with the item
/// label rendered as inline Markdown. Toggling flips the checkbox in the file
/// (the only write Cribble makes to a note from the reader). Labels are fully
/// highlightable, just like prose.
struct TaskListView: View {
    let items: [TaskListItem]
    let baseURL: URL
    let fontScale: Double
    /// Document-global ordinal of `items[0]`.
    let ordinalBase: Int
    let sectionAnchor: String
    let highlightsByBlock: [BlockKey: [ResolvedHighlight]]
    let onToggle: (_ globalOrdinal: Int, _ currentlyChecked: Bool) -> Void
    let onAddTask: (_ globalOrdinal: Int, _ target: TaskExportTarget?) -> Void
    let onUpdateHighlightNote: (UUID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                let globalOrdinal = ordinalBase + offset
                let blockIndex = HighlightBlockSpace.taskBlockIndex(globalOrdinal: globalOrdinal)
                let highlights = highlightsByBlock[BlockKey(sectionAnchor: sectionAnchor, blockIndex: blockIndex)] ?? []

                TaskRow(
                    item: item,
                    baseURL: baseURL,
                    fontScale: fontScale,
                    sectionAnchor: sectionAnchor,
                    blockIndex: blockIndex,
                    highlights: highlights,
                    onToggle: { currentlyChecked in onToggle(globalOrdinal, currentlyChecked) },
                    onAddTask: { target in onAddTask(globalOrdinal, target) },
                    onUpdateHighlightNote: onUpdateHighlightNote
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TaskRow: View {
    let item: TaskListItem
    let baseURL: URL
    let fontScale: Double
    let sectionAnchor: String
    let blockIndex: Int
    let highlights: [ResolvedHighlight]
    let onToggle: (_ currentlyChecked: Bool) -> Void
    let onAddTask: (_ target: TaskExportTarget?) -> Void
    let onUpdateHighlightNote: (UUID, String) -> Void

    @Environment(\.readerPrimaryFontName) private var primaryFontName
    @Environment(\.readerMonospaceFontName) private var monospaceFontName
    @State private var checked: Bool
    @State private var isHovering = false

    init(
        item: TaskListItem,
        baseURL: URL,
        fontScale: Double,
        sectionAnchor: String,
        blockIndex: Int,
        highlights: [ResolvedHighlight],
        onToggle: @escaping (Bool) -> Void,
        onAddTask: @escaping (TaskExportTarget?) -> Void,
        onUpdateHighlightNote: @escaping (UUID, String) -> Void
    ) {
        self.item = item
        self.baseURL = baseURL
        self.fontScale = fontScale
        self.sectionAnchor = sectionAnchor
        self.blockIndex = blockIndex
        self.highlights = highlights
        self.onToggle = onToggle
        self.onAddTask = onAddTask
        self.onUpdateHighlightNote = onUpdateHighlightNote
        _checked = State(initialValue: item.isChecked)
    }

    private var indentLevel: Int { min(item.indent / 2, 8) }

    private var highlightToken: String {
        highlights
            .map { "\($0.id.uuidString):\($0.note.hashValue)" }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                let wasChecked = checked
                checked.toggle() // optimistic; reconciled by `onChange` after the write
                onToggle(wasChecked)
            } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15 * fontScale))
                    .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .help(checked ? "Mark as not done" : "Mark as done")

            StructuredText(
                item.label.isEmpty ? "\u{200B}" : item.label,
                parser: HighlightedMarkdownParser(baseURL: baseURL, highlights: highlights),
                reparseToken: highlightToken
            )
            .font(ReaderTypography.primary(primaryFontName, size: 17 * fontScale))
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(
                InlineStyle()
                    .code(.font(ReaderTypography.monospace(monospaceFontName, size: 14 * fontScale)))
                    .strong(.fontWeight(.semibold))
            )
            .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
            .textual.textSelection(.enabled)
            .environment(\.textInteractionSectionAnchor, sectionAnchor)
            .environment(\.textInteractionBlockIndex, blockIndex)
            .environment(\.textInteractionBlockSignature, TextInteractionSelectionSnapshot.signature(for: item.label))
            .highlightInteractionOverlay(highlights, onUpdateNote: onUpdateHighlightNote)
            .opacity(checked ? 0.55 : 1)
            .fixedSize(horizontal: false, vertical: true)

            addTaskMenu
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, CGFloat(indentLevel) * 20)
        .onHover { isHovering = $0 }
        .onChange(of: item.isChecked) { _, newValue in
            // Reconcile with the parsed truth after a write/reload (or an
            // external edit) — also reverts the optimistic flip if the write
            // was skipped because the on-disk state had changed.
            checked = newValue
        }
    }

    private var addTaskMenu: some View {
        Menu {
            Button {
                onAddTask(nil)
            } label: {
                Label("Add to Tasks", systemImage: "text.badge.plus")
            }
            Divider()
            ForEach(TaskExportTarget.allCases) { target in
                Button {
                    onAddTask(target)
                } label: {
                    Label(target.label, systemImage: target.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13 * fontScale))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add this task to Tasks, Reminders, or Calendar")
        .pointingHandOnHover()
    }
}
