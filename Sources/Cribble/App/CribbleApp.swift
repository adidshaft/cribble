import AppKit
import SwiftUI

@main
struct CribbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MarkdownLibraryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup("Cribble") {
            ContentView()
                .environmentObject(library)
                .environmentObject(settings)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppIconManager.applyForSystemAppearance()

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
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }
}
