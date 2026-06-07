import AppKit
import XCTest
@testable import Cribble

@MainActor
final class CribbleUITests: XCTestCase {
    
    func testAppSettingsFontScaleLimits() {
        let settings = AppSettings()

        // Reset and check medium preset
        settings.resetFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.medium.scale)

        // Increase steps through the presets in order.
        settings.increaseFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.large.scale)

        settings.increaseFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.xl.scale)

        settings.increaseFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.xxl.scale)

        // Can't go beyond the largest preset.
        settings.increaseFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.xxl.scale)

        // Decrease back.
        settings.decreaseFontSize()
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.xl.scale)

        settings.setFontSize(.small)
        XCTAssertEqual(settings.readerFontScale, ReaderFontSizePreset.small.scale)
    }

    func testCopySelectedDocumentWikiLinkUsesDocumentTitle() {
        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.selectedDocument = MarkdownDocument(
            url: URL(fileURLWithPath: "/tmp/meeting.md"),
            title: "Team Review | June",
            rawMarkdown: "# Team Review | June\n",
            headings: [],
            outboundLinks: []
        )

        NSPasteboard.general.clearContents()
        store.copySelectedDocumentWikiLink()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), #"[[Team Review \| June]]"#)
        XCTAssertEqual(store.statusMessage, #"Copied [[Team Review \| June]]"#)
    }
    
    func testLibraryStoreSearchFiltering() throws {
        let store = MarkdownLibraryStore(includeBundledDemo: false)
        
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

    func testRemovingFolderOnlyRemovesItFromCribble() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        XCTAssertEqual(store.rootURLs, [rootURL.standardizedFileURL])
        XCTAssertNotNil(store.selectedDocument)

        store.removeSelectedFolder()
        await store.waitForLoadToComplete()

        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        XCTAssertTrue(store.rootURLs.isEmpty)
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertNil(store.selectedDocument)
        XCTAssertEqual(defaults.stringArray(forKey: "folderPaths") ?? [], [])
        XCTAssertEqual(defaults.array(forKey: "folderBookmarks") as? [Data] ?? [], [])
        XCTAssertTrue(defaults.dictionary(forKey: "folderDisplayNames")?.isEmpty ?? true)
    }

    func testRestoreIgnoresSavedFilePaths() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

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

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-folder-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        defaults.set([rootURL.path, fileURL.path], forKey: "folderPaths")

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        await store.waitForLoadToComplete()

        XCTAssertEqual(store.rootURLs, [rootURL.standardizedFileURL])
        XCTAssertEqual(defaults.stringArray(forKey: "folderPaths"), [rootURL.standardizedFileURL.path])
    }

    func testImportedFolderDisplayNameDoesNotRenameFolderOnDisk() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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
            .appendingPathComponent("Actual-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "# Note\n".write(to: rootURL.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.setImportedFolderDisplayName("Project Notes", for: rootURL)
        await store.waitForLoadToComplete()

        XCTAssertEqual(store.nodes.first?.name, "Project Notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path))
        XCTAssertEqual(rootURL.lastPathComponent, rootURL.standardizedFileURL.lastPathComponent)
        XCTAssertEqual(
            defaults.dictionary(forKey: "folderDisplayNames")?[rootURL.standardizedFileURL.path] as? String,
            "Project Notes"
        )
    }

    func testReadmeAIUsesSelectedReadmeFolder() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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
            .appendingPathComponent("AIReadme-\(UUID().uuidString)", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "# Root\n".write(to: rootURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "# Child\n".write(to: childURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "# Note\nBody\n".write(to: childURL.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: childURL)

        XCTAssertEqual(store.folderURLForAI(mode: .updateReadme), childURL.standardizedFileURL)
        XCTAssertEqual(store.folderURLForAI(mode: .suggestLinks), rootURL.standardizedFileURL)
        XCTAssertTrue(store.selectedDocument?.isEssentiallyEmptyReadme == true)
    }

    func testRelativeMarkdownLinksNavigateInsideCribble() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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
            .appendingPathComponent("RelativeLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let readmeURL = rootURL.appendingPathComponent("README.md")
        let guideURL = rootURL.appendingPathComponent("Guide File.md")
        try "# Home\n[Guide](Guide%20File.md#intro)\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "# Guide\nBody\n".write(to: guideURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: readmeURL)

        _ = store.handleOpenURL(URL(string: "Guide%20File.md#intro")!)

        XCTAssertEqual(store.selectedDocument?.url.standardizedFileURL, guideURL.standardizedFileURL)
    }

    func testRemoteImagePreferenceRerendersSelectedDocument() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        let oldLoadRemoteImages = defaults.object(forKey: "loadRemoteImages")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defaults.set(false, forKey: "loadRemoteImages")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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

            if let oldLoadRemoteImages {
                defaults.set(oldLoadRemoteImages, forKey: "loadRemoteImages")
            } else {
                defaults.removeObject(forKey: "loadRemoteImages")
            }
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteImage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = rootURL.appendingPathComponent("Note.md")
        try "# Note\n\n![banner](https://example.com/banner.png)\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: noteURL)
        await store.waitForRenderToComplete()

        XCTAssertTrue(store.selectedRenderedMarkdown.contains("[🖼 banner](https://example.com/banner.png)"))
        XCTAssertFalse(store.selectedRenderedMarkdown.contains("![banner](https://example.com/banner.png)"))

        defaults.set(true, forKey: "loadRemoteImages")
        store.rerenderSelectedDocument()
        await store.waitForRenderToComplete()

        XCTAssertTrue(store.selectedRenderedMarkdown.contains("![banner](https://example.com/banner.png)"))
        XCTAssertFalse(store.selectedRenderedMarkdown.contains("[🖼 banner](https://example.com/banner.png)"))
    }

    func testImageHeavyNoteRendersAfterDuplicateTitleIsStripped() async throws {
        let defaults = UserDefaults.standard
        let oldLoadRemoteImages = defaults.object(forKey: "loadRemoteImages")
        defaults.set(false, forKey: "loadRemoteImages")
        defer {
            if let oldLoadRemoteImages {
                defaults.set(oldLoadRemoteImages, forKey: "loadRemoteImages")
            } else {
                defaults.removeObject(forKey: "loadRemoteImages")
            }
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageHeavyNote-\(UUID().uuidString)", isDirectory: true)
        let attachmentsURL = rootURL.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
            0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82
        ])
        try pngData.write(to: rootURL.appendingPathComponent("pic.png"))
        try pngData.write(to: attachmentsURL.appendingPathComponent("attached.png"))

        let noteURL = rootURL.appendingPathComponent("Image Manual Check.md")
        try """
        # Image Manual Check

        Adjacent markdown image:

        ![alt](pic.png)

        Obsidian embed:

        ![[pic.png]]

        Attachment fallback:

        ![attached](attached.png)

        Raw HTML image:

        <img src="pic.png" alt="html pic">

        Remote image should be blocked until enabled:

        ![remote](https://example.com/y.png)
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: noteURL)
        await store.waitForRenderToComplete()

        XCTAssertTrue(store.selectedRenderedMarkdown.contains("Adjacent markdown image:"), store.selectedRenderedMarkdown)
        XCTAssertTrue(store.selectedRenderedMarkdown.contains("![alt](file://"), store.selectedRenderedMarkdown)
        XCTAssertTrue(store.selectedRenderedMarkdown.contains("![pic.png](file://"), store.selectedRenderedMarkdown)
        XCTAssertTrue(store.selectedRenderedMarkdown.contains("![attached](file://"), store.selectedRenderedMarkdown)
        XCTAssertTrue(store.selectedRenderedMarkdown.contains("![html pic](file://"), store.selectedRenderedMarkdown)
        XCTAssertTrue(store.selectedRenderedMarkdown.contains("[🖼 remote](https://example.com/y.png)"), store.selectedRenderedMarkdown)
    }

    func testAddToTasksAnchorsSourceAndDeduplicatesBacklink() async throws {
        let defaults = UserDefaults.standard
        let oldBookmarks = defaults.array(forKey: "folderBookmarks")
        let oldDisplayNames = defaults.dictionary(forKey: "folderDisplayNames")
        let oldFolderPaths = defaults.stringArray(forKey: "folderPaths")
        let oldLegacyPath = defaults.string(forKey: "lastFolderPath")
        defaults.removeObject(forKey: "folderBookmarks")
        defaults.removeObject(forKey: "folderDisplayNames")
        defaults.removeObject(forKey: "folderPaths")
        defaults.removeObject(forKey: "lastFolderPath")
        defer {
            if let oldBookmarks {
                defaults.set(oldBookmarks, forKey: "folderBookmarks")
            } else {
                defaults.removeObject(forKey: "folderBookmarks")
            }

            if let oldDisplayNames {
                defaults.set(oldDisplayNames, forKey: "folderDisplayNames")
            } else {
                defaults.removeObject(forKey: "folderDisplayNames")
            }

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
            .appendingPathComponent("TasksExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("Source.md")
        try "# Source\n\n## Launch\n\n- [ ] Send release notes\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: sourceURL)
        await store.waitForRenderToComplete()

        await store.addTaskToTracker(in: sourceURL, ordinal: 0, exportTo: nil)
        await store.waitForRenderToComplete()
        await store.addTaskToTracker(in: sourceURL, ordinal: 0, exportTo: nil)
        await store.waitForRenderToComplete()

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let anchor = try XCTUnwrap(TaskCheckbox.blockAnchor(in: source.components(separatedBy: "\n")[4]))
        XCTAssertTrue(anchor.hasPrefix("cribble-"))
        XCTAssertFalse(store.selectedRenderedMarkdown.contains("^cribble-"), store.selectedRenderedMarkdown)

        let tasksURL = rootURL.appendingPathComponent("Tasks.md")
        let tasks = try String(contentsOf: tasksURL, encoding: .utf8)
        let backlink = "[[Source#^\(anchor)]]"
        XCTAssertTrue(tasks.contains("- [ ] Send release notes — \(backlink)"), tasks)
        XCTAssertEqual(tasks.components(separatedBy: backlink).count - 1, 1, tasks)
        XCTAssertEqual(store.statusMessage, "Already in Tasks")
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
        
        // Task markers are preserved verbatim so the reader can render them as
        // interactive checkboxes downstream.
        let rawTasks = """
        - [x] Complete task
        - [ ] Pending task
        - [X] Case-insensitive complete
        """
        let preparedTasks = MarkdownDisplayPreprocessor.prepare(rawTasks, documentTitle: "Tasks")
        XCTAssertEqual(preparedTasks, rawTasks)
    }
}
