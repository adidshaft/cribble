import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsCenter
    @State private var showingAIProviderSheet = false
    @State private var showingDiagnosticsReport = false
    @State private var showingPreviousSessionIssue = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        sceneConfiguredContent
    }

    private var sceneConfiguredContent: some View {
        alertContent
            .focusedSceneValue(\.openFolderAction, { library.chooseFolder(sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.refreshFolderAction, { library.refresh(sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openInEditorAction, { library.openSelectedInEditor(settings: settings) })
            .focusedSceneValue(\.runAILinkingAction, { showingAIProviderSheet = true })
            .focusedSceneValue(\.showDiagnosticsAction, { showingDiagnosticsReport = true })
            .focusedSceneValue(\.copyDiagnosticsAction, { diagnostics.copyReport(library: library, settings: settings) })
            .focusedSceneValue(\.reportIssueAction, { reportIssueOnGitHub() })
            .focusedSceneValue(\.openPullRequestAction, { openPullRequestOnGitHub() })
            .focusedSceneValue(\.navigateBackAction, { library.navigateBack() })
            .focusedSceneValue(\.navigateForwardAction, { library.navigateForward() })
            .focusedSceneValue(\.toggleOutlineAction, { settings.showOutline.toggle() })
            .focusedSceneValue(\.toggleFocusModeAction, { settings.isFocusMode.toggle() })
    }

    private var alertContent: some View {
        sheetContent
            .alert("Cribble", isPresented: errorAlertBinding) {
                Button("Report Issue") {
                    reportIssueOnGitHub()
                    library.errorMessage = nil
                }
                Button("Copy Report") {
                    diagnostics.copyReport(library: library, settings: settings)
                    library.errorMessage = nil
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
            .alert("Cribble did not close cleanly", isPresented: $showingPreviousSessionIssue) {
                Button("Report Issue") {
                    reportIssueOnGitHub()
                    diagnostics.acknowledgePreviousSessionIssue()
                }
                Button("Copy Report") {
                    diagnostics.copyReport(library: library, settings: settings)
                    diagnostics.acknowledgePreviousSessionIssue()
                }
                Button("Not Now", role: .cancel) {
                    diagnostics.acknowledgePreviousSessionIssue()
                }
            } message: {
                Text("Cribble detected that the previous session may have crashed or been force quit. You can send a diagnostic report so it can be fixed.")
            }
    }

    private var sheetContent: some View {
        behaviorContent
            .sheet(isPresented: $showingAIProviderSheet) {
                AIProviderSheet { provider, mode in
                    showingAIProviderSheet = false
                    library.runAILinking(provider: provider, mode: mode)
                }
            }
            .sheet(isPresented: $showingDiagnosticsReport) {
                DiagnosticsReportSheet(
                    report: diagnostics.makeReport(library: library, settings: settings),
                    onCopy: { diagnostics.copyReport(library: library, settings: settings) },
                    onReportIssue: { reportIssueOnGitHub() },
                    onOpenPullRequest: { openPullRequestOnGitHub() }
                )
            }
            .sheet(item: pendingDiffBinding) { item in
                DiffPreviewSheet(diff: item.diff, applyError: library.pendingDiffError) {
                    library.applyPendingDiff()
                } onCancel: {
                    library.cancelPendingDiff()
                }
            }
    }

    private var behaviorContent: some View {
        toolbarContent
            .onChange(of: settings.fileSortMode) { _, newMode in
                library.refresh(sortMode: newMode)
            }
            .onAppear {
                showingPreviousSessionIssue = diagnostics.previousSessionDidNotCloseCleanly
            }
            .onChange(of: diagnostics.previousSessionDidNotCloseCleanly) { _, didNotCloseCleanly in
                showingPreviousSessionIssue = didNotCloseCleanly
            }
    }

    private var toolbarContent: some View {
        content
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search files")
        .onChange(of: settings.isFocusMode, initial: true) {
            let isFocus = settings.isFocusMode
            withAnimation {
                columnVisibility = isFocus ? .detailOnly : .all
            }
        }
        .toolbar {
            navigationToolbar
            primaryToolbar
        }
    }

    private var content: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            ReaderView()
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                library.navigateBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!library.canNavigateBack)
            .cribbleGlassButton()
            .help("Navigate back (Cmd + [)")

            Button {
                library.navigateForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .disabled(!library.canNavigateForward)
            .cribbleGlassButton()
            .help("Navigate forward (Cmd + ])")
        }
    }

    @ToolbarContentBuilder
    private var primaryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            TextSizeMenu()

            OpenInMenu()

            Button {
                settings.isFocusMode.toggle()
            } label: {
                Label("Focus Mode", systemImage: settings.isFocusMode ? "eye.slash.fill" : "eye.slash")
            }
            .cribbleGlassButton(prominent: settings.isFocusMode)
            .help("Toggle Focus Mode (Cmd + Option + F)")

            Button {
                settings.showOutline.toggle()
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .disabled(library.selectedDocument == nil || settings.isFocusMode)
            .cribbleGlassButton(prominent: settings.showOutline && !settings.isFocusMode)
            .help("Toggle Headings Outline (Cmd + Option + O)")

            Button {
                showingAIProviderSheet = true
            } label: {
                Label("AI Link Notes", systemImage: "sparkles")
            }
            .disabled(!library.hasFolders || library.isRunningAI)
            .cribbleGlassButton()
            .help("Ask a local AI tool to suggest wiki links with a patch preview")
        }
    }

    private var pendingDiffBinding: Binding<DiffSheetItem?> {
        Binding(
            get: { library.pendingDiff.map(DiffSheetItem.init(diff:)) },
            set: { item in
                if item == nil {
                    library.cancelPendingDiff()
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    library.errorMessage = nil
                }
            }
        )
    }

    private func reportIssueOnGitHub() {
        let report = diagnostics.makeReport(library: library, settings: settings)
        GitHubReport.openIssue(report: report)
        diagnostics.record(level: .info, message: "Opened GitHub issue flow.")
    }

    private func openPullRequestOnGitHub() {
        let report = diagnostics.makeReport(library: library, settings: settings)
        GitHubReport.openPullRequest(report: report)
        diagnostics.record(level: .info, message: "Opened GitHub pull request flow.")
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
        .cribbleGlassButton()
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
        .cribbleGlassButton()
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
