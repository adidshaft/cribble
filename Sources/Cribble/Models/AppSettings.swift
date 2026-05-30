import AppKit
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var readerFontScale: Double {
        didSet { UserDefaults.standard.set(readerFontScale, forKey: Keys.readerFontScale) }
    }

    /// App-wide appearance. Defaults to Light per the lighter-UI direction,
    /// while still letting users pick Dark or follow the system.
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Family name of a user-chosen body font, or nil for the system font.
    @Published var readerFontName: String? {
        didSet { UserDefaults.standard.set(readerFontName, forKey: Keys.readerFontName) }
    }

    /// Family name of a user-chosen monospace font, or nil for the system mono.
    @Published var monospaceFontName: String? {
        didSet { UserDefaults.standard.set(monospaceFontName, forKey: Keys.monospaceFontName) }
    }

    @Published var fileSortMode: FileSortMode {
        didSet { UserDefaults.standard.set(fileSortMode.rawValue, forKey: Keys.fileSortMode) }
    }

    @Published var showLinkedFileCards: Bool {
        didSet { UserDefaults.standard.set(showLinkedFileCards, forKey: Keys.showLinkedFileCards) }
    }

    @Published var showOutline: Bool {
        didSet { UserDefaults.standard.set(showOutline, forKey: Keys.showOutline) }
    }

    @Published var isFocusMode: Bool {
        didSet { UserDefaults.standard.set(isFocusMode, forKey: Keys.isFocusMode) }
    }

    @Published var editorApplicationURL: URL? {
        didSet { UserDefaults.standard.set(editorApplicationURL?.path, forKey: Keys.editorApplicationPath) }
    }

    init() {
        let scale = UserDefaults.standard.double(forKey: Keys.readerFontScale)
        // Clamp into the current range so a previously-saved (now out-of-range)
        // value can't leave the reader stuck at a too-large size.
        readerFontScale = scale == 0 ? 1.0 : min(max(scale, 0.55), 1.3)
        appearance = UserDefaults.standard.string(forKey: Keys.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .light
        readerFontName = UserDefaults.standard.string(forKey: Keys.readerFontName).flatMap { $0.isEmpty ? nil : $0 }
        monospaceFontName = UserDefaults.standard.string(forKey: Keys.monospaceFontName).flatMap { $0.isEmpty ? nil : $0 }
        let sortMode = UserDefaults.standard.string(forKey: Keys.fileSortMode).flatMap(FileSortMode.init(rawValue:))
        fileSortMode = sortMode ?? .name
        showLinkedFileCards = UserDefaults.standard.object(forKey: Keys.showLinkedFileCards) as? Bool ?? true
        showOutline = UserDefaults.standard.object(forKey: Keys.showOutline) as? Bool ?? true
        isFocusMode = UserDefaults.standard.object(forKey: Keys.isFocusMode) as? Bool ?? false
        if let path = UserDefaults.standard.string(forKey: Keys.editorApplicationPath), !path.isEmpty {
            editorApplicationURL = URL(fileURLWithPath: path)
        } else {
            editorApplicationURL = nil
        }
    }

    func increaseFontSize() {
        let current = ReaderFontSizePreset.closest(to: readerFontScale)
        guard let index = ReaderFontSizePreset.allCases.firstIndex(of: current),
              index < ReaderFontSizePreset.allCases.index(before: ReaderFontSizePreset.allCases.endIndex)
        else { return }
        readerFontScale = ReaderFontSizePreset.allCases[index + 1].scale
    }

    func decreaseFontSize() {
        let current = ReaderFontSizePreset.closest(to: readerFontScale)
        guard let index = ReaderFontSizePreset.allCases.firstIndex(of: current), index > 0 else {
            return
        }
        readerFontScale = ReaderFontSizePreset.allCases[index - 1].scale
    }

    func resetFontSize() {
        readerFontScale = ReaderFontSizePreset.medium.scale
    }

    func setFontSize(_ preset: ReaderFontSizePreset) {
        readerFontScale = preset.scale
    }

    func chooseEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose Markdown Editor"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        if panel.runModal() == .OK {
            editorApplicationURL = panel.url
        }
    }

    func resetEditor() {
        editorApplicationURL = nil
    }

    private enum Keys {
        static let readerFontScale = "readerFontScale"
        static let fileSortMode = "fileSortMode"
        static let showLinkedFileCards = "showLinkedFileCards"
        static let showOutline = "showOutline"
        static let isFocusMode = "isFocusMode"
        static let editorApplicationPath = "editorApplicationPath"
        static let appearance = "appearance"
        static let readerFontName = "readerFontName"
        static let monospaceFontName = "monospaceFontName"
    }
}

/// Resolves the user's font choices to SwiftUI fonts, falling back to the
/// system font (or system monospace) when no custom font is set or the named
/// font isn't installed.
enum ReaderTypography {
    static func primary(_ name: String?, size: CGFloat) -> Font {
        if let name, !name.isEmpty, NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size)
    }

    static func monospace(_ name: String?, size: CGFloat) -> Font {
        if let name, !name.isEmpty, NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}
