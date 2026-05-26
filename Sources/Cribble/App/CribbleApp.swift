import AppKit
import SwiftUI

@main
struct CribbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MarkdownLibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var diagnostics = DiagnosticsCenter.shared

    var body: some Scene {
        WindowGroup("Cribble: Markdown Knowledge Base Manager") {
            ContentView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(diagnostics)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
