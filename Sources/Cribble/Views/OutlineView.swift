import SwiftUI

struct OutlineView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if let document = library.selectedDocument, !document.headings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(document.headings, id: \.self) { heading in
                            Button {
                                // Convert heading title to textualSlug matching what Textual uses for IDs
                                library.activeScrollAnchor = heading.title.textualSlug()
                            } label: {
                                Text(heading.title)
                                    .font(.system(size: heading.level == 1 ? 13 : 12))
                                    .fontWeight(heading.level == 1 ? .semibold : .regular)
                                    .foregroundStyle(heading.level == 1 ? .primary : .secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.leading, CGFloat((heading.level - 1) * 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .pointingHandOnHover()
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(library.activeScrollAnchor == heading.title.textualSlug() ? Color.primary.opacity(0.06) : Color.clear)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ContentUnavailableView {
                    Label("No Headings", systemImage: "list.bullet.indent")
                } description: {
                    Text("This document has no markdown headings to show.")
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
    }
}

// Add a helper extension for Textual's slug structure
extension String {
    func textualSlug() -> String {
        String(
            self.lowercased()
                .map { $0.isWhitespace ? "-" : $0 }
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                .split(separator: "-", omittingEmptySubsequences: true)
                .joined(separator: "-")
        )
    }
}
