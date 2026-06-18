import SwiftUI

struct LinkedMentionsSection: View {
    let backlinks: [Backlink]
    let onSelect: (Backlink) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var mentionCount: Int {
        backlinks.reduce(0) { $0 + $1.occurrences.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let update = { isExpanded.toggle() }
                if reduceMotion {
                    update()
                } else {
                    withAnimation(.snappy(duration: 0.18)) {
                        update()
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "arrow.turn.down.left")
                        .foregroundStyle(.secondary)

                    Text("Linked Mentions")
                        .font(.system(size: 14))
                        .fontWeight(.semibold)

                    Text("\(mentionCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.06), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
                        }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Linked Mentions, \(mentionCount) mentions")
            .help(isExpanded ? "Collapse linked mentions" : "Expand linked mentions")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(backlinks) { backlink in
                        Button {
                            onSelect(backlink)
                        } label: {
                            LinkedMentionRow(backlink: backlink)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .pointingHandOnHover()
                        .notePreviewPopover(url: backlink.sourceURL)
                        .help("Open \(backlink.sourceTitle)")
                        .accessibilityLabel("\(backlink.sourceTitle), \(backlink.occurrences.count) linked mentions")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LinkedMentionRow: View {
    let backlink: Backlink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 18)

                Text(backlink.sourceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(backlink.occurrences.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            ForEach(backlink.occurrences.prefix(2)) { occurrence in
                Text(occurrence.snippet.isEmpty ? occurrence.linkLabel : occurrence.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.045))
        }
    }
}
