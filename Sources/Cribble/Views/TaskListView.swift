import SwiftUI
import Textual

/// Renders a run of GFM task-list items as interactive checkboxes — a real
/// tappable checkbox (no list bullet, no literal `[ ]` text), with the item
/// label rendered as inline Markdown. Toggling flips the checkbox in the file
/// (the only write Cribble makes to a note from the reader).
struct TaskListView: View {
    let items: [TaskListItem]
    let baseURL: URL
    let fontScale: Double
    /// Document-global ordinal of `items[0]`.
    let ordinalBase: Int
    let onToggle: (_ globalOrdinal: Int, _ currentlyChecked: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                TaskRow(
                    item: item,
                    baseURL: baseURL,
                    fontScale: fontScale
                ) { currentlyChecked in
                    onToggle(ordinalBase + offset, currentlyChecked)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TaskRow: View {
    let item: TaskListItem
    let baseURL: URL
    let fontScale: Double
    let onToggle: (_ currentlyChecked: Bool) -> Void

    @State private var checked: Bool

    init(item: TaskListItem, baseURL: URL, fontScale: Double, onToggle: @escaping (Bool) -> Void) {
        self.item = item
        self.baseURL = baseURL
        self.fontScale = fontScale
        self.onToggle = onToggle
        _checked = State(initialValue: item.isChecked)
    }

    private var indentLevel: Int { min(item.indent / 2, 8) }

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
                parser: HighlightedMarkdownParser(baseURL: baseURL, highlights: [])
            )
            .font(.system(size: 17 * fontScale))
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(
                InlineStyle()
                    .code(.font(.system(size: 14 * fontScale, design: .monospaced)))
                    .strong(.fontWeight(.semibold))
            )
            .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
            .textual.textSelection(.enabled)
            .opacity(checked ? 0.55 : 1)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indentLevel) * 20)
        .onChange(of: item.isChecked) { _, newValue in
            // Reconcile with the parsed truth after a write/reload (or an
            // external edit) — also reverts the optimistic flip if the write
            // was skipped because the on-disk state had changed.
            checked = newValue
        }
    }
}
