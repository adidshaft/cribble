import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore

    var body: some View {
        List(selection: $library.selectedURL) {
            if library.filteredNodes.isEmpty {
                ContentUnavailableView("No Markdown Files", systemImage: "doc.text.magnifyingglass")
                    .padding(.vertical, 24)
            } else {
                ForEach(library.filteredNodes) { node in
                    SidebarNodeView(node: node)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cribble")
        .onChange(of: library.selectedURL) { _, newValue in
            library.select(url: newValue)
        }
    }
}

private struct SidebarNodeView: View {
    let node: MarkdownNode

    var body: some View {
        switch node.kind {
        case .folder:
            DisclosureGroup {
                ForEach(node.children) { child in
                    SidebarNodeView(node: child)
                }
            } label: {
                SidebarRow(node: node)
            }
            .tag(Optional(node.url))
        case .markdown:
            SidebarRow(node: node)
                .tag(Optional(node.url))
        }
    }
}

private struct SidebarRow: View {
    let node: MarkdownNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: node.kind == .folder ? "folder" : "doc.text")
                .foregroundStyle(.secondary)
        }
    }
}
