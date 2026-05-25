import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAIProviderSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            ReaderView()
        }
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search files")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    library.chooseFolder(sortMode: settings.fileSortMode)
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    library.refresh(sortMode: settings.fileSortMode)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!library.hasFolders)

                Menu {
                    Picker("Sort Files", selection: $settings.fileSortMode) {
                        ForEach(FileSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Label("Sort Files", systemImage: "arrow.up.arrow.down")
                }
                .disabled(!library.hasFolders)

                Menu {
                    Button("Smaller", systemImage: "textformat.size.smaller") {
                        settings.decreaseFontSize()
                    }
                    Button("Larger", systemImage: "textformat.size.larger") {
                        settings.increaseFontSize()
                    }
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        settings.resetFontSize()
                    }
                } label: {
                    Label("Text Size", systemImage: "textformat.size")
                }

                Button {
                    library.openSelectedInEditor(settings: settings)
                } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                }
                .disabled(library.selectedDocument == nil)

                Button {
                    showingAIProviderSheet = true
                } label: {
                    Label("AI Link Notes", systemImage: "sparkles")
                }
                .disabled(!library.hasFolders || library.isRunningAI)
            }
        }
        .onChange(of: settings.fileSortMode) { _, newMode in
            library.refresh(sortMode: newMode)
        }
        .sheet(isPresented: $showingAIProviderSheet) {
            AIProviderSheet { provider in
                showingAIProviderSheet = false
                library.runAILinking(provider: provider)
            }
        }
        .sheet(item: Binding(
            get: { library.pendingDiff.map(DiffSheetItem.init(diff:)) },
            set: { if $0 == nil { library.cancelPendingDiff() } }
        )) { item in
            DiffPreviewSheet(diff: item.diff) {
                library.applyPendingDiff()
            } onCancel: {
                library.cancelPendingDiff()
            }
        }
        .alert("Cribble", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .focusedSceneValue(\.openFolderAction, { library.chooseFolder(sortMode: settings.fileSortMode) })
        .focusedSceneValue(\.refreshFolderAction, { library.refresh(sortMode: settings.fileSortMode) })
        .focusedSceneValue(\.openInEditorAction, { library.openSelectedInEditor(settings: settings) })
        .focusedSceneValue(\.runAILinkingAction, { showingAIProviderSheet = true })
    }
}

private struct DiffSheetItem: Identifiable {
    let id = UUID()
    let diff: UnifiedDiff
}
