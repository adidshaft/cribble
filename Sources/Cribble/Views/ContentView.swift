import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsCenter
    @State private var showingAIProviderSheet = false
    @State private var showingDiagnosticsReport = false

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

                OpenInMenu()

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
        .sheet(isPresented: $showingAIProviderSheet) {
            AIProviderSheet { provider, mode in
                showingAIProviderSheet = false
                library.runAILinking(provider: provider, mode: mode)
            }
        }
        .sheet(isPresented: $showingDiagnosticsReport) {
            DiagnosticsReportSheet(
                report: diagnostics.makeReport(library: library, settings: settings),
                onCopy: { diagnostics.copyReport(library: library, settings: settings) }
            )
        }
        .sheet(item: Binding(
            get: { library.pendingDiff.map(DiffSheetItem.init(diff:)) },
            set: { if $0 == nil { library.cancelPendingDiff() } }
        )) { item in
            DiffPreviewSheet(diff: item.diff, applyError: library.pendingDiffError) {
                library.applyPendingDiff()
            } onCancel: {
                library.cancelPendingDiff()
            }
        }
        .alert("Cribble", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("Copy Report") {
                diagnostics.copyReport(library: library, settings: settings)
                library.errorMessage = nil
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .focusedSceneValue(\.openFolderAction, { library.chooseFolder(sortMode: settings.fileSortMode) })
        .focusedSceneValue(\.refreshFolderAction, { library.refresh(sortMode: settings.fileSortMode) })
        .focusedSceneValue(\.openInEditorAction, { library.openSelectedInEditor(settings: settings) })
        .focusedSceneValue(\.runAILinkingAction, { showingAIProviderSheet = true })
        .focusedSceneValue(\.showDiagnosticsAction, { showingDiagnosticsReport = true })
        .focusedSceneValue(\.copyDiagnosticsAction, { diagnostics.copyReport(library: library, settings: settings) })
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

private struct OpenInMenu: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Menu {
            Button {
                library.openSelectedDocumentWithDefaultApp()
            } label: {
                Label("Default app", systemImage: "app")
            }

            ForEach(editorApplications) { app in
                Button {
                    library.openSelectedDocument(with: app.url)
                } label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                }
            }

            Divider()

            Button {
                library.revealSelectedDocumentInFinder()
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
        } label: {
            Label("Open in", systemImage: "square.and.pencil")
        }
        .buttonStyle(.glass)
        .disabled(library.selectedDocument == nil)
        .help("Open the selected Markdown file in another app or reveal it in Finder")
    }

    private var editorApplications: [EditorApplication] {
        guard library.selectedDocument != nil else { return [] }

        var urls: [URL] = []
        if let configuredURL = settings.editorApplicationURL {
            urls.append(configuredURL)
        }

        urls.append(contentsOf: CommonEditorApplication.installedURLs())

        return urls
            .map(\.standardizedFileURL)
            .uniqued()
            .map(EditorApplication.init(url:))
            .sorted { lhs, rhs in
                lhs.rank < rhs.rank || (lhs.rank == rhs.rank && lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending)
            }
    }
}

private struct EditorApplication: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let icon: NSImage
    let rank: Int

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.rank = CommonEditorApplication.rank(for: url)
    }
}

private enum CommonEditorApplication {
    static func installedURLs() -> [URL] {
        commonBundleIdentifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    static func rank(for url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains("visual studio code") || name == "code" { return 0 }
        if name.contains("cursor") { return 1 }
        if name.contains("obsidian") { return 2 }
        if name.contains("typora") { return 3 }
        if name.contains("marked") { return 4 }
        if name.contains("macdown") { return 5 }
        if name.contains("zed") { return 6 }
        if name.contains("sublime") { return 7 }
        if name.contains("textmate") { return 8 }
        if name.contains("nova") { return 9 }
        if name.contains("textedit") { return 10 }
        if name.contains("xcode") { return 11 }
        return 10
    }

    private static let commonBundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.cursor.Cursor",
        "md.obsidian",
        "abnerworks.Typora",
        "com.brettterpstra.marked2",
        "com.uranusjr.macdown",
        "dev.zed.Zed",
        "com.apple.TextEdit",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.Nova",
        "com.macromates.TextMate"
    ]
}

private struct DiffSheetItem: Identifiable {
    let diff: UnifiedDiff

    var id: String {
        diff.files.map(\.newPath).joined(separator: "\u{1f}")
    }
}
