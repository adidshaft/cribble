import SwiftUI

struct TagPaneView: View {
    let tags: [TagIndex.Tag]
    let selectedTag: TagIndex.Tag?
    let onSelect: (TagIndex.Tag) -> Void
    let onClear: () -> Void

    private let visibleLimit = 24

    private var visibleTags: [TagIndex.Tag] {
        Array(tags.prefix(visibleLimit))
    }

    var body: some View {
        if !visibleTags.isEmpty || selectedTag != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Tags", systemImage: "tag")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if selectedTag != nil {
                        Button(action: onClear) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear tag filter")
                        .accessibilityLabel("Clear tag filter")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(visibleTags, id: \.normalized) { tag in
                            tagButton(tag)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func tagButton(_ tag: TagIndex.Tag) -> some View {
        let isSelected = selectedTag?.normalized == tag.normalized
        return Button {
            onSelect(tag)
        } label: {
            HStack(spacing: 5) {
                Text("#\(tag.name)")
                    .lineLimit(1)
                Text("\(tag.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(tag.count) note\(tag.count == 1 ? "" : "s") tagged #\(tag.name)")
        .accessibilityLabel("Tag \(tag.name), \(tag.count) note\(tag.count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
