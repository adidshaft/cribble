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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
