import AppKit
import SwiftUI

/// Floating, non-activating HUD panel that hosts the Local Chat interface above
/// the main window (and other apps). Translucent dark "hudWindow" backdrop.
final class CribbleChatPanel: NSPanel {
    init(contentRect: NSRect) {
        // Borderless (no titlebar / "top bar") — the SwiftUI content owns all
        // chrome. Still resizable from the edges and movable by its background.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable],
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

/// Where the chat is currently shown.
enum ChatHUDPresentation {
    /// The floating panel above Cribble's window.
    case floating
    /// A popover hanging off the menu-bar (top bar) item.
    case menuBar
}

/// Owns the single chat view model and its two presentations — the floating
/// panel and the menu-bar popover — plus the purchase gate. SwiftUI views stay
/// declarative; lifecycle lives here.
@MainActor
final class ChatHUDController {
    static let shared = ChatHUDController()

    private var panel: CribbleChatPanel?
    private var popover: NSPopover?
    private var viewModel: ChatHUDViewModel?

    private weak var library: MarkdownLibraryStore?
    private weak var entitlement: LLMEntitlementStore?
    private var onLocked: (() -> Void)?
    private weak var statusButton: NSStatusBarButton?

    private init() {}

    /// Called from the main view once the environment is available so the
    /// controller can build the view model and honor the purchase gate.
    func configure(
        library: MarkdownLibraryStore,
        entitlement: LLMEntitlementStore,
        onLocked: @escaping () -> Void
    ) {
        self.library = library
        self.entitlement = entitlement
        self.onLocked = onLocked
    }

    /// Registered by the app delegate so the popover can anchor to the menu bar.
    func registerStatusButton(_ button: NSStatusBarButton) {
        statusButton = button
    }

    // MARK: - Entry points

    /// Toolbar / menu / ⌘C: toggle the floating panel.
    func toggleFloating() {
        guard gatePassed() else { return }
        if panel?.isVisible == true {
            close()
        } else {
            presentFloating()
        }
    }

    /// Menu-bar item click: toggle the popover.
    func handleStatusItemClick() {
        guard gatePassed() else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            presentMenuBar()
        }
    }

    /// Flip between the floating panel and the menu-bar popover (the ^ / v
    /// buttons in the HUD header).
    func toggleMode() {
        if panel?.isVisible == true {
            presentMenuBar()
        } else {
            presentFloating()
        }
    }

    func close() {
        panel?.orderOut(nil)
        popover?.performClose(nil)
    }

    // MARK: - Presentations

    private func presentFloating() {
        guard let vm = ensureViewModel() else { return }
        popover?.performClose(nil)
        let panel = self.panel ?? makePanel(viewModel: vm)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func presentMenuBar() {
        guard let vm = ensureViewModel(), let button = statusButton else {
            // No menu-bar anchor available — fall back to the panel.
            presentFloating()
            return
        }
        panel?.orderOut(nil)

        let popover = self.popover ?? makePopover(viewModel: vm)
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - Builders

    private func gatePassed() -> Bool {
        if entitlement?.isUnlocked ?? true { return true }
        onLocked?()
        return false
    }

    private func ensureViewModel() -> ChatHUDViewModel? {
        if let viewModel { return viewModel }
        guard let library else { return nil }
        let vm = ChatHUDViewModel(library: library)
        viewModel = vm
        return vm
    }

    private func makePanel(viewModel: ChatHUDViewModel) -> CribbleChatPanel {
        let initialFrame = NSRect(x: 0, y: 0, width: 380, height: 660)
        let panel = CribbleChatPanel(contentRect: initialFrame)
        panel.setFrameAutosaveName("CribbleChatHUDPanel")

        let root = ChatHUDView(
            viewModel: viewModel,
            presentation: .floating,
            onClose: { [weak self] in self?.close() },
            onToggleMode: { [weak self] in self?.toggleMode() }
        )

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

    private func makePopover(viewModel: ChatHUDViewModel) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 560)
        let root = ChatHUDView(
            viewModel: viewModel,
            presentation: .menuBar,
            onClose: { [weak self] in self?.popover?.performClose(nil) },
            onToggleMode: { [weak self] in self?.toggleMode() }
        )
        popover.contentViewController = NSHostingController(rootView: root)
        return popover
    }
}
