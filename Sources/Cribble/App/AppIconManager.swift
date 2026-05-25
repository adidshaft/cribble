import AppKit
import SwiftUI

@MainActor
enum AppIconManager {
    static func applyForSystemAppearance() {
        let resourceName = isSystemDarkMode ? "AppIconDark" : "AppIconLight"
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return
        }

        image.isTemplate = false
        NSApp.applicationIconImage = image
    }

    private static var isSystemDarkMode: Bool {
        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua
    }
}
