import SwiftUI

enum RelatedNotesSectionModel {
    static func scoreFraction(_ score: Double) -> Double {
        min(1, max(0, (score - 0.16) / 0.84))
    }
}

struct RelatedNotesSection: View {
    let hits: [SemanticHit]
    let onSelect: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

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

                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)

                    Text("Related Notes")
                        .font(.subheadline.weight(.semibold))

                    Text("\(hits.count)")
                        .font(.caption2.monospaced())
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
            .accessibilityLabel("Related Notes, \(hits.count) notes")
            .help(isExpanded ? "Collapse related notes" : "Expand related notes")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(hits) { hit in
                        Button {
                            onSelect(hit.url)
                        } label: {
                            RelatedNoteRow(hit: hit)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .pointingHandOnHover()
                        .notePreviewPopover(url: hit.url)
                        .help("Open \(hit.title)")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: hit))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 10))
    }

    private func accessibilityLabel(for hit: SemanticHit) -> String {
        "\(hit.title), related note, \(Int((hit.score * 100).rounded())) percent similarity"
    }
}

private struct RelatedNoteRow: View {
    let hit: SemanticHit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: 18)

                Text(hit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int((hit.score * 100).rounded()))%")
                    .font(.caption2.monospaced())
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(.primary.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.55))
                            .frame(width: proxy.size.width * RelatedNotesSectionModel.scoreFraction(hit.score))
                    }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
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
