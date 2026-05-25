import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SidebarControls()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if library.filteredNodes.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView("No Markdown Files", systemImage: "doc.text.magnifyingglass")
                        .padding(.vertical, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(library.filteredNodes, children: \.childNodes, selection: $library.selectedURL) { node in
                    SidebarRow(node: node)
                        .tag(Optional(node.url))
                        .contextMenu {
                            if library.isImportedRoot(node.url) {
                                Button("Remove Folder", systemImage: "folder.badge.minus", role: .destructive) {
                                    library.removeFolder(node.url)
                                }
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

                Button {
                    library.removeSelectedFolder()
                } label: {
                    Label("Remove Folder", systemImage: "folder.badge.minus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .disabled(library.selectedRootURL == nil)
                .help("Remove the selected folder from Cribble without deleting files")

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
