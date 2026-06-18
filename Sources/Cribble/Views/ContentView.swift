import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsCenter
    @EnvironmentObject private var semanticIndex: SemanticSearchIndex
    @EnvironmentObject private var llmEntitlement: LLMEntitlementStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @EnvironmentObject private var extensionRegistry: ExtensionRegistry
    @State private var showingAIProviderSheet = false
    @State private var showingLLMUnlockSheet = false
    @State private var showingDiagnosticsReport = false
    @State private var showingImportGuidance = false
    @State private var showingQuickSwitcher = false
    @State private var showingCommandPalette = false
    @State private var importGuidanceStatus: String?
    @State private var showingPreviousSessionIssue = false
    @State private var pendingRestoreRunnerConsent: ExtensionRunnerConsentRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isSearchFocused: Bool
    /// True when the window is too narrow for a side-by-side sidebar; the
    /// sidebar then becomes an on-demand overlay instead of a column.
    @State private var isCompactWidth = false
    /// Whether the overlay sidebar is showing in compact mode.
    @State private var showCompactSidebar = false

    /// Below this content width the sidebar collapses into an overlay.
    private static let compactWidthThreshold: CGFloat = 640

    var body: some View {
        sceneConfiguredContent
    }

    private var sceneConfiguredContent: some View {
        focusedHelpActions(
            focusedNavigationActions(
                focusedDiagnosticsActions(
                    focusedPrimaryActions(alertContent)
                )
            )
        )
        .onAppear(perform: configureControllers)
    }

    private func focusedPrimaryActions<Content: View>(_ content: Content) -> some View {
        content
            .focusedSceneValue(\.newNoteAction, newNoteAction)
            .focusedSceneValue(\.openTodayNoteAction, openTodayNoteAction)
            .focusedSceneValue(\.openFolderAction, { library.chooseFolder(sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.importFileAction, importFileAction)
            .focusedSceneValue(\.refreshFolderAction, { library.refresh(sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openTasksAction, openTasksAction)
            .focusedSceneValue(\.openInEditorAction, { library.openSelectedInEditor(settings: settings) })
            .focusedSceneValue(\.revealSelectedDocumentAction, selectedDocumentAction(library.revealSelectedDocumentInFinder))
            .focusedSceneValue(\.copySelectedDocumentPathAction, selectedDocumentAction(library.copySelectedDocumentPath))
            .focusedSceneValue(\.copySelectedDocumentMarkdownAction, selectedDocumentAction(library.copySelectedDocumentMarkdown))
            .focusedSceneValue(\.copySelectedDocumentMarkdownLinkAction, selectedDocumentAction(library.copySelectedDocumentMarkdownLink))
            .focusedSceneValue(\.copySelectedDocumentWikiLinkAction, selectedDocumentAction(library.copySelectedDocumentWikiLink))
            .focusedSceneValue(\.undoNoteChangeAction, { library.undoLastChangeToSelectedNote() })
            .focusedSceneValue(\.runAILinkingAction, { showingAIProviderSheet = true })
            .focusedSceneValue(\.summarizeWithAIAction, summarizeWithAIAction)
            .focusedSceneValue(\.explainSimplyWithAIAction, explainSimplyWithAIAction)
            .focusedSceneValue(\.findRelatedWithAIAction, findRelatedWithAIAction)
            .focusedSceneValue(\.createIndexWithAIAction, createIndexWithAIAction)
            .focusedSceneValue(\.draftTodayWithAIAction, draftTodayWithAIAction)
            .focusedSceneValue(\.extractTasksWithAIAction, extractTasksWithAIAction)
            .focusedSceneValue(\.toggleChatHUDAction, { openChatHUD() })
            .focusedSceneValue(\.toggleIntelligenceHUDAction, { openIntelligenceHUD() })
    }

    private func focusedDiagnosticsActions<Content: View>(_ content: Content) -> some View {
        content
            .focusedSceneValue(\.showDiagnosticsAction, { showingDiagnosticsReport = true })
            .focusedSceneValue(\.copyDiagnosticsAction, {
                diagnostics.copyReport(
                    library: library,
                    settings: settings,
                    intelligence: intelligenceDiagnostics,
                    extensions: extensionDiagnostics
                )
            })
            .focusedSceneValue(\.revealCrashReportAction, { _ = diagnostics.revealLatestCrashReportInFinder() })
            .focusedSceneValue(\.reportIssueAction, { reportIssueOnGitHub() })
            .focusedSceneValue(\.openPullRequestAction, { openPullRequestOnGitHub() })
    }

    private func focusedNavigationActions<Content: View>(_ content: Content) -> some View {
        content
            .focusedSceneValue(\.navigateBackAction, navigateBackAction)
            .focusedSceneValue(\.navigateForwardAction, navigateForwardAction)
            .focusedSceneValue(\.toggleOutlineAction, { settings.showOutline.toggle() })
            .focusedSceneValue(\.toggleFocusModeAction, { settings.isFocusMode.toggle() })
            .focusedSceneValue(\.openQuickSwitcherAction, { showingQuickSwitcher = true })
            .focusedSceneValue(\.openCommandPaletteAction, { showingCommandPalette = true })
            .focusedSceneValue(\.focusSearchAction, {
                isSearchFocused = true
            })
            .focusedSceneValue(\.clearSearchAction, clearSearchAction)
    }

    private func focusedHelpActions<Content: View>(_ content: Content) -> some View {
        focusedTemplateHelpActions(
            focusedGuideHelpActions(content)
                .focusedSceneValue(\.openExtensionSettingsAction, openSettingsWindow)
        )
            .focusedSceneValue(\.resetDemoNotesAction, { library.openDemoLibrary(sortMode: settings.fileSortMode, reset: true) })
    }

    private func focusedGuideHelpActions<Content: View>(_ content: Content) -> some View {
        content
            .focusedSceneValue(\.openDemoNotesAction, { library.openDemoLibrary(sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openCribbleAIGuideAction, { library.openDemoNote(named: "Cribble AI.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openWorkflowPlaybookAction, { library.openDemoNote(named: "Workflow Playbook.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openTasksGuideAction, { library.openDemoNote(named: "Tasks and Intelligence.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openResearchReviewAction, { library.openDemoNote(named: "Research Review.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openDecisionLogGuideAction, { library.openDemoNote(named: "Decision Log.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openTeamExtensionKitAction, { library.openDemoNote(named: "Team Extension Kit.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openExtensionContributionGuideAction, { library.openDemoNote(named: "Extension Contribution Guide.md", sortMode: settings.fileSortMode) })
            .focusedSceneValue(\.openRemoteIntelligenceGuideAction, { library.openDemoNote(named: "Extensions and Remote Intelligence.md", sortMode: settings.fileSortMode) })
    }

    private func focusedTemplateHelpActions<Content: View>(_ content: Content) -> some View {
        content
            .focusedSceneValue(\.copyExtensionProposalAction, copyExtensionProposal)
            .focusedSceneValue(\.copyDecisionEntryTemplateAction, copyDecisionEntryTemplate)
            .focusedSceneValue(\.copyResearchReviewTemplateAction, copyResearchReviewTemplate)
            .focusedSceneValue(\.copyRemoteRunnerSetupReviewAction, copyRemoteRunnerSetupReview)
            .focusedSceneValue(\.copyImportLaneSetupReviewAction, copyImportLaneSetupReview)
            .focusedSceneValue(\.copyProductReadinessCheckpointAction, copyProductReadinessCheckpoint)
            .focusedSceneValue(\.copyStarterChecklistAction, copyStarterChecklist)
    }

    private func copyExtensionProposal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ExtensionProposalTemplate.markdown, forType: .string)
        library.statusMessage = "Copied extension proposal template"
    }

    private func copyDecisionEntryTemplate() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DecisionLogTemplate.markdown, forType: .string)
        library.statusMessage = "Copied decision entry template"
    }

    private func copyResearchReviewTemplate() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ResearchReviewTemplate.markdown, forType: .string)
        library.statusMessage = "Copied research review template"
    }

    private func copyRemoteRunnerSetupReview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(RemoteRunnerSetupReview.markdown, forType: .string)
        library.statusMessage = "Copied remote runner setup review"
    }

    private func copyImportLaneSetupReview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ImportLaneSetupReview.markdown, forType: .string)
        library.statusMessage = "Copied import lane setup review"
    }

    private func copyProductReadinessCheckpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ProductReadinessCheckpointTemplate.markdown, forType: .string)
        library.statusMessage = "Copied product readiness checkpoint"
    }

    private func copyStarterChecklist() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WelcomeStarterChecklist.markdown, forType: .string)
        library.statusMessage = "Copied starter checklist"
    }

    private func configureControllers() {
        ChatHUDController.shared.configure(
            library: library,
            semanticIndex: semanticIndex,
            entitlement: llmEntitlement,
            intelligence: intelligence,
            extensionRegistry: extensionRegistry,
            onLocked: { showingLLMUnlockSheet = true }
        )
        IntelligenceHUDController.shared.configure(
            engine: intelligence,
            library: library,
            entitlement: llmEntitlement,
            extensionRegistry: extensionRegistry,
            onLocked: { showingLLMUnlockSheet = true }
        )
        extensionRegistry.reload(projectRoots: library.rootURLs)
        if let root = library.activeRootURL {
            restoreIntelligenceAfterConsent(root: root)
        }
    }

    private var importFileAction: (() -> Void)? {
        { openImportFlow() }
    }

    private func openImportFlow() {
        let capabilities = extensionRegistry.importerCapabilities
        if capabilities.isEmpty {
            importGuidanceStatus = nil
            showingImportGuidance = true
        } else {
            library.chooseImportFile(capabilities: capabilities)
        }
    }

    private func selectedDocumentAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        guard library.selectedDocument != nil else { return nil }
        return action
    }

    private var navigateBackAction: (() -> Void)? {
        library.canNavigateBack ? { library.navigateBack() } : nil
    }

    private var navigateForwardAction: (() -> Void)? {
        library.canNavigateForward ? { library.navigateForward() } : nil
    }

    private var clearSearchAction: (() -> Void)? {
        guard !library.searchText.isEmpty else { return nil }
        return {
            library.searchText = ""
            isSearchFocused = false
        }
    }

    private var openTasksAction: (() -> Void)? {
        library.hasFolders ? { library.openTasksFile() } : nil
    }

    private var newNoteAction: (() -> Void)? {
        library.hasFolders ? { library.proposeBlankNote() } : nil
    }

    private var openTodayNoteAction: (() -> Void)? {
        library.hasFolders ? { library.openTodayNote() } : nil
    }

    private var draftTodayWithAIAction: (() -> Void)? {
        library.hasFolders ? { ChatHUDController.shared.runBuiltInQuickAction(id: "today-note") } : nil
    }

    private var summarizeWithAIAction: (() -> Void)? {
        guard library.selectedDocument != nil else { return nil }
        return {
            ChatHUDController.shared.runBuiltInQuickAction(id: "summarize")
        }
    }

    private var explainSimplyWithAIAction: (() -> Void)? {
        guard library.selectedDocument != nil else { return nil }
        return {
            ChatHUDController.shared.runBuiltInQuickAction(id: "simplify")
        }
    }

    private var findRelatedWithAIAction: (() -> Void)? {
        guard library.selectedDocument != nil else { return nil }
        return {
            ChatHUDController.shared.runBuiltInQuickAction(id: "related")
        }
    }

    private var createIndexWithAIAction: (() -> Void)? {
        library.hasFolders ? { ChatHUDController.shared.runBuiltInQuickAction(id: "index") } : nil
    }

    private var extractTasksWithAIAction: (() -> Void)? {
        guard library.selectedDocument != nil else { return nil }
        return {
            ChatHUDController.shared.runBuiltInQuickAction(id: "extract-tasks")
        }
    }

    private var alertContent: some View {
        sheetContent
            .alert("Cribble", isPresented: errorAlertBinding) {
                Button("Report Issue") {
                    reportIssueOnGitHub()
                    library.errorMessage = nil
                }
                Button("Copy Report") {
                    diagnostics.copyReport(
                        library: library,
                        settings: settings,
                        intelligence: intelligenceDiagnostics,
                        extensions: extensionDiagnostics
                    )
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
                    diagnostics.copyReport(
                        library: library,
                        settings: settings,
                        intelligence: intelligenceDiagnostics,
                        extensions: extensionDiagnostics
                    )
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
                    report: diagnostics.makeReport(
                        library: library,
                        settings: settings,
                        intelligence: intelligenceDiagnostics,
                        extensions: extensionDiagnostics
                    ),
                    crashReport: diagnostics.latestCrashReport,
                    latestRefreshSnapshot: diagnostics.latestRefreshSnapshot,
                    nextActions: [
                        intelligenceDiagnostics.nextActionSummary,
                        extensionDiagnostics.nextActionSummary
                    ],
                    onCopy: {
                        diagnostics.copyReport(
                            library: library,
                            settings: settings,
                            intelligence: intelligenceDiagnostics,
                            extensions: extensionDiagnostics
                        )
                    },
                    onCopyCrashReport: { diagnostics.copyLatestCrashReport() },
                    onRevealCrashReport: { diagnostics.revealLatestCrashReportInFinder() },
                    onReportIssue: { reportIssueOnGitHub() },
                    onOpenPullRequest: { openPullRequestOnGitHub() }
                )
            }
            .sheet(isPresented: $showingImportGuidance) {
                ImportGuidanceSheet(
                    canCreateProjectExample: library.activeRootURL != nil,
                    status: importGuidanceStatus,
                    onCreateProjectExample: createProjectImportLane,
                    onCreateUserExample: createUserImportLane,
                    onOpenSettings: openSettingsWindow,
                    onOpenTeamKit: {
                        showingImportGuidance = false
                        library.openDemoNote(named: "Team Extension Kit.md", sortMode: settings.fileSortMode)
                    },
                    onOpenContributionGuide: {
                        showingImportGuidance = false
                        library.openDemoNote(named: "Extension Contribution Guide.md", sortMode: settings.fileSortMode)
                    }
                )
            }
            .sheet(item: pendingDiffBinding) { item in
                DiffPreviewSheet(diff: item.diff, applyError: library.pendingDiffError) {
                    library.applyPendingDiff()
                } onCancel: {
                    library.cancelPendingDiff()
                }
            }
            .sheet(item: $library.pathfinderRequest) { request in
                PathfinderSheet(request: request)
            }
            .sheet(isPresented: $showingLLMUnlockSheet) {
                LLMUnlockSheet(entitlement: llmEntitlement)
            }
            .sheet(item: $pendingRestoreRunnerConsent) { request in
                ExtensionRunnerConsentSheet(
                    profile: request.profile,
                    usesKeychain: intelligence.settings.runnerUsesKeychain(baseURL: request.profile.baseURL.absoluteString),
                    onCancel: { pendingRestoreRunnerConsent = nil },
                    onApprove: {
                        ExtensionRunnerConsentStore().approve(request.profile)
                        pendingRestoreRunnerConsent = nil
                        restoreIntelligenceAfterConsent(root: request.url)
                    }
                )
            }
    }

    /// Toggles the floating Local Chat HUD. The controller honors the purchase
    /// gate (App Store build only — the DMG build is always unlocked).
    private func openChatHUD() {
        ChatHUDController.shared.toggleFloating()
    }

    /// Toggles the floating Intelligence HUD (project-intelligence cockpit).
    private func openIntelligenceHUD() {
        IntelligenceHUDController.shared.toggle()
    }

    private var behaviorContent: some View {
        toolbarContent
            .onChange(of: settings.fileSortMode) { _, newMode in
                library.refresh(sortMode: newMode)
            }
            .onChange(of: settings.loadRemoteImages) {
                library.rerenderSelectedDocument()
            }
            .onAppear {
                showingPreviousSessionIssue = diagnostics.previousSessionDidNotCloseCleanly
            }
            .onChange(of: diagnostics.previousSessionDidNotCloseCleanly) { _, didNotCloseCleanly in
                showingPreviousSessionIssue = didNotCloseCleanly
            }
            // `nodes` and `documents` are set together after a scan, so reacting
            // to the published `nodes` keeps the semantic index in sync. Cheap
            // when nothing changed (unchanged files are skipped by hash).
            .onChange(of: library.nodes, initial: true) {
                semanticIndex.reindex(documents: library.documents)
            }
    }

    private var toolbarContent: some View {
        content
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search files")
        .searchFocused($isSearchFocused)
        .simultaneousGesture(TapGesture().onEnded {
            isSearchFocused = false
        })
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

    private var readerShortcutActions: ReaderView.ShortcutActions {
        ReaderView.ShortcutActions(
            navigateBack: navigateBackAction,
            navigateForward: navigateForwardAction,
            focusSearch: { isSearchFocused = true },
            toggleOutline: { settings.showOutline.toggle() },
            toggleIntelligence: { openIntelligenceHUD() },
            toggleChat: { openChatHUD() },
            newNote: newNoteAction,
            openTasks: openTasksAction,
            openInEditor: selectedDocumentAction { library.openSelectedInEditor(settings: settings) },
            runAILinking: library.hasFolders && !library.isRunningAI ? { showingAIProviderSheet = true } : nil,
            revealInFinder: selectedDocumentAction(library.revealSelectedDocumentInFinder)
        )
    }

    private var content: some View {
        GeometryReader { proxy in
            Group {
                if isCompactWidth {
                    compactLayout
                } else {
                    splitLayout
                }
            }
            .onChange(of: proxy.size.width, initial: true) { _, width in
                DispatchQueue.main.async {
                    updateCompactState(for: width)
                }
            }
        }
        .overlay {
            if showingQuickSwitcher || showingCommandPalette {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { dismissOverlays() }
            }

            if showingQuickSwitcher {
                QuickSwitcherView(
                    items: quickSwitcherItems,
                    onSelect: { item in
                        library.select(url: item.url)
                        dismissQuickSwitcher()
                    },
                    onDismiss: dismissQuickSwitcher
                )
                .padding()
            }

            if showingCommandPalette {
                CommandPaletteView(
                    commands: commandPaletteCommands,
                    onDismiss: dismissCommandPalette
                )
                .padding()
            }
        }
        // Selecting a note in the overlay sidebar dismisses it.
        .onChange(of: library.selectedURL) {
            if isCompactWidth, showCompactSidebar {
                withAnimation(.easeInOut(duration: 0.2)) { showCompactSidebar = false }
            }
        }
    }

    private var quickSwitcherItems: [QuickSwitcherItem] {
        QuickSwitcherModel.items(
            documents: library.documents,
            recentURLs: library.history,
            relativePath: { library.relativePath(for: $0) }
        )
    }

    private func dismissQuickSwitcher() {
        withAnimation(.snappy(duration: 0.16)) {
            showingQuickSwitcher = false
        }
    }

    private func dismissCommandPalette() {
        withAnimation(.snappy(duration: 0.16)) {
            showingCommandPalette = false
        }
    }

    private func dismissOverlays() {
        withAnimation(.snappy(duration: 0.16)) {
            showingQuickSwitcher = false
            showingCommandPalette = false
        }
    }

    private var commandPaletteCommands: [PaletteCommand] {
        [
            paletteCommand(id: "new-note", title: "New Note", subtitle: "Create a note in the current folder", keywords: ["file", "create"], action: newNoteAction),
            paletteCommand(id: "open-today", title: "Open Today Note", subtitle: "Jump to today's daily note", shortcut: "⌘N", keywords: ["daily", "today"], action: openTodayNoteAction),
            paletteCommand(id: "open-folder", title: "Open Folder", subtitle: "Choose a Markdown folder", keywords: ["vault", "library"]) {
                library.chooseFolder(sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "import", title: "Import", subtitle: "Import a folder or supported file", shortcut: "⌘I", keywords: ["folder", "file"], action: importFileAction),
            paletteCommand(id: "refresh", title: "Refresh", subtitle: "Rescan open folders", keywords: ["reload", "folder"]) {
                library.refresh(sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "open-tasks", title: "Open Tasks", subtitle: "Open the project task note", keywords: ["todo"], action: openTasksAction),
            paletteCommand(id: "open-editor", title: "Open in Editor", subtitle: "Open the current Markdown file in your editor", keywords: ["external"], action: selectedDocumentAction { library.openSelectedInEditor(settings: settings) }),
            paletteCommand(id: "reveal-finder", title: "Reveal in Finder", subtitle: "Show the current file in Finder", keywords: ["folder", "file"], action: selectedDocumentAction(library.revealSelectedDocumentInFinder)),
            paletteCommand(id: "copy-path", title: "Copy File Path", subtitle: "Copy the current file path", shortcut: "⌥⇧⌘C", keywords: ["clipboard"], action: selectedDocumentAction(library.copySelectedDocumentPath)),
            paletteCommand(id: "copy-markdown", title: "Copy Markdown", subtitle: "Copy the current note as Markdown", shortcut: "⌘M", keywords: ["clipboard", "md"], action: selectedDocumentAction(library.copySelectedDocumentMarkdown)),
            paletteCommand(id: "copy-markdown-link", title: "Copy Markdown Link", subtitle: "Copy a Markdown link to the current note", shortcut: "⌘L", keywords: ["clipboard", "link"], action: selectedDocumentAction(library.copySelectedDocumentMarkdownLink)),
            paletteCommand(id: "copy-wiki-link", title: "Copy Wiki Link", subtitle: "Copy a wiki link to the current note", shortcut: "⌘W", keywords: ["clipboard", "wikilink"], action: selectedDocumentAction(library.copySelectedDocumentWikiLink)),
            paletteCommand(id: "undo-note-change", title: "Undo Last Note Change", subtitle: "Undo the last safe note change", shortcut: "⇧⌘Z", keywords: ["restore"]) {
                library.undoLastChangeToSelectedNote()
            },
            paletteCommand(id: "back", title: "Back", subtitle: "Navigate to the previous note", shortcut: "⌘←", keywords: ["history"], action: navigateBackAction),
            paletteCommand(id: "forward", title: "Forward", subtitle: "Navigate to the next note", shortcut: "⌘→", keywords: ["history"], action: navigateForwardAction),
            paletteCommand(id: "quick-switcher", title: "Quick Switcher", subtitle: "Open a note by fuzzy search", shortcut: "⌘O", keywords: ["note", "open"]) {
                showingQuickSwitcher = true
            },
            paletteCommand(id: "command-palette", title: "Command Palette", subtitle: "Search every command", shortcut: "⌘P", keywords: ["actions"]) {
                showingCommandPalette = true
            },
            paletteCommand(id: "toggle-outline", title: "Toggle Outline", subtitle: "Show or hide the document outline", keywords: ["view"]) {
                settings.showOutline.toggle()
            },
            paletteCommand(id: "toggle-focus", title: "Toggle Focus Mode", subtitle: "Focus the reader", keywords: ["view", "reading"]) {
                settings.isFocusMode.toggle()
            },
            paletteCommand(id: "find-files", title: "Find in Files", subtitle: "Focus the file search field", keywords: ["search"]) {
                isSearchFocused = true
            },
            paletteCommand(id: "clear-search", title: "Clear Search", subtitle: "Clear file search", shortcut: "Esc", keywords: ["search"], action: clearSearchAction),
            paletteCommand(id: "ai-link", title: "AI Link Notes", subtitle: "Suggest wiki links with local review", keywords: ["intelligence", "links"], action: library.hasFolders && !library.isRunningAI ? { showingAIProviderSheet = true } : nil),
            paletteCommand(id: "cribble-ai", title: "Cribble AI Chat", subtitle: "Open the local-first AI chat", keywords: ["assistant", "chat"]) {
                openChatHUD()
            },
            paletteCommand(id: "summarize", title: "Summarize Current Note", subtitle: "Ask local AI for a summary", keywords: ["ai"], action: summarizeWithAIAction),
            paletteCommand(id: "explain", title: "Explain Current Note Simply", subtitle: "Ask local AI for a simpler explanation", keywords: ["ai"], action: explainSimplyWithAIAction),
            paletteCommand(id: "related-ai", title: "Find Related Notes", subtitle: "Ask local AI for related notes", keywords: ["ai"], action: findRelatedWithAIAction),
            paletteCommand(id: "index-ai", title: "Create Index Note", subtitle: "Draft an index note with AI", keywords: ["ai"], action: createIndexWithAIAction),
            paletteCommand(id: "draft-today", title: "Draft Today with AI", subtitle: "Draft today's note with AI", keywords: ["daily", "ai"], action: draftTodayWithAIAction),
            paletteCommand(id: "extract-tasks", title: "Extract Tasks from Current Note", subtitle: "Find tasks in the current note", keywords: ["ai", "todo"], action: extractTasksWithAIAction),
            paletteCommand(id: "intelligence", title: "Project Intelligence", subtitle: "Open the intelligence window", keywords: ["ai", "runner"]) {
                openIntelligenceHUD()
            },
            paletteCommand(id: "demo-tour", title: "Open DemoNotes Tour", subtitle: "Open the bundled DemoNotes folder", keywords: ["help", "guide"]) {
                library.openDemoLibrary(sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "reset-demo", title: "Reset DemoNotes Tour", subtitle: "Restore the bundled DemoNotes folder", keywords: ["help", "guide"]) {
                library.openDemoLibrary(sortMode: settings.fileSortMode, reset: true)
            },
            paletteCommand(id: "guide-cribble-ai", title: "Open Cribble AI Guide", subtitle: "Open the bundled AI guide", keywords: ["help", "guide"]) {
                library.openDemoNote(named: "Cribble AI.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-workflow", title: "Open Workflow Playbook", subtitle: "Open the bundled workflow guide", keywords: ["help", "guide"]) {
                library.openDemoNote(named: "Workflow Playbook.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-tasks", title: "Open Tasks & Intelligence Guide", subtitle: "Open the bundled tasks guide", keywords: ["help", "guide"]) {
                library.openDemoNote(named: "Tasks and Intelligence.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-research", title: "Open Research Review Guide", subtitle: "Open the bundled research guide", keywords: ["help", "guide"]) {
                library.openDemoNote(named: "Research Review.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-decision", title: "Open Decision Log Guide", subtitle: "Open the bundled decision guide", keywords: ["help", "guide"]) {
                library.openDemoNote(named: "Decision Log.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-team-extension", title: "Open Team Extension Kit", subtitle: "Open the bundled extension guide", keywords: ["help", "guide", "plugin"]) {
                library.openDemoNote(named: "Team Extension Kit.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-extension-contribution", title: "Open Extension Contribution Guide", subtitle: "Open the bundled contribution guide", keywords: ["help", "guide", "plugin"]) {
                library.openDemoNote(named: "Extension Contribution Guide.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "guide-remote-intelligence", title: "Open Remote Intelligence Guide", subtitle: "Open the bundled remote intelligence guide", keywords: ["help", "guide", "runner"]) {
                library.openDemoNote(named: "Extensions and Remote Intelligence.md", sortMode: settings.fileSortMode)
            },
            paletteCommand(id: "settings-extensions", title: "Open Extension Settings", subtitle: "Configure extensions", keywords: ["plugins", "preferences"], action: openSettingsWindow),
            paletteCommand(id: "copy-extension-proposal", title: "Copy Extension Proposal", subtitle: "Copy the extension proposal template", keywords: ["help", "clipboard"], action: copyExtensionProposal),
            paletteCommand(id: "copy-decision-template", title: "Copy Decision Entry Template", subtitle: "Copy the decision log template", keywords: ["help", "clipboard"], action: copyDecisionEntryTemplate),
            paletteCommand(id: "copy-research-template", title: "Copy Research Review Template", subtitle: "Copy the research review template", keywords: ["help", "clipboard"], action: copyResearchReviewTemplate),
            paletteCommand(id: "copy-remote-review", title: "Copy Remote Runner Setup Review", subtitle: "Copy the remote runner review", keywords: ["help", "clipboard"], action: copyRemoteRunnerSetupReview),
            paletteCommand(id: "copy-import-review", title: "Copy Import Lane Setup Review", subtitle: "Copy the import lane review", keywords: ["help", "clipboard"], action: copyImportLaneSetupReview),
            paletteCommand(id: "copy-product-checkpoint", title: "Copy Product Readiness Checkpoint", subtitle: "Copy the readiness checklist", keywords: ["help", "clipboard"], action: copyProductReadinessCheckpoint),
            paletteCommand(id: "copy-starter-checklist", title: "Copy Starter Checklist", subtitle: "Copy the starter checklist", keywords: ["help", "clipboard"], action: copyStarterChecklist),
            paletteCommand(id: "diagnostics", title: "Show Diagnostic Report", subtitle: "Open diagnostics", shortcut: "⇧⌘D", keywords: ["help", "report"]) {
                showingDiagnosticsReport = true
            },
            paletteCommand(id: "copy-diagnostics", title: "Copy Diagnostic Report", subtitle: "Copy diagnostics to the clipboard", shortcut: "⌥⌘C", keywords: ["help", "report"]) {
                diagnostics.copyReport(library: library, settings: settings, intelligence: intelligenceDiagnostics, extensions: extensionDiagnostics)
            },
            paletteCommand(id: "reveal-crash", title: "Reveal Latest Crash Report", subtitle: "Show the latest crash report in Finder", keywords: ["help", "diagnostics"]) {
                _ = diagnostics.revealLatestCrashReportInFinder()
            },
            paletteCommand(id: "report-issue", title: "Report Issue on GitHub", subtitle: "Open a prefilled issue", keywords: ["help", "bug"]) {
                reportIssueOnGitHub()
            },
            paletteCommand(id: "open-pr", title: "Open Pull Request on GitHub", subtitle: "Open the project pull request page", keywords: ["help", "github"]) {
                openPullRequestOnGitHub()
            }
        ]
    }

    private func paletteCommand(
        id: String,
        title: String,
        subtitle: String? = nil,
        shortcut: String? = nil,
        keywords: [String] = [],
        action: (() -> Void)?
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            shortcut: shortcut,
            keywords: keywords,
            isEnabled: action != nil,
            action: action ?? {}
        )
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            ReaderView(shortcutActions: readerShortcutActions)
        }
    }

    /// Narrow windows: the reader fills the width and the sidebar slides in over
    /// it on demand, never changing the window size.
    private var compactLayout: some View {
        ZStack(alignment: .leading) {
            ReaderView(shortcutActions: readerShortcutActions)

            if showCompactSidebar {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showCompactSidebar = false }
                    }
                    .transition(.opacity)

                SidebarView()
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                    .cribbleInteractiveGlass(in: Rectangle())
                    .cribbleGlassContainer()
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.separator).frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 18, x: 6)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
    }

    private func updateCompactState(for width: CGFloat) {
        let compact = width < Self.compactWidthThreshold
        guard compact != isCompactWidth else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isCompactWidth = compact
            if compact { showCompactSidebar = false }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if isCompactWidth {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showCompactSidebar.toggle() }
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .cribbleToolbarIcon()
                .help("Show or hide the file sidebar")
            }

            Button {
                library.navigateBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!library.canNavigateBack)
            .cribbleToolbarIcon()
            .help("Navigate back (Left)")

            Button {
                library.navigateForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .disabled(!library.canNavigateForward)
            .cribbleToolbarIcon()
            .help("Navigate forward (Right)")
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
            .cribbleToolbarIcon()
            .help("Toggle Focus Mode (Space)")

            Button {
                settings.showOutline.toggle()
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .disabled(library.selectedDocument == nil || settings.isFocusMode)
            .cribbleToolbarIcon()
            .help("Toggle Headings Outline (O)")

            Button {
                showingAIProviderSheet = true
            } label: {
                Label("AI Link Notes", systemImage: "link")
            }
            .disabled(!library.hasFolders || library.isRunningAI)
            .cribbleToolbarIcon()
            .help("Ask a local AI tool to suggest wiki links with a patch preview (L)")

            Button {
                openChatHUD()
            } label: {
                Label("Cribble AI", systemImage: "bubble.left.and.text.bubble.right")
            }
            .cribbleToolbarIcon()
            .help("Open the local-first AI chat (C)")
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
        let report = diagnostics.makeReport(
            library: library,
            settings: settings,
            intelligence: intelligenceDiagnostics,
            extensions: extensionDiagnostics
        )
        GitHubReport.openIssue(report: report)
        diagnostics.record(level: .info, message: "Opened GitHub issue flow.")
    }

    private func openPullRequestOnGitHub() {
        let report = diagnostics.makeReport(
            library: library,
            settings: settings,
            intelligence: intelligenceDiagnostics,
            extensions: extensionDiagnostics
        )
        GitHubReport.openPullRequest(report: report)
        diagnostics.record(level: .info, message: "Opened GitHub pull request flow.")
    }

    private var intelligenceDiagnostics: IntelligenceDiagnosticsSnapshot {
        intelligence.diagnosticsSnapshot()
    }

    private var extensionDiagnostics: ExtensionDiagnosticsSnapshot {
        ExtensionDiagnosticsSnapshot(
            installed: extensionRegistry.installedExtensions,
            disabledIDs: extensionRegistry.disabledExtensionIDs,
            warnings: extensionRegistry.loadWarnings
        )
    }

    private func restoreIntelligenceAfterConsent(root: URL) {
        let standardized = root.standardizedFileURL
        extensionRegistry.reload(projectRoots: library.rootURLs)
        if let profile = ExtensionRunnerConsentStore().requiredApprovalProfile(
            runnerURL: intelligence.settings.localRunnerBaseURL,
            modelID: intelligence.settings.modelID,
            profiles: extensionRegistry.intelligenceProviderProfiles
        ) {
            pendingRestoreRunnerConsent = ExtensionRunnerConsentRequest(url: standardized, profile: profile)
            return
        }
        Task { await intelligence.restoreIfEnabled(rootURL: standardized) }
    }

    private func createProjectImportLane() {
        guard let root = library.activeRootURL else {
            importGuidanceStatus = "Open a folder before creating a project import lane."
            return
        }

        do {
            let url = try extensionRegistry.writeProjectExampleManifest(template: .importer, projectRoot: root)
            extensionRegistry.reload(projectRoots: library.rootURLs)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            importGuidanceStatus = "Created \(folderName) in this folder. Adapt the manifest, then open Settings > Extensions > Import lanes > Copy Review."
            library.statusMessage = "Created project import lane example"
        } catch {
            importGuidanceStatus = error.localizedDescription
        }
    }

    private func createUserImportLane() {
        do {
            let url = try extensionRegistry.writeExampleManifest(template: .importer)
            extensionRegistry.reload(projectRoots: library.rootURLs)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            importGuidanceStatus = "Created \(folderName) in your user extension folder. Adapt the manifest, then open Settings > Extensions > Import lanes > Copy Review."
            library.statusMessage = "Created user import lane example"
        } catch {
            importGuidanceStatus = error.localizedDescription
        }
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct ImportGuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedReview = false

    let canCreateProjectExample: Bool
    let status: String?
    let onCreateProjectExample: () -> Void
    let onCreateUserExample: () -> Void
    let onOpenSettings: () -> Void
    let onOpenTeamKit: () -> Void
    let onOpenContributionGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up an Import Lane")
                        .font(.title3.weight(.semibold))
                    Text("Import starts with enabled declarative extensions. Create a starter lane, review the manifest, then adapt it for your team before any converter execution exists.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ImportSafetyRow(
                    icon: "doc.text.magnifyingglass",
                    title: "1. Declare the files",
                    detail: "The manifest lists file extensions and the intended output format."
                )
                ImportSafetyRow(
                    icon: "checkmark.shield",
                    title: "2. Review the lane",
                    detail: "API v1 stays data-only: no scripts, binaries, or network calls run from importers."
                )
                ImportSafetyRow(
                    icon: "power",
                    title: "3. Disable cleanly",
                    detail: "Turning the extension off removes its import lane from the app."
                )
                ImportSafetyRow(
                    icon: "doc.on.doc",
                    title: "4. Copy the installed review",
                    detail: "After the lane appears, use Settings > Extensions > Import lanes > Copy Review for the handoff."
                )
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    onCreateProjectExample()
                } label: {
                    Label("Create Project Import Lane", systemImage: "folder.badge.plus")
                }
                .disabled(!canCreateProjectExample)
                .help("Write an importer manifest into the current folder's .cribble/extensions directory")

                Button {
                    onCreateUserExample()
                } label: {
                    Label("Create User Import Lane", systemImage: "person.crop.circle.badge.plus")
                }
                .help("Write an importer manifest into Cribble's user extension folder")

                Divider()

                Button {
                    copyImportLaneSetupReview()
                } label: {
                    Label(copiedReview ? "Copied Review" : "Copy Review", systemImage: copiedReview ? "checkmark" : "doc.on.doc")
                }
                .help("Copy the import-lane setup safety checklist")

                Button {
                    onOpenSettings()
                } label: {
                    Label("Open Extension Settings", systemImage: "gearshape")
                }
                .help("Open Settings to copy the installed import-lane review")

                Button {
                    onOpenTeamKit()
                } label: {
                    Label("Open Team Extension Kit", systemImage: "book.pages")
                }

                Button {
                    onOpenContributionGuide()
                } label: {
                    Label("Open Contribution Guide", systemImage: "checkmark.shield")
                }
                .help("Open the strict read-only, least-writing, native SwiftUI contribution guide")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !canCreateProjectExample {
                Label("Open a Markdown folder to create a project-local import lane.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private func copyImportLaneSetupReview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ImportLaneSetupReview.markdown, forType: .string)
        copiedReview = true
    }
}

private struct ImportSafetyRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        .cribbleToolbarIcon()
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
        .cribbleToolbarIcon()
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
