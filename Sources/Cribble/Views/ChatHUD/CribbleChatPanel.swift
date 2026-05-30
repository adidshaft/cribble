import AppKit
import SwiftUI

/// Floating, non-activating HUD panel that hosts the Local Chat interface above
/// the main window (and other apps). Translucent dark "hudWindow" backdrop.
final class CribbleChatPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Companion to Cribble's window, not a global overlay: it floats above
        // Cribble's own windows but steps aside (hides) when another app is
        // active, so it isn't on top of everything all the time.
        hidesOnDeactivate = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        isMovableByWindowBackground = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Keep a sensible resize envelope matching the 1:2 design profile.
        minSize = NSSize(width: 320, height: 480)
        maxSize = NSSize(width: 640, height: 1300)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the single shared HUD panel and its view model. Lifecycle and framing
/// live here so SwiftUI views stay declarative.
@MainActor
final class ChatHUDController {
    static let shared = ChatHUDController()

    private var panel: CribbleChatPanel?
    private var viewModel: ChatHUDViewModel?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the panel, creating it (and the view model) on first use, or hides
    /// it if already on screen.
    func toggle(library: MarkdownLibraryStore) {
        if isVisible {
            close()
        } else {
            show(library: library)
        }
    }

    func show(library: MarkdownLibraryStore) {
        let model = viewModel ?? ChatHUDViewModel(library: library)
        viewModel = model

        let panel = self.panel ?? makePanel(viewModel: model)
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(viewModel: ChatHUDViewModel) -> CribbleChatPanel {
        let initialFrame = NSRect(x: 0, y: 0, width: 380, height: 720)
        let panel = CribbleChatPanel(contentRect: initialFrame)
        panel.setFrameAutosaveName("CribbleChatHUDPanel")

        let root = ChatHUDView(viewModel: viewModel) { [weak panel] in
            panel?.orderOut(nil)
        }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        panel.contentView = visualEffect
        if panel.frame.width < 320 {
            panel.setContentSize(initialFrame.size)
            panel.center()
        }
        return panel
    }
}
