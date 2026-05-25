import AppKit
import SwiftUI

@MainActor
enum AppIconManager {
    static func apply(for colorScheme: ColorScheme) {
        let resourceName = colorScheme == .dark ? "AppIconDark" : "AppIconLight"
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return
        }

        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}
