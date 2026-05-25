import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var readerFontScale: Double {
        didSet { UserDefaults.standard.set(readerFontScale, forKey: Keys.readerFontScale) }
    }

    @Published var fileSortMode: FileSortMode {
        didSet { UserDefaults.standard.set(fileSortMode.rawValue, forKey: Keys.fileSortMode) }
    }

    @Published var editorApplicationURL: URL? {
        didSet { UserDefaults.standard.set(editorApplicationURL?.path, forKey: Keys.editorApplicationPath) }
    }

    init() {
        let scale = UserDefaults.standard.double(forKey: Keys.readerFontScale)
        readerFontScale = scale == 0 ? 1.0 : scale
        let sortMode = UserDefaults.standard.string(forKey: Keys.fileSortMode).flatMap(FileSortMode.init(rawValue:))
        fileSortMode = sortMode ?? .name
        if let path = UserDefaults.standard.string(forKey: Keys.editorApplicationPath), !path.isEmpty {
            editorApplicationURL = URL(fileURLWithPath: path)
        } else {
            editorApplicationURL = nil
        }
    }

    func increaseFontSize() {
        readerFontScale = min(1.6, readerFontScale + 0.05)
    }

    func decreaseFontSize() {
        readerFontScale = max(0.75, readerFontScale - 0.05)
    }

    func resetFontSize() {
        readerFontScale = 1.0
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
        static let editorApplicationPath = "editorApplicationPath"
    }
}
