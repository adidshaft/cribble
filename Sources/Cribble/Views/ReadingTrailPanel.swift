import SwiftUI

/// A minimalist vertical tree of the active reading trail. Rows are tappable to
/// jump back to a note; a footer action synthesizes the whole trail into a new
/// Markdown note (previewed as a safe unified diff before anything is written).
struct ReadingTrailPanel: View {
    @EnvironmentObject private var trail: ReadingTrailStore
    @EnvironmentObject private var annotations: ReadingAnnotationsStore
    @EnvironmentObject private var library: MarkdownLibraryStore

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)

            if trail.isEmpty {
                emptyState
            } else {
                trailList
                Divider().opacity(0.4)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Reading Trail")
                .font(.system(size: 13, design: .rounded))
                .fontWeight(.semibold)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .help("Close (P)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "signpost.right.and.left")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No trail yet")
                .font(.system(size: 13, weight: .medium))
            Text("Open notes and follow wiki links — your path appears here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var trailList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(trail.orderedNodes) { node in
                    TrailRow(
                        node: node,
                        isCurrent: node.id == trail.currentNodeID,
                        seconds: trail.seconds(for: node),
                        highlightCount: annotations.highlights(for: node.url).count
                    ) {
                        library.select(url: node.url)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                createTrailNote()
            } label: {
                Label("Create Trail Note", systemImage: "doc.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .cribbleGlassButton(prominent: true)
            .help("Synthesize this trail into a new Markdown note (with a diff preview)")

            Button(role: .destructive) {
                trail.clear()
            } label: {
                Text("Clear Trail")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pointingHandOnHover()
        }
        .padding(12)
    }

    private func createTrailNote() {
        guard let note = trail.makeTrailNote(annotations: annotations) else { return }
        library.presentNewNoteProposal(fileName: note.fileName, content: note.content)
    }
}

private struct TrailRow: View {
    let node: ReadingTrailNode
    let isCurrent: Bool
    let seconds: TimeInterval
    let highlightCount: Int
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Depth connector + node dot.
                HStack(spacing: 0) {
                    if node.depth > 0 {
                        Color.clear.frame(width: CGFloat(node.depth) * 12)
                    }
                    Circle()
                        .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(ReadingTrailStore.format(seconds: seconds))
                        if highlightCount > 0 {
                            Label("\(highlightCount)", systemImage: "highlighter")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isCurrent ? Color.accentColor.opacity(0.12) : (isHovering ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .onHover { isHovering = $0 }
    }
}
