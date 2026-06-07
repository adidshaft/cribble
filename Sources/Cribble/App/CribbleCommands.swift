import SwiftUI

struct CribbleCommands: Commands {
    @FocusedValue(\.openFolderAction) private var openFolder
    @FocusedValue(\.importFileAction) private var importFile
    @FocusedValue(\.refreshFolderAction) private var refreshFolder
    @FocusedValue(\.openInEditorAction) private var openInEditor
    @FocusedValue(\.revealSelectedDocumentAction) private var revealSelectedDocument
    @FocusedValue(\.copySelectedDocumentPathAction) private var copySelectedDocumentPath
    @FocusedValue(\.copySelectedDocumentWikiLinkAction) private var copySelectedDocumentWikiLink
    @FocusedValue(\.undoNoteChangeAction) private var undoNoteChange
    @FocusedValue(\.runAILinkingAction) private var runAILinking
    @FocusedValue(\.toggleChatHUDAction) private var toggleChatHUD
    @FocusedValue(\.toggleIntelligenceHUDAction) private var toggleIntelligenceHUD
    @FocusedValue(\.showDiagnosticsAction) private var showDiagnostics
    @FocusedValue(\.copyDiagnosticsAction) private var copyDiagnostics
    @FocusedValue(\.revealCrashReportAction) private var revealCrashReport
    @FocusedValue(\.reportIssueAction) private var reportIssue
    @FocusedValue(\.openPullRequestAction) private var openPullRequest
    @FocusedValue(\.navigateBackAction) private var navigateBack
    @FocusedValue(\.navigateForwardAction) private var navigateForward
    @FocusedValue(\.toggleOutlineAction) private var toggleOutline
    @FocusedValue(\.toggleFocusModeAction) private var toggleFocusMode
    @FocusedValue(\.openDemoNotesAction) private var openDemoNotes
    @FocusedValue(\.openWorkflowPlaybookAction) private var openWorkflowPlaybook
    @FocusedValue(\.resetDemoNotesAction) private var resetDemoNotes

    var body: some Commands {
        // File — folder operations (replaces the default "New" group).
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…", action: { openFolder?() })
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(openFolder == nil)

            Button("Import…", action: { importFile?() })
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(importFile == nil)

            Button("Refresh", action: { refreshFolder?() })
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(refreshFolder == nil)

            Divider()

            Button("Open in Editor", action: { openInEditor?() })
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(openInEditor == nil)

            Button("Reveal in Finder", action: { revealSelectedDocument?() })
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(revealSelectedDocument == nil)

            Button("Copy File Path", action: { copySelectedDocumentPath?() })
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(copySelectedDocumentPath == nil)

            Button("Copy Wiki Link", action: { copySelectedDocumentWikiLink?() })
                .keyboardShortcut("l", modifiers: [.command, .option, .shift])
                .disabled(copySelectedDocumentWikiLink == nil)

            Divider()

            Button("Undo Last Note Change", action: { undoNoteChange?() })
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(undoNoteChange == nil)
        }

        // View — navigation, layout, and reading actions, merged into the
        // system View menu (no more duplicate "View").
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Back", action: { navigateBack?() })
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(navigateBack == nil)

            Button("Forward", action: { navigateForward?() })
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(navigateForward == nil)

            Divider()

            Button("Toggle Outline", action: { toggleOutline?() })
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(toggleOutline == nil)

            Button("Toggle Focus Mode", action: { toggleFocusMode?() })
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(toggleFocusMode == nil)

            Divider()

            Button("Drop Reading Bookmark", action: { ReaderShortcutHub.shared.performDropBookmark() })
            Button("Highlight", action: { ReaderShortcutHub.shared.performHighlightKey() })
            Button("Toggle Reading Trail", action: { ReaderShortcutHub.shared.performToggleTrail() })
        }

        // AI — the two LLM entry points.
        CommandMenu("AI") {
            Button("AI Link Notes…", action: { runAILinking?() })
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(runAILinking == nil)

            Button("Cribble AI Chat", action: { toggleChatHUD?() })
                .keyboardShortcut("j", modifiers: [.command])
                .disabled(toggleChatHUD == nil)

            Button("Project Intelligence", action: { toggleIntelligenceHUD?() })
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(toggleIntelligenceHUD == nil)
        }

        // Help — diagnostics live here instead of a top-level menu. (Check for
        // Updates is in the Cribble app menu, added by AppDelegate.)
        CommandGroup(replacing: .help) {
            Button("Open DemoNotes Tour", action: { openDemoNotes?() })
                .disabled(openDemoNotes == nil)

            Button("Open Workflow Playbook", action: { openWorkflowPlaybook?() })
                .disabled(openWorkflowPlaybook == nil)

            Button("Reset DemoNotes Tour", action: { resetDemoNotes?() })
                .disabled(resetDemoNotes == nil)

            Divider()

            Button("Show Diagnostic Report", action: { showDiagnostics?() })
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(showDiagnostics == nil)

            Button("Copy Diagnostic Report", action: { copyDiagnostics?() })
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(copyDiagnostics == nil)

            Button("Reveal Latest Crash Report", action: { revealCrashReport?() })
                .disabled(revealCrashReport == nil)

            Divider()

            Button("Report Issue on GitHub", action: { reportIssue?() })
                .disabled(reportIssue == nil)

            Button("Open Pull Request on GitHub", action: { openPullRequest?() })
                .disabled(openPullRequest == nil)
        }
    }
}

private struct OpenFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ImportFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RefreshFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenInEditorActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RevealSelectedDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopySelectedDocumentPathActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopySelectedDocumentWikiLinkActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct UndoNoteChangeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RunAILinkingActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleChatHUDActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleIntelligenceHUDActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowDiagnosticsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopyDiagnosticsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RevealCrashReportActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ReportIssueActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenPullRequestActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NavigateBackActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NavigateForwardActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleOutlineActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleFocusModeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenDemoNotesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenWorkflowPlaybookActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ResetDemoNotesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DropReadingBookmarkActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct HighlightSelectionActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFolderAction: (() -> Void)? {
        get { self[OpenFolderActionKey.self] }
        set { self[OpenFolderActionKey.self] = newValue }
    }

    var importFileAction: (() -> Void)? {
        get { self[ImportFileActionKey.self] }
        set { self[ImportFileActionKey.self] = newValue }
    }

    var refreshFolderAction: (() -> Void)? {
        get { self[RefreshFolderActionKey.self] }
        set { self[RefreshFolderActionKey.self] = newValue }
    }

    var openInEditorAction: (() -> Void)? {
        get { self[OpenInEditorActionKey.self] }
        set { self[OpenInEditorActionKey.self] = newValue }
    }

    var revealSelectedDocumentAction: (() -> Void)? {
        get { self[RevealSelectedDocumentActionKey.self] }
        set { self[RevealSelectedDocumentActionKey.self] = newValue }
    }

    var copySelectedDocumentPathAction: (() -> Void)? {
        get { self[CopySelectedDocumentPathActionKey.self] }
        set { self[CopySelectedDocumentPathActionKey.self] = newValue }
    }

    var copySelectedDocumentWikiLinkAction: (() -> Void)? {
        get { self[CopySelectedDocumentWikiLinkActionKey.self] }
        set { self[CopySelectedDocumentWikiLinkActionKey.self] = newValue }
    }

    var undoNoteChangeAction: (() -> Void)? {
        get { self[UndoNoteChangeActionKey.self] }
        set { self[UndoNoteChangeActionKey.self] = newValue }
    }

    var runAILinkingAction: (() -> Void)? {
        get { self[RunAILinkingActionKey.self] }
        set { self[RunAILinkingActionKey.self] = newValue }
    }

    var toggleChatHUDAction: (() -> Void)? {
        get { self[ToggleChatHUDActionKey.self] }
        set { self[ToggleChatHUDActionKey.self] = newValue }
    }

    var toggleIntelligenceHUDAction: (() -> Void)? {
        get { self[ToggleIntelligenceHUDActionKey.self] }
        set { self[ToggleIntelligenceHUDActionKey.self] = newValue }
    }

    var showDiagnosticsAction: (() -> Void)? {
        get { self[ShowDiagnosticsActionKey.self] }
        set { self[ShowDiagnosticsActionKey.self] = newValue }
    }

    var copyDiagnosticsAction: (() -> Void)? {
        get { self[CopyDiagnosticsActionKey.self] }
        set { self[CopyDiagnosticsActionKey.self] = newValue }
    }

    var revealCrashReportAction: (() -> Void)? {
        get { self[RevealCrashReportActionKey.self] }
        set { self[RevealCrashReportActionKey.self] = newValue }
    }

    var reportIssueAction: (() -> Void)? {
        get { self[ReportIssueActionKey.self] }
        set { self[ReportIssueActionKey.self] = newValue }
    }

    var openPullRequestAction: (() -> Void)? {
        get { self[OpenPullRequestActionKey.self] }
        set { self[OpenPullRequestActionKey.self] = newValue }
    }

    var navigateBackAction: (() -> Void)? {
        get { self[NavigateBackActionKey.self] }
        set { self[NavigateBackActionKey.self] = newValue }
    }

    var navigateForwardAction: (() -> Void)? {
        get { self[NavigateForwardActionKey.self] }
        set { self[NavigateForwardActionKey.self] = newValue }
    }

    var toggleOutlineAction: (() -> Void)? {
        get { self[ToggleOutlineActionKey.self] }
        set { self[ToggleOutlineActionKey.self] = newValue }
    }

    var toggleFocusModeAction: (() -> Void)? {
        get { self[ToggleFocusModeActionKey.self] }
        set { self[ToggleFocusModeActionKey.self] = newValue }
    }

    var openDemoNotesAction: (() -> Void)? {
        get { self[OpenDemoNotesActionKey.self] }
        set { self[OpenDemoNotesActionKey.self] = newValue }
    }

    var openWorkflowPlaybookAction: (() -> Void)? {
        get { self[OpenWorkflowPlaybookActionKey.self] }
        set { self[OpenWorkflowPlaybookActionKey.self] = newValue }
    }

    var resetDemoNotesAction: (() -> Void)? {
        get { self[ResetDemoNotesActionKey.self] }
        set { self[ResetDemoNotesActionKey.self] = newValue }
    }

    var dropReadingBookmarkAction: (() -> Void)? {
        get { self[DropReadingBookmarkActionKey.self] }
        set { self[DropReadingBookmarkActionKey.self] = newValue }
    }

    var highlightSelectionAction: (() -> Void)? {
        get { self[HighlightSelectionActionKey.self] }
        set { self[HighlightSelectionActionKey.self] = newValue }
    }
}
