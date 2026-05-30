import AppKit
import SwiftUI

@main
struct CribbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = AppUpdater.shared
    @StateObject private var library = MarkdownLibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var diagnostics = DiagnosticsCenter.shared
    @StateObject private var readingAnnotations = ReadingAnnotationsStore()
    @StateObject private var readingTrail = ReadingTrailStore()
    @StateObject private var semanticIndex = SemanticSearchIndex()
    @StateObject private var llmEntitlement = LLMEntitlementStore()

    init() {
        // Runs at the very top of App.main(), before SwiftUI evaluates the
        // @StateObject autoclosures above. The crash on other machines was
        // MarkdownLibraryStore()'s init touching a SwiftPM resource bundle
        // before AppDelegate.init had installed the redirect hook. Installing
        // it here covers that window (and protects Textual's own
        // Bundle.module resources, which are loaded during rendering).
        SPMBundleAccessorFix.ensureInstalled()
    }

    var body: some Scene {
        WindowGroup("Cribble: Markdown Knowledge Base Manager") {
            ContentView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(diagnostics)
                .environmentObject(readingAnnotations)
                .environmentObject(readingTrail)
                .environmentObject(semanticIndex)
                .environmentObject(llmEntitlement)
                .frame(minWidth: 380, minHeight: 480)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .commands {
            CribbleCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?

    override init() {
        SPMBundleAccessorFix.ensureInstalled()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SPMBundleAccessorFix.ensureInstalled()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        AppIconManager.applyForSystemAppearance()
        DiagnosticsCenter.shared.markLaunch()
        installStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.installCheckForUpdatesMenuItem()
        }

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppIconManager.applyForSystemAppearance()
            }
        }
    }

    private func installCheckForUpdatesMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first(where: { $0.title.hasPrefix("Cribble") })?.submenu,
              !appMenu.items.contains(where: { $0.title == "Check for Updates..." })
        else { return }

        let item = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        item.target = self

        let insertionIndex = min(1, appMenu.items.count)
        appMenu.insertItem(item, at: insertionIndex)
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    /// Adds a menu-bar (top bar) item so the AI chat can be opened from anywhere
    /// without bringing the main window forward first. The actual open is routed
    /// through the main view so the purchase gate is still honored.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "bubble.left.and.text.bubble.right",
                accessibilityDescription: "Cribble AI"
            )
            image?.isTemplate = true
            button.image = image
            button.action = #selector(toggleChatFromStatusItem)
            button.target = self
            button.toolTip = "Cribble AI chat"
            ChatHUDController.shared.registerStatusButton(button)
        }
        statusItem = item
    }

    @objc private func toggleChatFromStatusItem() {
        // Activate first so the popover/panel can show even when another app is
        // frontmost; the controller honors the purchase gate.
        NSApp.activate(ignoringOtherApps: true)
        ChatHUDController.shared.handleStatusItemClick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        DiagnosticsCenter.shared.markCleanTermination()

        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }
}
