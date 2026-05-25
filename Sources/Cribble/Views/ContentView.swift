import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                TextSizeMenu()

                Button {
                    library.openSelectedInEditor(settings: settings)
                } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                }
                .disabled(library.selectedDocument == nil)
                .help("Open the selected Markdown file in your configured editor")

                Button {
                    showingAIProviderSheet = true
                } label: {
                    Label("AI Link Notes", systemImage: "sparkles")
                }
                .disabled(!library.hasFolders || library.isRunningAI)
                .buttonStyle(.glass)
                .help("Ask a local AI tool to suggest wiki links with a patch preview")
            }
        }
        .onChange(of: settings.fileSortMode) { _, newMode in
            library.refresh(sortMode: newMode)
        }
        .onAppear {
            AppIconManager.apply(for: colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            AppIconManager.apply(for: newScheme)
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

private struct TextSizeMenu: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Menu {
            Picker("Text Size", selection: Binding(
                get: { ReaderFontSizePreset.closest(to: settings.readerFontScale) },
                set: { settings.setFontSize($0) }
            )) {
                ForEach(ReaderFontSizePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Divider()

            Button("Smaller", systemImage: "textformat.size.smaller") {
                settings.decreaseFontSize()
            }
            Button("Reset", systemImage: "arrow.counterclockwise") {
                settings.resetFontSize()
            }
            Button("Larger", systemImage: "textformat.size.larger") {
                settings.increaseFontSize()
            }
        } label: {
            Label("Text Size", systemImage: "textformat.size")
        }
        .buttonStyle(.glass)
        .help("Change reader text size from XXS to XXL")
    }
}

private struct DiffSheetItem: Identifiable {
    let id = UUID()
    let diff: UnifiedDiff
}
