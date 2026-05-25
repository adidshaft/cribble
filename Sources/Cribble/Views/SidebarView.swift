import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SidebarControls()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

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
        }
        .navigationTitle("Cribble")
        .onChange(of: library.selectedURL) { _, newValue in
            library.select(url: newValue)
        }
    }
}

private struct SidebarControls: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    library.chooseFolder(sortMode: settings.fileSortMode)
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glassProminent)
                .help("Open a Markdown folder and keep it in the sidebar")

                Button {
                    library.refresh(sortMode: settings.fileSortMode)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .disabled(!library.hasFolders)
                .help("Reload the opened Markdown folders")

                Menu {
                    Picker("Sort Files", selection: $settings.fileSortMode) {
                        ForEach(FileSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .disabled(!library.hasFolders)
                .help("Sort files inside folders by name, created date, or updated date")

                Spacer(minLength: 0)
            }
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
