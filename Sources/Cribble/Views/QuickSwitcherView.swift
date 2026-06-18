import SwiftUI

struct QuickSwitcherView: View {
    let items: [QuickSwitcherItem]
    let onSelect: (QuickSwitcherItem) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var selectedID: QuickSwitcherItem.ID?

    private var results: [QuickSwitcherItem] {
        QuickSwitcherModel.results(query: query, items: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open note", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { openSelection() }
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if results.isEmpty {
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No recent notes" : "No matching notes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            .background {
                                if item.id == selectedID {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(.quaternary)
                                }
                            }
                            .accessibilityLabel("\(item.title), \(item.subtitle)")
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 520)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .onAppear {
            selectedID = results.first?.id
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) {
            selectedID = results.first?.id
        }
        .onExitCommand(perform: onDismiss)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick switcher")
    }

    private func row(_ item: QuickSwitcherItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.recencyRank != nil {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func openSelection() {
        guard let selectedID,
              let item = results.first(where: { $0.id == selectedID }) ?? results.first else {
            return
        }
        onSelect(item)
    }
}
