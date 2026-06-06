import AppKit
import SwiftUI

/// Floating panel that hosts the Intelligence HUD above Cribble's window —
/// the project-intelligence cockpit, separate from the Chat HUD (design plan
/// §10). Mirrors `CribbleChatPanel`/`ChatHUDController` so the two HUDs feel
/// like siblings.
final class IntelligencePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 380, height: 520)
        maxSize = NSSize(width: 900, height: 1400)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first mouse click even when its window isn't
/// key. Without this, a `.nonactivatingPanel`'s first click only keys the window
/// (it's swallowed), so buttons/menus in the floating HUD appear unresponsive
/// whenever another app has stolen focus. Returning true delivers that first
/// click straight to the SwiftUI controls.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

/// Owns the single Intelligence HUD panel and the purchase gate, mirroring
/// `ChatHUDController`. The view binds directly to the shared `IntelligenceEngine`.
@MainActor
final class IntelligenceHUDController {
    static let shared = IntelligenceHUDController()

    private var panel: IntelligencePanel?
    private weak var engine: IntelligenceEngine?
    private weak var library: MarkdownLibraryStore?
    private weak var entitlement: LLMEntitlementStore?
    private var onLocked: (() -> Void)?

    private init() {}

    func configure(
        engine: IntelligenceEngine,
        library: MarkdownLibraryStore,
        entitlement: LLMEntitlementStore,
        onLocked: @escaping () -> Void
    ) {
        self.engine = engine
        self.library = library
        self.entitlement = entitlement
        self.onLocked = onLocked
    }

    func toggle() {
        guard gatePassed() else { return }
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            present()
        }
    }

    /// Presents the HUD without toggling (used when switching projects so it
    /// stays open rather than closing).
    func show() {
        guard gatePassed() else { return }
        present()
    }

    func close() { panel?.orderOut(nil) }

    private func gatePassed() -> Bool {
        if entitlement?.isUnlocked ?? true { return true }
        onLocked?()
        return false
    }

    private func present() {
        guard let engine, let library else { return }
        let panel = self.panel ?? makePanel(engine: engine, library: library)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel(engine: IntelligenceEngine, library: MarkdownLibraryStore) -> IntelligencePanel {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 720)
        let panel = IntelligencePanel(contentRect: frame)
        panel.setFrameAutosaveName("CribbleIntelligenceHUDPanel")

        let root = IntelligenceHUDView(
            engine: engine,
            activeRootURL: { [weak library] in library?.activeRootURL },
            onClose: { [weak self] in self?.close() },
            onOpenSource: { [weak library, weak engine] path in
                // Resolve via the engine (handles absolute paths in all-folders scope).
                guard let url = engine?.resolveProjectFile(path) else { return }
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                if url.pathExtension.lowercased() == "md" {
                    // Markdown opens in Cribble's reader.
                    library?.selectedURL = url
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.isVisible && !($0 is IntelligencePanel) })?.makeKeyAndOrderFront(nil)
                } else {
                    // Cribble is a Markdown reader; reveal code files in Finder.
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            allRoots: { [weak library] in library?.rootURLs ?? [] },
            latestContextReceipt: { ChatHUDController.shared.latestContextReceipt }
        )

        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        panel.center()
        return panel
    }
}
