import AppKit
import SwiftUI

@MainActor
enum AppIconManager {
    static func applyForSystemAppearance() {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}
