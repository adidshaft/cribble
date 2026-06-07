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
        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
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

    func testCopySelectedDocumentMarkdownUsesRawMarkdown() {
        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.selectedDocument = MarkdownDocument(
            url: URL(fileURLWithPath: "/tmp/brief.md"),
            title: "Launch Brief",
            rawMarkdown: "# Launch Brief\n\n- [ ] Ship it\n",
            headings: [],
            outboundLinks: []
        )

        NSPasteboard.general.clearContents()
        store.copySelectedDocumentMarkdown()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "# Launch Brief\n\n- [ ] Ship it\n")
        XCTAssertEqual(store.statusMessage, "Copied Markdown for Launch Brief")
    }

    func testCopySelectedDocumentMarkdownLinkUsesTitleAndFileName() {
        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.selectedDocument = MarkdownDocument(
            url: URL(fileURLWithPath: "/tmp/launch brief.md"),
            title: "Launch [Brief]",
            rawMarkdown: "# Launch Brief\n",
            headings: [],
            outboundLinks: []
        )

        NSPasteboard.general.clearContents()
        store.copySelectedDocumentMarkdownLink()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), #"[Launch \[Brief\]](launch%20brief.md)"#)
        XCTAssertEqual(store.statusMessage, "Copied Markdown link for Launch [Brief]")
    }

    func testCopyWikiLinkForURLUsesLoadedMetadata() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarWikiLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = rootURL.appendingPathComponent("meeting.md")
        try "# Better Team Rituals\n\nNotes.\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        NSPasteboard.general.clearContents()
        store.copyWikiLink(for: noteURL)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "[[Better Team Rituals]]")
        XCTAssertEqual(store.statusMessage, "Copied [[Better Team Rituals]]")
    }

    func testCopyMarkdownForURLReadsNoteBody() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarMarkdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = rootURL.appendingPathComponent("brief.md")
        let markdown = "# Project Brief\n\nBody from disk.\n"
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        NSPasteboard.general.clearContents()
        store.copyMarkdown(for: noteURL)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), markdown)
        XCTAssertEqual(store.statusMessage, "Copied Markdown for Project Brief")
    }

    func testCopyMarkdownLinkForURLUsesRelativeEncodedPath() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarMarkdownLink-\(UUID().uuidString)", isDirectory: true)
        let folderURL = rootURL.appendingPathComponent("Team Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = folderURL.appendingPathComponent("launch brief.md")
        try "# Launch Brief\n\nBody.\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        NSPasteboard.general.clearContents()
        store.copyMarkdownLink(for: noteURL)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "[Launch Brief](Team%20Notes/launch%20brief.md)")
        XCTAssertEqual(store.statusMessage, "Copied Markdown link for Launch Brief")
    }

    func testFolderRefreshRecordsDiagnosticsSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "# One\n".write(to: rootURL.appendingPathComponent("One.md"), atomically: true, encoding: .utf8)
        try "# Two\n".write(to: rootURL.appendingPathComponent("Two.md"), atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        let firstSnapshot = DiagnosticsCenter.shared.latestRefreshSnapshot
        XCTAssertEqual(firstSnapshot?.totalDocuments, 2)
        XCTAssertEqual(firstSnapshot?.loadedDocuments, 2)

        store.refresh(sortMode: .name)
        await store.waitForLoadToComplete()

        let secondSnapshot = DiagnosticsCenter.shared.latestRefreshSnapshot
        XCTAssertEqual(secondSnapshot?.totalDocuments, 2)
        XCTAssertEqual(secondSnapshot?.reusedDocuments, 2)
        XCTAssertEqual(secondSnapshot?.loadedDocuments, 0)
        XCTAssertTrue(store.statusMessage?.contains("2 reused") == true)
        XCTAssertTrue(store.statusMessage?.contains("0 loaded") == false)
    }

    func testLibraryStoreSearchFiltering() throws {
        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        
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

    func testSidebarSearchSummaryCountsNestedFileMatches() {
        let root = MarkdownNode(
            id: URL(fileURLWithPath: "/dummy"),
            name: "Root",
            url: URL(fileURLWithPath: "/dummy"),
            kind: .folder,
            createdAt: nil,
            modifiedAt: nil,
            readmeURL: nil,
            children: [
                MarkdownNode(
                    id: URL(fileURLWithPath: "/dummy/one.md"),
                    name: "One",
                    url: URL(fileURLWithPath: "/dummy/one.md"),
                    kind: .markdown,
                    createdAt: nil,
                    modifiedAt: nil,
                    readmeURL: nil,
                    children: []
                ),
                MarkdownNode(
                    id: URL(fileURLWithPath: "/dummy/nested"),
                    name: "Nested",
                    url: URL(fileURLWithPath: "/dummy/nested"),
                    kind: .folder,
                    createdAt: nil,
                    modifiedAt: nil,
                    readmeURL: nil,
                    children: [
                        MarkdownNode(
                            id: URL(fileURLWithPath: "/dummy/nested/two.md"),
                            name: "Two",
                            url: URL(fileURLWithPath: "/dummy/nested/two.md"),
                            kind: .markdown,
                            createdAt: nil,
                            modifiedAt: nil,
                            readmeURL: nil,
                            children: []
                        )
                    ]
                )
            ]
        )

        let summary = SidebarSearchSummary(
            query: " project ",
            filteredNodes: [root],
            semanticResultCount: 3
        )

        XCTAssertEqual(summary?.query, "project")
        XCTAssertEqual(summary?.fileMatchCount, 2)
        XCTAssertEqual(summary?.semanticResultCount, 3)
        XCTAssertEqual(summary?.title, "2 visible file results")
        XCTAssertEqual(summary?.detail, "3 related results")
        XCTAssertNil(SidebarSearchSummary(query: " ", filteredNodes: [root], semanticResultCount: 0))
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

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
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

    func testRootFolderShortcutsOpenReadmeLanding() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderShortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let readmeURL = rootURL.appendingPathComponent("README.md")
        try "# Home\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "# Other\n".write(to: rootURL.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()
        store.setImportedFolderDisplayName("Client Notes", for: rootURL)
        await store.waitForLoadToComplete()

        let shortcut = try XCTUnwrap(store.rootFolderShortcuts.first)
        XCTAssertEqual(shortcut.title, "Client Notes")
        XCTAssertEqual(shortcut.documentCount, 2)

        store.openRootLanding(rootURL, sortMode: .name)

        XCTAssertEqual(store.selectedURL?.standardizedFileURL, readmeURL.standardizedFileURL)
        XCTAssertEqual(store.statusMessage, "Opened Client Notes")
    }

    func testRootFolderLandingReportsEmptyMarkdownFolder() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptyShortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        store.openRootLanding(rootURL, sortMode: .name)

        XCTAssertNil(store.selectedURL)
        XCTAssertEqual(store.statusMessage, "No Markdown files in \(rootURL.lastPathComponent)")
    }

    func testRecentDocumentShortcutsUseHistoryOrderAndSkipStaleEntries() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentShortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstURL = rootURL.appendingPathComponent("First.md")
        let secondURL = rootURL.appendingPathComponent("Second.md")
        let staleURL = rootURL.appendingPathComponent("Missing.md")
        try "# First\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# Second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        store.select(url: firstURL)
        store.select(url: secondURL)
        store.history.append(staleURL)
        store.select(url: firstURL)

        let shortcuts = store.recentDocumentShortcuts

        XCTAssertEqual(shortcuts.map(\.url), [
            firstURL.standardizedFileURL,
            secondURL.standardizedFileURL
        ])
        XCTAssertEqual(shortcuts.first?.title, "First")
        XCTAssertEqual(shortcuts.first?.subtitle, "First.md")
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

        store.openTasksFile()
        XCTAssertEqual(store.selectedURL?.standardizedFileURL, tasksURL.standardizedFileURL)
        XCTAssertEqual(store.statusMessage, "Opened Tasks")
    }

    func testOpenTasksCreatesAndSelectsTasksFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasksCreate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        let tasksURL = rootURL.appendingPathComponent("Tasks.md").standardizedFileURL
        store.openTasksFile()
        await store.waitForLoadToComplete()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tasksURL.path))
        XCTAssertEqual(store.selectedURL?.standardizedFileURL, tasksURL)
        XCTAssertEqual(store.selectedDocument?.url.standardizedFileURL, tasksURL)
        XCTAssertEqual(store.statusMessage, "Created Tasks.md")
    }

    func testDemoHelpGuideTargetsExistInBundledNotes() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let demoRoot = projectRoot.appendingPathComponent("Sources/Cribble/Resources/DemoNotes", isDirectory: true)

        let helpGuideFiles = [
            "Cribble AI.md",
            "Workflow Playbook.md",
            "Tasks and Intelligence.md",
            "Research Review.md",
            "Team Extension Kit.md",
            "Extensions and Remote Intelligence.md"
        ]

        for fileName in helpGuideFiles {
            let url = demoRoot.appendingPathComponent(fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(fileName) should be bundled for Help menu onboarding")
        }
    }

    func testCribbleAIGuideNamesModelDataBoundaries() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guideURL = projectRoot.appendingPathComponent("Sources/Cribble/Resources/DemoNotes/Cribble AI.md")

        let guide = try String(contentsOf: guideURL, encoding: .utf8)
        XCTAssertTrue(guide.contains("On-device"))
        XCTAssertTrue(guide.contains("keep notes on this Mac"))
        XCTAssertTrue(guide.contains("Claude or Codex"))
        XCTAssertTrue(guide.contains("note context leaves the Mac"))
        XCTAssertTrue(guide.contains("signed-in command-line tool"))
    }

    func testDemoNotesUseLocalFirstAICopy() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let demoRoot = projectRoot.appendingPathComponent("Sources/Cribble/Resources/DemoNotes", isDirectory: true)

        let home = try String(contentsOf: demoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(home.contains("local-first AI"))
        XCTAssertTrue(home.contains("local-first intelligence"))
        XCTAssertTrue(home.contains("keep notes on this Mac"))
        XCTAssertTrue(home.contains("renderer aliases, import-lane"))
        XCTAssertTrue(home.contains("extension profiles get a review sheet"))
        XCTAssertFalse(home.contains("No cloud, no account"))

        let gettingStarted = try String(contentsOf: demoRoot.appendingPathComponent("Getting Started.md"), encoding: .utf8)
        XCTAssertTrue(gettingStarted.contains("local-first chat"))

        let tasks = try String(contentsOf: demoRoot.appendingPathComponent("Tasks and Intelligence.md"), encoding: .utf8)
        XCTAssertTrue(tasks.contains("trusted remote runners are opt-in"))
        XCTAssertTrue(tasks.contains("reviewed before note context"))

        let featureTour = try String(contentsOf: demoRoot.appendingPathComponent("Feature Tour.md"), encoding: .utf8)
        XCTAssertTrue(featureTour.contains("pick the model boundary you trust"))
        XCTAssertTrue(featureTour.contains("clearly labeled Claude/Codex CLI choice"))

        let cribbleAI = try String(contentsOf: demoRoot.appendingPathComponent("Cribble AI.md"), encoding: .utf8)
        XCTAssertTrue(cribbleAI.contains("pick the model boundary you trust"))

        let extensions = try String(contentsOf: demoRoot.appendingPathComponent("Extensions and Remote Intelligence.md"), encoding: .utf8)
        XCTAssertTrue(extensions.contains("data-only"))
        XCTAssertTrue(extensions.contains("signed/revocable model"))
        XCTAssertTrue(extensions.contains("Chat HUD command surface"))

        let workflow = try String(contentsOf: demoRoot.appendingPathComponent("Workflow Playbook.md"), encoding: .utf8)
        XCTAssertTrue(workflow.contains("import-lane declaration"))
    }

    func testWelcomeStarterChecklistGuidesCoreProductTour() {
        let checklist = WelcomeStarterChecklist.markdown

        XCTAssertTrue(checklist.contains("Cribble Starter Checklist"))
        XCTAssertTrue(checklist.contains("[[Getting Started]]"))
        XCTAssertTrue(checklist.contains("[[Cribble AI]]"))
        XCTAssertTrue(checklist.contains("model boundary"))
        XCTAssertTrue(checklist.contains("Tasks.md"))
        XCTAssertTrue(checklist.contains("[[Workflow Playbook]]"))
        XCTAssertTrue(checklist.contains("[[Team Extension Kit]]"))
        XCTAssertTrue(checklist.contains("Copy Proposal"))
        XCTAssertTrue(checklist.contains("read-only, least-access, and native SwiftUI"))
        XCTAssertTrue(checklist.contains("VPS or remote runner"))
    }

    func testImportLaneSetupReviewKeepsExecutionBoundariesClear() {
        let review = ImportLaneSetupReview.markdown

        XCTAssertTrue(review.contains("Import lane setup review"))
        XCTAssertTrue(review.contains("declarative manifest data only"))
        XCTAssertTrue(review.contains("no scripts, binaries, network calls, or converters run"))
        XCTAssertTrue(review.contains("only user-selected files"))
        XCTAssertTrue(review.contains("preview/review/cancel"))
        XCTAssertTrue(review.contains("never place tokens"))
        XCTAssertTrue(review.contains("native SwiftUI"))
        XCTAssertTrue(review.contains("disabling the extension removes its import lane"))
        XCTAssertTrue(review.contains("Copy Proposal"))
    }

    func testNewNoteProposalUsesReviewFlowAndAppliesUniqueFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewNote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "# Existing\n".write(to: rootURL.appendingPathComponent("Untitled.md"), atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        store.proposeBlankNote()

        let pending = try XCTUnwrap(store.pendingDiff)
        XCTAssertEqual(pending.files.first?.oldPath, "/dev/null")
        XCTAssertEqual(pending.files.first?.newPath, "Untitled 2.md")
        XCTAssertEqual(store.statusMessage, "Review the new note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Untitled 2.md").path))

        store.applyPendingDiff()
        await store.waitForLoadToComplete()

        let createdURL = rootURL.appendingPathComponent("Untitled 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(try String(contentsOf: createdURL, encoding: .utf8), "# Untitled\n")
        XCTAssertEqual(store.statusMessage, "Created Untitled 2.md")
    }

    func testUnresolvedCreateUsesReviewFlowAndOpensExistingFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingNote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        store.proposeDocument(named: "Missing Idea", in: rootURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Missing Idea.md").path))
        let pending = try XCTUnwrap(store.pendingDiff)
        XCTAssertEqual(pending.files.first?.oldPath, "/dev/null")
        XCTAssertEqual(pending.files.first?.newPath, "Missing Idea.md")
        XCTAssertEqual(store.statusMessage, "Review Missing Idea.md")

        store.applyPendingDiff()
        await store.waitForLoadToComplete()

        let createdURL = rootURL.appendingPathComponent("Missing Idea.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(try String(contentsOf: createdURL, encoding: .utf8), "# Missing Idea\n")
        XCTAssertEqual(store.statusMessage, "Created Missing Idea.md")

        store.selectedUnresolvedTarget = UnresolvedTarget(targetName: "Missing Idea", folderURL: rootURL)
        store.proposeDocument(named: "Missing Idea", in: rootURL)

        XCTAssertNil(store.pendingDiff)
        XCTAssertNil(store.selectedUnresolvedTarget)
        XCTAssertEqual(store.selectedDocument?.url.standardizedFileURL, createdURL.standardizedFileURL)
        XCTAssertEqual(store.statusMessage, "Missing Idea.md already exists — opening it")
    }

    func testTodayNoteProposalUsesReviewFlowAndNestedDailyFolder() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayNote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        store.openTodayNote(date: date, calendar: calendar)

        let pending = try XCTUnwrap(store.pendingDiff)
        XCTAssertEqual(pending.files.first?.oldPath, "/dev/null")
        XCTAssertEqual(pending.files.first?.newPath, "Daily/2026-06-08.md")
        XCTAssertEqual(store.statusMessage, "Review today's note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Daily/2026-06-08.md").path))

        store.applyPendingDiff()
        await store.waitForLoadToComplete()

        let createdURL = rootURL.appendingPathComponent("Daily/2026-06-08.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(try String(contentsOf: createdURL, encoding: .utf8), "# 2026-06-08\n\n## Notes\n")
        XCTAssertEqual(store.statusMessage, "Created Daily/2026-06-08.md")
    }

    func testTodayNoteOpensExistingDailyNote() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayExisting-\(UUID().uuidString)", isDirectory: true)
        let dailyURL = rootURL.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let noteURL = dailyURL.appendingPathComponent("2026-06-08.md")
        try "# Existing Today\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        store.openTodayNote(date: date, calendar: calendar)

        XCTAssertNil(store.pendingDiff)
        XCTAssertEqual(store.selectedURL?.standardizedFileURL, noteURL.standardizedFileURL)
        XCTAssertEqual(store.selectedDocument?.url.standardizedFileURL, noteURL.standardizedFileURL)
        XCTAssertEqual(store.statusMessage, "Opened Today")
    }

    func testTaskExternalExportStatusNamesTasksAndDestination() {
        XCTAssertEqual(
            TaskTrackerStatus.externalExportMessage(target: .reminders, addedToTasks: true),
            "Added to Tasks and Reminders"
        )
        XCTAssertEqual(
            TaskTrackerStatus.externalExportMessage(target: .calendar, addedToTasks: true),
            "Added to Tasks and Calendar"
        )
        XCTAssertEqual(
            TaskTrackerStatus.externalExportMessage(target: .reminders, addedToTasks: false),
            "Already in Tasks; added to Reminders"
        )
    }

    func testOpenTasksReportsNameCollisionWithDirectory() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasksDirectoryCollision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let tasksURL = rootURL.appendingPathComponent("Tasks.md", isDirectory: true)
        try FileManager.default.createDirectory(at: tasksURL, withIntermediateDirectories: true)

        let store = MarkdownLibraryStore(includeBundledDemo: false)
        store.openFolder(rootURL, sortMode: .name)
        await store.waitForLoadToComplete()

        store.openTasksFile()

        XCTAssertTrue(store.errorMessage?.contains("folder already uses that name") == true)
        XCTAssertNotEqual(store.statusMessage, "Opened Tasks")
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
