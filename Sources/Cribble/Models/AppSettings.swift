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

    @Published var showLinkedFileCards: Bool {
        didSet { UserDefaults.standard.set(showLinkedFileCards, forKey: Keys.showLinkedFileCards) }
    }

    @Published var editorApplicationURL: URL? {
        didSet { UserDefaults.standard.set(editorApplicationURL?.path, forKey: Keys.editorApplicationPath) }
    }

    init() {
        let scale = UserDefaults.standard.double(forKey: Keys.readerFontScale)
        readerFontScale = scale == 0 ? 1.0 : scale
        let sortMode = UserDefaults.standard.string(forKey: Keys.fileSortMode).flatMap(FileSortMode.init(rawValue:))
        fileSortMode = sortMode ?? .name
        showLinkedFileCards = UserDefaults.standard.object(forKey: Keys.showLinkedFileCards) as? Bool ?? true
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
        static let editorApplicationPath = "editorApplicationPath"
    }
}
