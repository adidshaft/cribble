import XCTest
@testable import Cribble

@MainActor
final class CribbleUITests: XCTestCase {
    
    func testAppSettingsFontScaleLimits() {
        let settings = AppSettings()
        
        // Reset and check medium preset
        settings.resetFontSize()
        XCTAssertEqual(settings.readerFontScale, 1.0)
        
        // Increase multiple times and check scale matches next preset
        settings.increaseFontSize() // to L: 1.15
        XCTAssertEqual(settings.readerFontScale, 1.15)
        
        settings.increaseFontSize() // to XL: 1.35
        XCTAssertEqual(settings.readerFontScale, 1.35)
        
        settings.increaseFontSize() // to XXL: 1.65
        XCTAssertEqual(settings.readerFontScale, 1.65)
        
        // Try to increase beyond XXL (should stay 1.65)
        settings.increaseFontSize()
        XCTAssertEqual(settings.readerFontScale, 1.65)
        
        // Decrease back
        settings.decreaseFontSize() // to XL: 1.35
        XCTAssertEqual(settings.readerFontScale, 1.35)
        
        settings.setFontSize(.small)
        XCTAssertEqual(settings.readerFontScale, 0.9)
    }
    
    func testLibraryStoreSearchFiltering() throws {
        let store = MarkdownLibraryStore()
        
        // Create nodes mock
        let node1 = MarkdownNode(
            id: URL(fileURLWithPath: "/dummy/doc1.md"),
            name: "Apple Note",
            url: URL(fileURLWithPath: "/dummy/doc1.md"),
            kind: .markdown,
            createdAt: nil,
            modifiedAt: nil,
            readmeURL: nil,
            children: []
        )
        let node2 = MarkdownNode(
            id: URL(fileURLWithPath: "/dummy/doc2.md"),
            name: "Banana Note",
            url: URL(fileURLWithPath: "/dummy/doc2.md"),
            kind: .markdown,
            createdAt: nil,
            modifiedAt: nil,
            readmeURL: nil,
            children: []
        )
        
        store.nodes = [node1, node2]
        
        // Initially search text is empty, filteredNodes should match nodes
        store.searchText = ""
        XCTAssertEqual(store.filteredNodes.count, 2)
        
        // Search "Apple"
        store.searchText = "Apple"
        XCTAssertEqual(store.filteredNodes.count, 1)
        XCTAssertEqual(store.filteredNodes.first?.name, "Apple Note")
        
        // Search "Banana" (case-insensitive)
        store.searchText = "banana"
        XCTAssertEqual(store.filteredNodes.count, 1)
        XCTAssertEqual(store.filteredNodes.first?.name, "Banana Note")
        
        // Search something that doesn't exist
        store.searchText = "Cherry"
        XCTAssertTrue(store.filteredNodes.isEmpty)
    }

    func testRemovingFolderOnlyRemovesItFromCribble() throws {
        let defaults = UserDefaults.standard
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldFolderPaths {
                defaults.set(oldFolderPaths, forKey: "folderPaths")
            } else {
                defaults.removeObject(forKey: "folderPaths")
            }

            if let oldLegacyPath {
                defaults.set(oldLegacyPath, forKey: "lastFolderPath")
            } else {
                defaults.removeObject(forKey: "lastFolderPath")
            }
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = rootURL.appendingPathComponent("Note.md")
        try "# Note\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore()
        store.openFolder(rootURL, sortMode: .name)
        XCTAssertEqual(store.rootURLs, [rootURL.standardizedFileURL])
        XCTAssertNotNil(store.selectedDocument)

        store.removeSelectedFolder()

        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        XCTAssertTrue(store.rootURLs.isEmpty)
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertNil(store.selectedDocument)
        XCTAssertEqual(defaults.stringArray(forKey: "folderPaths") ?? [], [])
    }
    
    func testMarkdownDisplayPreprocessorTitleAndTaskHandling() {
        // Strip duplicate document title
        let rawContent = """
        # Test Title
        
        Hello world!
        """
        let prepared = MarkdownDisplayPreprocessor.prepare(rawContent, documentTitle: "Test Title")
        XCTAssertEqual(prepared, "Hello world!")
        
        // Do not strip if title does not match
        let rawContentDifferent = """
        # Another Title
        
        Hello world!
        """
        let preparedDifferent = MarkdownDisplayPreprocessor.prepare(rawContentDifferent, documentTitle: "Test Title")
        XCTAssertEqual(preparedDifferent, "# Another Title\n\nHello world!")
        
        // Task list markdown formatting
        let rawTasks = """
        - [x] Complete task
        - [ ] Pending task
        - [X] Case-insensitive complete
        """
        let preparedTasks = MarkdownDisplayPreprocessor.prepare(rawTasks, documentTitle: "Tasks")
        XCTAssertEqual(preparedTasks, "- ☑ Complete task\n- ☐ Pending task\n- ☑ Case-insensitive complete")
    }
}
