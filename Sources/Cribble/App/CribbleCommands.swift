import SwiftUI

struct CribbleCommands: Commands {
    @FocusedValue(\.openFolderAction) private var openFolder
    @FocusedValue(\.refreshFolderAction) private var refreshFolder
    @FocusedValue(\.openInEditorAction) private var openInEditor
    @FocusedValue(\.runAILinkingAction) private var runAILinking

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
}
