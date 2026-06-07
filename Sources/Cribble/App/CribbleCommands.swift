import SwiftUI

struct CribbleCommands: Commands {
    @FocusedValue(\.newNoteAction) private var newNote
    @FocusedValue(\.openTodayNoteAction) private var openTodayNote
    @FocusedValue(\.openFolderAction) private var openFolder
    @FocusedValue(\.importFileAction) private var importFile
    @FocusedValue(\.refreshFolderAction) private var refreshFolder
    @FocusedValue(\.openTasksAction) private var openTasks
    @FocusedValue(\.openInEditorAction) private var openInEditor
    @FocusedValue(\.revealSelectedDocumentAction) private var revealSelectedDocument
    @FocusedValue(\.copySelectedDocumentPathAction) private var copySelectedDocumentPath
    @FocusedValue(\.copySelectedDocumentMarkdownAction) private var copySelectedDocumentMarkdown
    @FocusedValue(\.copySelectedDocumentMarkdownLinkAction) private var copySelectedDocumentMarkdownLink
    @FocusedValue(\.copySelectedDocumentWikiLinkAction) private var copySelectedDocumentWikiLink
    @FocusedValue(\.undoNoteChangeAction) private var undoNoteChange
    @FocusedValue(\.runAILinkingAction) private var runAILinking
    @FocusedValue(\.summarizeWithAIAction) private var summarizeWithAI
    @FocusedValue(\.explainSimplyWithAIAction) private var explainSimplyWithAI
    @FocusedValue(\.findRelatedWithAIAction) private var findRelatedWithAI
    @FocusedValue(\.createIndexWithAIAction) private var createIndexWithAI
    @FocusedValue(\.draftTodayWithAIAction) private var draftTodayWithAI
    @FocusedValue(\.extractTasksWithAIAction) private var extractTasksWithAI
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
    @FocusedValue(\.focusSearchAction) private var focusSearch
    @FocusedValue(\.clearSearchAction) private var clearSearch
    @FocusedValue(\.openDemoNotesAction) private var openDemoNotes
    @FocusedValue(\.openCribbleAIGuideAction) private var openCribbleAIGuide
    @FocusedValue(\.openWorkflowPlaybookAction) private var openWorkflowPlaybook
    @FocusedValue(\.openTasksGuideAction) private var openTasksGuide
    @FocusedValue(\.openResearchReviewAction) private var openResearchReview
    @FocusedValue(\.openDecisionLogGuideAction) private var openDecisionLogGuide
    @FocusedValue(\.openTeamExtensionKitAction) private var openTeamExtensionKit
    @FocusedValue(\.openRemoteIntelligenceGuideAction) private var openRemoteIntelligenceGuide
    @FocusedValue(\.openExtensionSettingsAction) private var openExtensionSettings
    @FocusedValue(\.copyExtensionProposalAction) private var copyExtensionProposal
    @FocusedValue(\.copyRemoteRunnerSetupReviewAction) private var copyRemoteRunnerSetupReview
    @FocusedValue(\.copyStarterChecklistAction) private var copyStarterChecklist
    @FocusedValue(\.resetDemoNotesAction) private var resetDemoNotes
    @FocusedValue(\.dropReadingBookmarkAction) private var dropReadingBookmark
    @FocusedValue(\.highlightSelectionAction) private var highlightSelection
    @FocusedValue(\.toggleReadingTrailAction) private var toggleReadingTrail

    var body: some Commands {
        // File — folder operations (replaces the default "New" group).
        CommandGroup(replacing: .newItem) {
            Button("New Note", action: { newNote?() })
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(newNote == nil)

            Button("Open Today Note", action: { openTodayNote?() })
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(openTodayNote == nil)

            Divider()

            Button("Open Folder…", action: { openFolder?() })
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(openFolder == nil)

            Button("Import…", action: { importFile?() })
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(importFile == nil)

            Button("Refresh", action: { refreshFolder?() })
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(refreshFolder == nil)

            Button("Open Tasks", action: { openTasks?() })
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(openTasks == nil)

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

            Button("Copy Markdown", action: { copySelectedDocumentMarkdown?() })
                .keyboardShortcut("m", modifiers: [.command, .option, .shift])
                .disabled(copySelectedDocumentMarkdown == nil)

            Button("Copy Markdown Link", action: { copySelectedDocumentMarkdownLink?() })
                .keyboardShortcut("k", modifiers: [.command, .option, .shift])
                .disabled(copySelectedDocumentMarkdownLink == nil)

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

            Button("Drop Reading Bookmark", action: { dropReadingBookmark?() })
                .disabled(dropReadingBookmark == nil)

            Button("Highlight", action: { highlightSelection?() })
                .disabled(highlightSelection == nil)

            Button("Toggle Reading Trail", action: { toggleReadingTrail?() })
                .disabled(toggleReadingTrail == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Files", action: { focusSearch?() })
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(focusSearch == nil)

            Button("Clear Search", action: { clearSearch?() })
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(clearSearch == nil)
        }

        // AI — the two LLM entry points.
        CommandMenu("AI") {
            Button("AI Link Notes…", action: { runAILinking?() })
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(runAILinking == nil)

            Button("Cribble AI Chat", action: { toggleChatHUD?() })
                .keyboardShortcut("j", modifiers: [.command])
                .disabled(toggleChatHUD == nil)

            Divider()

            Button("Summarize Current Note", action: { summarizeWithAI?() })
                .disabled(summarizeWithAI == nil)

            Button("Explain Current Note Simply", action: { explainSimplyWithAI?() })
                .disabled(explainSimplyWithAI == nil)

            Button("Find Related Notes", action: { findRelatedWithAI?() })
                .disabled(findRelatedWithAI == nil)

            Button("Create Index Note", action: { createIndexWithAI?() })
                .disabled(createIndexWithAI == nil)

            Divider()

            Button("Draft Today with AI", action: { draftTodayWithAI?() })
                .disabled(draftTodayWithAI == nil)

            Button("Extract Tasks from Current Note", action: { extractTasksWithAI?() })
                .disabled(extractTasksWithAI == nil)

            Divider()

            Button("Project Intelligence", action: { toggleIntelligenceHUD?() })
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(toggleIntelligenceHUD == nil)
        }

        // Help — diagnostics live here instead of a top-level menu. (Check for
        // Updates is in the Cribble app menu, added by AppDelegate.)
        CommandGroup(replacing: .help) {
            Button("Open DemoNotes Tour", action: { openDemoNotes?() })
                .disabled(openDemoNotes == nil)

            Button("Open Cribble AI Guide", action: { openCribbleAIGuide?() })
                .disabled(openCribbleAIGuide == nil)

            Button("Open Workflow Playbook", action: { openWorkflowPlaybook?() })
                .disabled(openWorkflowPlaybook == nil)

            Button("Open Tasks & Intelligence Guide", action: { openTasksGuide?() })
                .disabled(openTasksGuide == nil)

            Button("Open Research Review Guide", action: { openResearchReview?() })
                .disabled(openResearchReview == nil)

            Button("Open Decision Log Guide", action: { openDecisionLogGuide?() })
                .disabled(openDecisionLogGuide == nil)

            Button("Open Team Extension Kit", action: { openTeamExtensionKit?() })
                .disabled(openTeamExtensionKit == nil)

            Button("Open Remote Intelligence Guide", action: { openRemoteIntelligenceGuide?() })
                .disabled(openRemoteIntelligenceGuide == nil)

            Button("Open Extension Settings", action: { openExtensionSettings?() })
                .disabled(openExtensionSettings == nil)

            Button("Copy Extension Proposal", action: { copyExtensionProposal?() })
                .disabled(copyExtensionProposal == nil)

            Button("Copy Remote Runner Setup Review", action: { copyRemoteRunnerSetupReview?() })
                .disabled(copyRemoteRunnerSetupReview == nil)

            Button("Copy Starter Checklist", action: { copyStarterChecklist?() })
                .disabled(copyStarterChecklist == nil)

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

private struct NewNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenTodayNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
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

private struct OpenTasksActionKey: FocusedValueKey {
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

private struct CopySelectedDocumentMarkdownActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopySelectedDocumentMarkdownLinkActionKey: FocusedValueKey {
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

private struct SummarizeWithAIActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ExplainSimplyWithAIActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindRelatedWithAIActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CreateIndexWithAIActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DraftTodayWithAIActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ExtractTasksWithAIActionKey: FocusedValueKey {
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

private struct FocusSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ClearSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenDemoNotesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenCribbleAIGuideActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenWorkflowPlaybookActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenTasksGuideActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenResearchReviewActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenDecisionLogGuideActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenTeamExtensionKitActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenRemoteIntelligenceGuideActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenExtensionSettingsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopyExtensionProposalActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopyRemoteRunnerSetupReviewActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CopyStarterChecklistActionKey: FocusedValueKey {
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

private struct ToggleReadingTrailActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newNoteAction: (() -> Void)? {
        get { self[NewNoteActionKey.self] }
        set { self[NewNoteActionKey.self] = newValue }
    }

    var openTodayNoteAction: (() -> Void)? {
        get { self[OpenTodayNoteActionKey.self] }
        set { self[OpenTodayNoteActionKey.self] = newValue }
    }

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

    var openTasksAction: (() -> Void)? {
        get { self[OpenTasksActionKey.self] }
        set { self[OpenTasksActionKey.self] = newValue }
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

    var copySelectedDocumentMarkdownAction: (() -> Void)? {
        get { self[CopySelectedDocumentMarkdownActionKey.self] }
        set { self[CopySelectedDocumentMarkdownActionKey.self] = newValue }
    }

    var copySelectedDocumentMarkdownLinkAction: (() -> Void)? {
        get { self[CopySelectedDocumentMarkdownLinkActionKey.self] }
        set { self[CopySelectedDocumentMarkdownLinkActionKey.self] = newValue }
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

    var summarizeWithAIAction: (() -> Void)? {
        get { self[SummarizeWithAIActionKey.self] }
        set { self[SummarizeWithAIActionKey.self] = newValue }
    }

    var explainSimplyWithAIAction: (() -> Void)? {
        get { self[ExplainSimplyWithAIActionKey.self] }
        set { self[ExplainSimplyWithAIActionKey.self] = newValue }
    }

    var findRelatedWithAIAction: (() -> Void)? {
        get { self[FindRelatedWithAIActionKey.self] }
        set { self[FindRelatedWithAIActionKey.self] = newValue }
    }

    var createIndexWithAIAction: (() -> Void)? {
        get { self[CreateIndexWithAIActionKey.self] }
        set { self[CreateIndexWithAIActionKey.self] = newValue }
    }

    var draftTodayWithAIAction: (() -> Void)? {
        get { self[DraftTodayWithAIActionKey.self] }
        set { self[DraftTodayWithAIActionKey.self] = newValue }
    }

    var extractTasksWithAIAction: (() -> Void)? {
        get { self[ExtractTasksWithAIActionKey.self] }
        set { self[ExtractTasksWithAIActionKey.self] = newValue }
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

    var focusSearchAction: (() -> Void)? {
        get { self[FocusSearchActionKey.self] }
        set { self[FocusSearchActionKey.self] = newValue }
    }

    var clearSearchAction: (() -> Void)? {
        get { self[ClearSearchActionKey.self] }
        set { self[ClearSearchActionKey.self] = newValue }
    }

    var openDemoNotesAction: (() -> Void)? {
        get { self[OpenDemoNotesActionKey.self] }
        set { self[OpenDemoNotesActionKey.self] = newValue }
    }

    var openCribbleAIGuideAction: (() -> Void)? {
        get { self[OpenCribbleAIGuideActionKey.self] }
        set { self[OpenCribbleAIGuideActionKey.self] = newValue }
    }

    var openWorkflowPlaybookAction: (() -> Void)? {
        get { self[OpenWorkflowPlaybookActionKey.self] }
        set { self[OpenWorkflowPlaybookActionKey.self] = newValue }
    }

    var openTasksGuideAction: (() -> Void)? {
        get { self[OpenTasksGuideActionKey.self] }
        set { self[OpenTasksGuideActionKey.self] = newValue }
    }

    var openResearchReviewAction: (() -> Void)? {
        get { self[OpenResearchReviewActionKey.self] }
        set { self[OpenResearchReviewActionKey.self] = newValue }
    }

    var openDecisionLogGuideAction: (() -> Void)? {
        get { self[OpenDecisionLogGuideActionKey.self] }
        set { self[OpenDecisionLogGuideActionKey.self] = newValue }
    }

    var openTeamExtensionKitAction: (() -> Void)? {
        get { self[OpenTeamExtensionKitActionKey.self] }
        set { self[OpenTeamExtensionKitActionKey.self] = newValue }
    }

    var openRemoteIntelligenceGuideAction: (() -> Void)? {
        get { self[OpenRemoteIntelligenceGuideActionKey.self] }
        set { self[OpenRemoteIntelligenceGuideActionKey.self] = newValue }
    }

    var openExtensionSettingsAction: (() -> Void)? {
        get { self[OpenExtensionSettingsActionKey.self] }
        set { self[OpenExtensionSettingsActionKey.self] = newValue }
    }

    var copyExtensionProposalAction: (() -> Void)? {
        get { self[CopyExtensionProposalActionKey.self] }
        set { self[CopyExtensionProposalActionKey.self] = newValue }
    }

    var copyRemoteRunnerSetupReviewAction: (() -> Void)? {
        get { self[CopyRemoteRunnerSetupReviewActionKey.self] }
        set { self[CopyRemoteRunnerSetupReviewActionKey.self] = newValue }
    }

    var copyStarterChecklistAction: (() -> Void)? {
        get { self[CopyStarterChecklistActionKey.self] }
        set { self[CopyStarterChecklistActionKey.self] = newValue }
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

    var toggleReadingTrailAction: (() -> Void)? {
        get { self[ToggleReadingTrailActionKey.self] }
        set { self[ToggleReadingTrailActionKey.self] = newValue }
    }
}
