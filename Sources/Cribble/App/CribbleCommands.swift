import SwiftUI

struct CribbleCommands: Commands {
    @FocusedValue(\.openFolderAction) private var openFolder
    @FocusedValue(\.refreshFolderAction) private var refreshFolder
    @FocusedValue(\.openInEditorAction) private var openInEditor
    @FocusedValue(\.runAILinkingAction) private var runAILinking
    @FocusedValue(\.showDiagnosticsAction) private var showDiagnostics
    @FocusedValue(\.copyDiagnosticsAction) private var copyDiagnostics
    @FocusedValue(\.revealCrashReportAction) private var revealCrashReport
    @FocusedValue(\.reportIssueAction) private var reportIssue
    @FocusedValue(\.openPullRequestAction) private var openPullRequest
    @FocusedValue(\.navigateBackAction) private var navigateBack
    @FocusedValue(\.navigateForwardAction) private var navigateForward
    @FocusedValue(\.toggleOutlineAction) private var toggleOutline
    @FocusedValue(\.toggleFocusModeAction) private var toggleFocusMode

    var body: some Commands {
        CommandMenu("Library") {
            Button("Open Folder...", action: { openFolder?() })
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(openFolder == nil)

            Button("Refresh", action: { refreshFolder?() })
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(refreshFolder == nil)

            Divider()

            Button("Open in Editor", action: { openInEditor?() })
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(openInEditor == nil)

            Button("AI Link Notes...", action: { runAILinking?() })
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(runAILinking == nil)
        }

        CommandMenu("Go") {
            Button("Back", action: { navigateBack?() })
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(navigateBack == nil)

            Button("Forward", action: { navigateForward?() })
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(navigateForward == nil)
        }

        CommandMenu("View") {
            Button("Toggle Outline", action: { toggleOutline?() })
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(toggleOutline == nil)

            Button("Toggle Focus Mode", action: { toggleFocusMode?() })
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(toggleFocusMode == nil)
        }

        CommandMenu("Diagnostics") {
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

private struct RefreshFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenInEditorActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RunAILinkingActionKey: FocusedValueKey {
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

extension FocusedValues {
    var openFolderAction: (() -> Void)? {
        get { self[OpenFolderActionKey.self] }
        set { self[OpenFolderActionKey.self] = newValue }
    }

    var refreshFolderAction: (() -> Void)? {
        get { self[RefreshFolderActionKey.self] }
        set { self[RefreshFolderActionKey.self] = newValue }
    }

    var openInEditorAction: (() -> Void)? {
        get { self[OpenInEditorActionKey.self] }
        set { self[OpenInEditorActionKey.self] = newValue }
    }

    var runAILinkingAction: (() -> Void)? {
        get { self[RunAILinkingActionKey.self] }
        set { self[RunAILinkingActionKey.self] = newValue }
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
}
