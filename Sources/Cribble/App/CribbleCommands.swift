import SwiftUI

struct CribbleCommands: Commands {
    @FocusedValue(\.openFolderAction) private var openFolder
    @FocusedValue(\.refreshFolderAction) private var refreshFolder
    @FocusedValue(\.openInEditorAction) private var openInEditor
    @FocusedValue(\.runAILinkingAction) private var runAILinking
    @FocusedValue(\.showDiagnosticsAction) private var showDiagnostics
    @FocusedValue(\.copyDiagnosticsAction) private var copyDiagnostics

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

        CommandMenu("Diagnostics") {
            Button("Show Diagnostic Report", action: { showDiagnostics?() })
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(showDiagnostics == nil)

            Button("Copy Diagnostic Report", action: { copyDiagnostics?() })
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(copyDiagnostics == nil)
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
}
