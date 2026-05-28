import AppKit
import SwiftUI

@main
struct CribbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MarkdownLibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var diagnostics = DiagnosticsCenter.shared
    @StateObject private var readingAnnotations = ReadingAnnotationsStore()
    @StateObject private var readingTrail = ReadingTrailStore()
    @StateObject private var semanticIndex = SemanticSearchIndex()

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
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CribbleCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?

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

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsCenter.shared.markCleanTermination()

        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }
}
