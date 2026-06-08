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

    func testSidebarEmptySearchHintGuidesSemanticAndIntelligenceRecovery() {
        let related = SidebarEmptySearchHint(semanticResultCount: 2, hasFolders: true)
        XCTAssertEqual(related.description, "No file names matched, but related results are shown above.")
        XCTAssertFalse(related.showsIntelligenceAction)

        let indexable = SidebarEmptySearchHint(semanticResultCount: 0, hasFolders: true)
        XCTAssertEqual(indexable.description, "No file names or related notes matched. Project Intelligence can index this folder for deeper search.")
        XCTAssertTrue(indexable.showsIntelligenceAction)

        let noFolder = SidebarEmptySearchHint(semanticResultCount: 0, hasFolders: false)
        XCTAssertEqual(noFolder.description, "No file names matched this search.")
        XCTAssertFalse(noFolder.showsIntelligenceAction)
    }

    func testSidebarNoMatchEmptyStateOffersProjectIntelligenceRecovery() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/SidebarView.swift")
        let sidebar = try String(contentsOf: sidebarURL, encoding: .utf8)

        XCTAssertTrue(sidebar.contains("SidebarEmptySearchHint("))
        XCTAssertTrue(sidebar.contains("emptySearchHint.showsIntelligenceAction"))
        XCTAssertTrue(sidebar.contains("Label(\"Open Project Intelligence\", systemImage: \"brain\")"))
    }

    func testReadingTrailEmptyStateOffersWorkflowRecovery() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let trailURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ReadingTrailPanel.swift")
        let trail = try String(contentsOf: trailURL, encoding: .utf8)

        XCTAssertTrue(trail.contains("@EnvironmentObject private var settings: AppSettings"))
        XCTAssertTrue(trail.contains("Workflow Playbook.md"))
        XCTAssertTrue(trail.contains("Label(\"Workflow Guide\", systemImage: \"book.pages\")"))
        XCTAssertTrue(trail.contains("library.proposeBlankNote()"))
        XCTAssertTrue(trail.contains("Label(\"New Note\", systemImage: \"doc.badge.plus\")"))
        XCTAssertTrue(trail.contains("Copy Trail Summary"))
        XCTAssertTrue(trail.contains("NSPasteboard.general.setString(note.content"))
        XCTAssertTrue(trail.contains("Copy this trail as Markdown without creating a note"))
        XCTAssertTrue(trail.contains("Copied reading trail summary"))
        XCTAssertTrue(trail.contains("Open notes, follow wiki links, and collect highlights"))
    }

    func testUnresolvedTargetCanCopyMissingWikiLink() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let unresolvedURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/UnresolvedTargetView.swift")
        let unresolved = try String(contentsOf: unresolvedURL, encoding: .utf8)

        XCTAssertTrue(unresolved.contains("import AppKit"))
        XCTAssertTrue(unresolved.contains("copyMissingWikiLink()"))
        XCTAssertTrue(unresolved.contains("Label(copiedWikiLink ? \"Copied Link\" : \"Copy Wiki Link\""))
        XCTAssertTrue(unresolved.contains("NSPasteboard.general.setString(\"[[\\(target.targetName)]]\""))
        XCTAssertTrue(unresolved.contains("library.statusMessage = \"Copied [[\\(target.targetName)]]\""))
    }

    func testPathfinderSheetCanCopySummary() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pathfinderURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/PathfinderSheet.swift")
        let pathfinder = try String(contentsOf: pathfinderURL, encoding: .utf8)

        XCTAssertTrue(pathfinder.contains("import AppKit"))
        XCTAssertTrue(pathfinder.contains("copySummary()"))
        XCTAssertTrue(pathfinder.contains("Label(copiedSummary ? \"Copied Summary\" : \"Copy Summary\""))
        XCTAssertTrue(pathfinder.contains("PathfinderHandoffSummary.markdown("))
        XCTAssertTrue(pathfinder.contains("library.statusMessage = \"Copied Pathfinder summary\""))
    }

    func testDiffPreviewSheetCanCopyPatchForReview() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let diffSheetURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/DiffPreviewSheet.swift")
        let diffSheet = try String(contentsOf: diffSheetURL, encoding: .utf8)

        XCTAssertTrue(diffSheet.contains("import AppKit"))
        XCTAssertTrue(diffSheet.contains("Label(copiedDiff ? \"Copied Diff\" : \"Copy Diff\""))
        XCTAssertTrue(diffSheet.contains("UnifiedDiffRenderer.render(diff)"))
        XCTAssertTrue(diffSheet.contains("Copy the proposed patch for issue, PR, or teammate review before applying"))
    }

    func testDiagnosticsSheetCanCopyNextActionsOnly() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let diagnosticsURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/DiagnosticsReportSheet.swift")
        let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)

        XCTAssertTrue(diagnostics.contains("Label(\"Copy Next Actions\", systemImage: \"checklist\")"))
        XCTAssertTrue(diagnostics.contains(".disabled(actionableNextActions.isEmpty)"))
        XCTAssertTrue(diagnostics.contains("NSPasteboard.general.setString(actionable.map { \"- \\($0)\" }.joined(separator: \"\\n\")"))
        XCTAssertTrue(diagnostics.contains("Copy only the actionable diagnostics checklist"))
    }

    func testOutlineEmptyStateCanCopyHeadingStarter() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outlineURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/OutlineView.swift")
        let outline = try String(contentsOf: outlineURL, encoding: .utf8)

        XCTAssertTrue(outline.contains("import AppKit"))
        XCTAssertTrue(outline.contains("Label(\"Copy Heading Starter\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(outline.contains("copyHeadingStarter()"))
        XCTAssertTrue(outline.contains("NSPasteboard.general.setString(\"## Next section\\n\\nStart writing here.\""))
        XCTAssertTrue(outline.contains("library.statusMessage = \"Copied heading starter\""))
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
            "Decision Log.md",
            "Team Extension Kit.md",
            "Extension Contribution Guide.md",
            "Extensions and Remote Intelligence.md"
        ]

        for fileName in helpGuideFiles {
            let url = demoRoot.appendingPathComponent(fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(fileName) should be bundled for Help menu onboarding")
        }
    }

    func testWelcomeStartGridIncludesContributorPath() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readerViewURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ReaderView.swift")
        let readerView = try String(contentsOf: readerViewURL, encoding: .utf8)

        XCTAssertTrue(readerView.contains("demoStartButton(\"Contribute\""))
        XCTAssertTrue(readerView.contains("Extension Contribution Guide.md"))
        XCTAssertTrue(readerView.contains("person.crop.circle.badge.plus"))
    }

    func testWelcomeLaunchpadIncludesProjectTaskLane() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readerViewURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ReaderView.swift")
        let readerView = try String(contentsOf: readerViewURL, encoding: .utf8)

        XCTAssertTrue(readerView.contains("library.openTasksFile()"))
        XCTAssertTrue(readerView.contains("Label(\"Tasks\", systemImage: \"checklist.checked\")"))
        XCTAssertTrue(readerView.contains("Open or create Tasks.md for the current folder"))
    }

    func testChatEmptyStateSurfacesExtensionContributionLane() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hudURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ChatHUD/ChatHUDView.swift")
        let hud = try String(contentsOf: hudURL, encoding: .utf8)
        let viewModelURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ChatHUD/ChatHUDViewModel.swift")
        let viewModel = try String(contentsOf: viewModelURL, encoding: .utf8)

        XCTAssertTrue(hud.contains("extensionLaneHint"))
        XCTAssertTrue(hud.contains("puzzlepiece.extension"))
        XCTAssertTrue(hud.contains("ChatHUDViewModel.extensionLaneSummary"))
        XCTAssertTrue(viewModel.contains("Extension Contribution Guide"))
        XCTAssertTrue(hud.contains("Extension manifests can add slash commands"))
    }

    func testSidebarEmptyStateOffersDemoTourAndTaskLane() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/SidebarView.swift")
        let sidebar = try String(contentsOf: sidebarURL, encoding: .utf8)

        XCTAssertTrue(sidebar.contains("library.openDemoLibrary(sortMode: settings.fileSortMode)"))
        XCTAssertTrue(sidebar.contains("Label(\"Open Demo Tour\", systemImage: \"sparkles\")"))
        XCTAssertTrue(sidebar.contains("library.openTasksFile()"))
        XCTAssertTrue(sidebar.contains("Label(\"Tasks\", systemImage: \"checklist.checked\")"))
    }

    func testShortcutPopoverSurfacesHelpRecoveryPaths() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readerViewURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ReaderView.swift")
        let readerView = try String(contentsOf: readerViewURL, encoding: .utf8)

        XCTAssertTrue(readerView.contains("shortcutSection(\"Help Menu\""))
        XCTAssertTrue(readerView.contains("Open or reset DemoNotes"))
        XCTAssertTrue(readerView.contains("contribution and remote intelligence guides"))
        XCTAssertTrue(readerView.contains("starter, research, decision, import, and runner reviews"))
        XCTAssertTrue(readerView.contains("Copy diagnostics / report issue"))
        XCTAssertTrue(readerView.contains("Copy Trail Summary for a zero-file handoff"))
    }

    func testHelpMenuGroupsGuidesTemplatesAndDiagnostics() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let commandsURL = projectRoot.appendingPathComponent("Sources/Cribble/App/CribbleCommands.swift")
        let commands = try String(contentsOf: commandsURL, encoding: .utf8)

        XCTAssertLessThan(index(of: "Button(\"Open DemoNotes Tour\"", in: commands), index(of: "Button(\"Reset DemoNotes Tour\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Reset DemoNotes Tour\"", in: commands), index(of: "Button(\"Open Cribble AI Guide\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Open Remote Intelligence Guide\"", in: commands), index(of: "Button(\"Open Extension Settings\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Open Extension Settings\"", in: commands), index(of: "Button(\"Copy Extension Proposal\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Copy Remote Runner Setup Review\"", in: commands), index(of: "Button(\"Copy Import Lane Setup Review\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Copy Import Lane Setup Review\"", in: commands), index(of: "Button(\"Copy Product Readiness Checkpoint\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Copy Product Readiness Checkpoint\"", in: commands), index(of: "Button(\"Copy Reading Trail Summary\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Copy Reading Trail Summary\"", in: commands), index(of: "Button(\"Copy Starter Checklist\"", in: commands))
        XCTAssertLessThan(index(of: "Button(\"Copy Starter Checklist\"", in: commands), index(of: "Button(\"Show Diagnostic Report\"", in: commands))
        XCTAssertTrue(commands.contains("@FocusedValue(\\.copyReadingTrailSummaryAction)"))
        XCTAssertTrue(commands.contains("CopyReadingTrailSummaryActionKey"))
        XCTAssertLessThan(index(of: "Button(\"Reveal Latest Crash Report\"", in: commands), index(of: "Button(\"Report Issue on GitHub\"", in: commands))
    }

    func testExtensionSettingsLinksToContributionGuide() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/SettingsView.swift")
        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        let extensionSettings = String(settings[try XCTUnwrap(settings.range(of: "Section(\"Extensions\")")).lowerBound...])

        XCTAssertLessThan(index(of: "Button(\"Open Kit\"", in: extensionSettings), index(of: "Button(\"Contribution Guide\"", in: extensionSettings))
        XCTAssertLessThan(index(of: "Button(\"Contribution Guide\"", in: extensionSettings), index(of: "Button(\"Remote Guide\"", in: extensionSettings))
        XCTAssertTrue(settings.contains("Extension Contribution Guide.md"))
        XCTAssertTrue(settings.contains("read-only-first contribution guide"))
        XCTAssertTrue(settings.contains("onOpenContributionGuide"))
        XCTAssertTrue(settings.contains("Open the read-only-first contribution guide before writing a new extension"))
        XCTAssertTrue(settings.contains("Button(\"Reveal\", action: revealUserExtensionsFolder)"))
        XCTAssertTrue(settings.contains("Revealed user extensions folder"))
        XCTAssertTrue(settings.contains("revealExtensionManifest(installed)"))
        XCTAssertTrue(settings.contains("Revealed \\(installed.manifest.name) manifest"))
        XCTAssertTrue(settings.contains("Write a starter manifest plus README review checklist"))
        XCTAssertTrue(settings.contains("New examples include a local README checklist"))
        XCTAssertTrue(settings.contains("Created \\(folderName) with README checklist"))
        XCTAssertTrue(settings.contains("Created project example \\(folderName) with README checklist"))
        XCTAssertTrue(settings.contains("read-only API v1, least permission, previewed writes, Keychain secrets, native SwiftUI"))
        XCTAssertTrue(settings.contains("setExtensionEnabled(enabled, for: installed)"))
        XCTAssertTrue(settings.contains("\"\\(enabled ? \"Enabled\" : \"Disabled\") \\(installed.manifest.name)\""))
        XCTAssertTrue(settings.contains("revokeTrust(for: installed)"))
        XCTAssertTrue(settings.contains("Revoked future consent for \\(installed.manifest.name)"))
        XCTAssertTrue(settings.contains("clearTrustDecision(for: installed)"))
        XCTAssertTrue(settings.contains("Cleared trust decision for \\(installed.manifest.name)"))
        XCTAssertTrue(settings.contains("Label(\"Copy Warnings\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(settings.contains("Cribble extension validation warnings"))
        XCTAssertTrue(settings.contains("Copied extension warnings"))
        XCTAssertTrue(settings.contains("fix the manifest, then use Check Again"))
    }

    func testSettingsExposeProjectIntelligenceControls() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/SettingsView.swift")
        let appURL = projectRoot.appendingPathComponent("Sources/Cribble/App/CribbleApp.swift")
        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        let app = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertTrue(settings.contains("Section(\"Project Intelligence\")"))
        XCTAssertTrue(settings.contains("Picker(\"Performance\""))
        XCTAssertTrue(settings.contains("Toggle(\"Pause on battery saver\""))
        XCTAssertTrue(settings.contains("Toggle(\"Use Project Intelligence in chat\""))
        XCTAssertTrue(settings.contains("Stepper(value: Binding("))
        XCTAssertTrue(settings.contains("intelligence.settings.diskBudgetMB = $0"))
        XCTAssertTrue(settings.contains("RemoteRunnerDataBoundary.detail"))
        XCTAssertTrue(settings.contains("Button(\"Copy Review\""))
        XCTAssertTrue(settings.contains("RemoteRunnerSetupReview.markdown"))
        XCTAssertTrue(settings.contains("Copied remote runner setup review"))
        XCTAssertTrue(settings.contains("Notes stay on this Mac unless you choose a remote runner or extension profile."))
        XCTAssertTrue(app.contains(".environmentObject(intelligence)"))
    }

    func testRemoteRunnerHandoffStripsExposeCopyReviewLabels() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hudURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/IntelligenceHUD/IntelligenceHUDView.swift")
        let hud = try String(contentsOf: hudURL, encoding: .utf8)

        XCTAssertTrue(hud.contains("private struct CustomRunnerHandoffStrip"))
        XCTAssertTrue(hud.contains("private struct ExtensionRunnerHandoffStrip"))
        XCTAssertEqual(hud.components(separatedBy: "Label(\"Copy Review\", systemImage: \"doc.on.doc\")").count - 1, 2)
        XCTAssertTrue(hud.contains(".help(\"Copy custom runner checklist\")"))
        XCTAssertTrue(hud.contains(".help(\"Copy runner handoff details\")"))
    }

    private func index(of needle: String, in haystack: String) -> String.Index {
        guard let index = haystack.range(of: needle)?.lowerBound else {
            XCTFail("Expected to find \(needle)")
            return haystack.endIndex
        }
        return index
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
        XCTAssertTrue(home.contains("Contribute"))
        XCTAssertTrue(home.contains("renderer aliases, import-lane"))
        XCTAssertTrue(home.contains("extension profiles get a review sheet"))
        XCTAssertTrue(home.contains("Copy a generated Intelligence artifact as Markdown"))
        XCTAssertTrue(home.contains("Copy Diff"))
        XCTAssertTrue(home.contains("Copy Next Actions"))
        XCTAssertTrue(home.contains("Help → Copy Extension Proposal"))
        XCTAssertTrue(home.contains("Help → Copy Research Review Template"))
        XCTAssertTrue(home.contains("Help → Copy Decision Entry Template"))
        XCTAssertTrue(home.contains("Help → Open Extension Contribution Guide"))
        XCTAssertTrue(home.contains("Help → Copy Remote Runner Setup Review"))
        XCTAssertTrue(home.contains("[[Decision Log]]"))
        XCTAssertFalse(home.contains("No cloud, no account"))

        let gettingStarted = try String(contentsOf: demoRoot.appendingPathComponent("Getting Started.md"), encoding: .utf8)
        XCTAssertTrue(gettingStarted.contains("local-first chat"))

        let tasks = try String(contentsOf: demoRoot.appendingPathComponent("Tasks and Intelligence.md"), encoding: .utf8)
        XCTAssertTrue(tasks.contains("trusted remote runners are opt-in"))
        XCTAssertTrue(tasks.contains("reviewed before note context"))
        XCTAssertTrue(tasks.contains("Copy Task"))
        XCTAssertTrue(tasks.contains("zero-permission handoff"))
        XCTAssertTrue(tasks.contains("Copy Markdown"))
        XCTAssertTrue(tasks.contains("Copy Diff"))
        XCTAssertTrue(tasks.contains("artifact type, cached path"))
        XCTAssertTrue(tasks.contains("Copy Answer"))
        XCTAssertTrue(tasks.contains("original question and answer"))

        let featureTour = try String(contentsOf: demoRoot.appendingPathComponent("Feature Tour.md"), encoding: .utf8)
        XCTAssertTrue(featureTour.contains("pick the model boundary you trust"))
        XCTAssertTrue(featureTour.contains("clearly labeled Claude/Codex CLI choice"))

        let cribbleAI = try String(contentsOf: demoRoot.appendingPathComponent("Cribble AI.md"), encoding: .utf8)
        XCTAssertTrue(cribbleAI.contains("pick the model boundary you trust"))

        let extensions = try String(contentsOf: demoRoot.appendingPathComponent("Extensions and Remote Intelligence.md"), encoding: .utf8)
        XCTAssertTrue(extensions.contains("data-only"))
        XCTAssertTrue(extensions.contains("signed/revocable model"))
        XCTAssertTrue(extensions.contains("Chat HUD command surface"))
        XCTAssertTrue(extensions.contains("Help → Copy Import Lane Setup Review"))
        XCTAssertTrue(extensions.contains("File → Import → Copy Review"))
        XCTAssertTrue(extensions.contains("Help → Copy Remote Runner Setup Review"))
        XCTAssertTrue(extensions.contains("# Remote Runner Setup Review"))
        XCTAssertTrue(extensions.contains("Prompts, note excerpts, generated summaries, and embedding requests may leave this Mac"))
        XCTAssertTrue(extensions.contains("Retention policy, logging, and access controls are understood before use"))
        XCTAssertTrue(extensions.contains("Secrets stay out of manifests and notes; use Keychain only"))
        XCTAssertTrue(extensions.contains("user-selected files only"))
        XCTAssertTrue(extensions.contains("previewed writes"))

        let teamKit = try String(contentsOf: demoRoot.appendingPathComponent("Team Extension Kit.md"), encoding: .utf8)
        XCTAssertTrue(teamKit.contains("Help → Copy Extension Proposal"))
        XCTAssertTrue(teamKit.contains("Help → Copy Import Lane Setup Review"))
        XCTAssertTrue(teamKit.contains("Help → Copy Remote Runner Setup Review"))
        XCTAssertTrue(teamKit.contains("Settings → Extensions → Copy Warnings"))
        XCTAssertTrue(teamKit.contains("File → Import → Copy Review"))
        XCTAssertTrue(teamKit.contains("[[Extension Contribution Guide]]"))
        XCTAssertTrue(teamKit.contains("Help → Open Extension Contribution Guide"))
        XCTAssertTrue(teamKit.contains("docs/extension-contributions.md"))
        XCTAssertTrue(teamKit.contains("read-only first, least reading, least writing"))
        XCTAssertTrue(teamKit.contains("hard native SwiftUI surfaces"))
        XCTAssertTrue(teamKit.contains("creating or adapting a manifest"))
        XCTAssertTrue(teamKit.contains("Executable plugins need a separate readiness review"))
        XCTAssertTrue(teamKit.contains("process isolation"))
        XCTAssertTrue(teamKit.contains("native SwiftUI surfaces"))

        let contributionGuide = try String(contentsOf: demoRoot.appendingPathComponent("Extension Contribution Guide.md"), encoding: .utf8)
        XCTAssertTrue(contributionGuide.contains("Ideas should be open and ambitious"))
        XCTAssertTrue(contributionGuide.contains("Read-only first"))
        XCTAssertTrue(contributionGuide.contains("Least writing"))
        XCTAssertTrue(contributionGuide.contains("Hard native SwiftUI"))
        XCTAssertTrue(contributionGuide.contains("No hidden execution"))
        XCTAssertTrue(contributionGuide.contains("Help → Copy Extension Proposal"))
        XCTAssertTrue(contributionGuide.contains("Help → Copy Import Lane Setup Review"))
        XCTAssertTrue(contributionGuide.contains("File → Import → Copy Review"))
        XCTAssertTrue(contributionGuide.contains("Help → Copy Remote Runner Setup Review"))
        XCTAssertTrue(contributionGuide.contains("Settings → Extensions → Copy Warnings"))
        XCTAssertTrue(contributionGuide.contains("signed bundle identity"))

        let researchReview = try String(contentsOf: demoRoot.appendingPathComponent("Research Review.md"), encoding: .utf8)
        XCTAssertTrue(researchReview.contains("Help → Copy Research Review Template"))
        XCTAssertTrue(researchReview.contains("claim table"))
        XCTAssertTrue(researchReview.contains("review boundaries"))

        let workflow = try String(contentsOf: demoRoot.appendingPathComponent("Workflow Playbook.md"), encoding: .utf8)
        XCTAssertTrue(workflow.contains("import-lane declaration"))
        XCTAssertTrue(workflow.contains("generated artifact can be inspected and copied as Markdown"))
        XCTAssertTrue(workflow.contains("answer can be copied with the question attached"))
        XCTAssertTrue(workflow.contains("Help → Copy Research"))
        XCTAssertTrue(workflow.contains("Help → Copy Decision Entry"))
        XCTAssertTrue(workflow.contains("[[Decision Log]]"))

        let decisionLog = try String(contentsOf: demoRoot.appendingPathComponent("Decision Log.md"), encoding: .utf8)
        XCTAssertTrue(decisionLog.contains("Decision entry template"))
        XCTAssertTrue(decisionLog.contains("Help → Copy Decision Entry Template"))
        XCTAssertTrue(decisionLog.contains("YYYY-MM-DD - Decision title"))
        XCTAssertTrue(decisionLog.contains("Status: proposed | accepted | reversed"))
        XCTAssertTrue(decisionLog.contains("Review boundary"))
        XCTAssertTrue(decisionLog.contains("Help → Copy Extension Proposal"))
        XCTAssertTrue(decisionLog.contains("Help → Copy Import Lane Setup Review"))
        XCTAssertTrue(decisionLog.contains("Help → Copy Remote Runner Setup Review"))
        XCTAssertTrue(decisionLog.contains("executable readiness gates"))
    }

    func testWelcomeStarterChecklistGuidesCoreProductTour() {
        let checklist = WelcomeStarterChecklist.markdown

        XCTAssertTrue(checklist.contains("Cribble Starter Checklist"))
        XCTAssertTrue(checklist.contains("[[Getting Started]]"))
        XCTAssertTrue(checklist.contains("Copy Trail Summary"))
        XCTAssertTrue(checklist.contains("zero-file research handoff"))
        XCTAssertTrue(checklist.contains("[[Cribble AI]]"))
        XCTAssertTrue(checklist.contains("model boundary"))
        XCTAssertTrue(checklist.contains("welcome **Tasks** button"))
        XCTAssertTrue(checklist.contains("Command Option T"))
        XCTAssertTrue(checklist.contains("Tasks.md"))
        XCTAssertTrue(checklist.contains("[[Workflow Playbook]]"))
        XCTAssertTrue(checklist.contains("Help -> Copy Research Review Template"))
        XCTAssertTrue(checklist.contains("Help -> Copy Decision Entry Template"))
        XCTAssertTrue(checklist.contains("[[Team Extension Kit]]"))
        XCTAssertTrue(checklist.contains("Help -> Open Extension Contribution Guide"))
        XCTAssertTrue(checklist.contains("Help -> Copy Extension Proposal"))
        XCTAssertTrue(checklist.contains("Copy Proposal"))
        XCTAssertTrue(checklist.contains("read-only, least-access, and native SwiftUI"))
        XCTAssertTrue(checklist.contains("Help -> Copy Import Lane Setup Review"))
        XCTAssertTrue(checklist.contains("Help -> Copy Remote Runner Setup Review"))
        XCTAssertTrue(checklist.contains("VPS or remote runner"))
    }

    func testDecisionLogTemplateNamesReviewBoundary() {
        let template = DecisionLogTemplate.markdown

        XCTAssertTrue(template.contains("YYYY-MM-DD - Decision title"))
        XCTAssertTrue(template.contains("Status: proposed | accepted | reversed"))
        XCTAssertTrue(template.contains("[[Research Review]]"))
        XCTAssertTrue(template.contains("Review boundary"))
        XCTAssertTrue(template.contains("What may leave this Mac?"))
        XCTAssertTrue(template.contains("What can be disabled or reverted?"))
    }

    func testResearchReviewTemplateNamesEvidenceAndBoundaries() {
        let template = ResearchReviewTemplate.markdown

        XCTAssertTrue(template.contains("# Research Review"))
        XCTAssertTrue(template.contains("Claim table"))
        XCTAssertTrue(template.contains("What would change my mind?"))
        XCTAssertTrue(template.contains("Contradictions or gaps"))
        XCTAssertTrue(template.contains("Review boundary"))
        XCTAssertTrue(template.contains("Did any note context leave this Mac?"))
    }

    func testProductReadinessCheckpointTemplateNamesStopConditions() {
        let template = ProductReadinessCheckpointTemplate.markdown

        XCTAssertTrue(template.contains("# Product Readiness Checkpoint"))
        XCTAssertTrue(template.contains("Strong product signal"))
        XCTAssertTrue(template.contains("Ready to keep"))
        XCTAssertTrue(template.contains("Stop conditions"))
        XCTAssertTrue(template.contains("Keep going only if"))
        XCTAssertTrue(template.contains("Verification snapshot"))
        XCTAssertTrue(template.contains("executable plugin runtime"))
        XCTAssertTrue(template.contains("source-note writes without preview/review/cancel"))
        XCTAssertTrue(template.contains("remote intelligence that hides retention"))
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
        XCTAssertTrue(review.contains("Help > Copy Import Lane Setup Review"))
        XCTAssertTrue(review.contains("Copy Proposal"))
    }

    func testImportGuidanceSheetLinksContributionGuide() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/ContentView.swift")
        let content = try String(contentsOf: contentURL, encoding: .utf8)

        XCTAssertTrue(content.contains("onOpenContributionGuide"))
        XCTAssertTrue(content.contains("library.openDemoNote(named: \"Extension Contribution Guide.md\""))
        XCTAssertTrue(content.contains("Label(\"Open Contribution Guide\", systemImage: \"checkmark.shield\")"))
        XCTAssertTrue(content.contains("strict read-only, least-writing, native SwiftUI contribution guide"))
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

    func testTaskMenuCanCopyTaskWithoutExternalExport() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let taskListURL = projectRoot.appendingPathComponent("Sources/Cribble/Views/TaskListView.swift")
        let taskList = try String(contentsOf: taskListURL, encoding: .utf8)

        XCTAssertTrue(taskList.contains("import AppKit"))
        XCTAssertTrue(taskList.contains("Label(copiedTask ? \"Copied Task\" : \"Copy Task\""))
        XCTAssertTrue(taskList.contains("copyTask()"))
        XCTAssertTrue(taskList.contains("NSPasteboard.general.setString(item.label.trimmingCharacters"))
        XCTAssertTrue(taskList.contains("without creating a Reminder or Calendar event"))
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
