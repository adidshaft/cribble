import XCTest
@testable import Cribble

final class NavigationHistoryTests: XCTestCase {
    @MainActor
    func testNavigationHistoryStack() throws {
        let store = MarkdownLibraryStore(restore: false)
        // Simulating selection (normally done via select(url:))
        // Since we are mocking, let's manually populate or verify history logic.
        // Wait, select(url:) resolves via documentURL(for:). To avoid FileManager/DocumentLoader checking,
        // let's test using the store's open folder environment, or let's look at select() logic:
        // Inside select(url:), it does:
        // let documentURL = documentURL(for: url) -> checks fileExists
        // To test select(url:) directly, we need files that exist.
        
        let root = try Fixture.makeFolder()
        let noteA = root.appendingPathComponent("NoteA.md")
        let noteB = root.appendingPathComponent("NoteB.md")
        let noteC = root.appendingPathComponent("NoteC.md")
        
        try "# Note A".write(to: noteA, atomically: true, encoding: .utf8)
        try "# Note B".write(to: noteB, atomically: true, encoding: .utf8)
        try "# Note C".write(to: noteC, atomically: true, encoding: .utf8)
        // Open the folder
        store.openFolder(root, sortMode: .name)

        // Wait for loader task
        let exp = expectation(description: "Wait for folder scan")
        Task {
            await store.waitForLoadToComplete()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // Clear history and selection so we start from a clean slate
        store.history = []
        store.historyIndex = -1
        store.selectedURL = nil
        store.selectedDocument = nil

        // Initial state
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
        
        // Select A
        store.select(url: noteA)
        XCTAssertEqual(store.selectedDocument?.url, noteA)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
        
        // Select B
        store.select(url: noteB)
        XCTAssertEqual(store.selectedDocument?.url, noteB)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
        XCTAssertEqual(store.history.count, 2)
        XCTAssertEqual(store.historyIndex, 1)
        
        // Select C
        store.select(url: noteC)
        XCTAssertEqual(store.selectedDocument?.url, noteC)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
        XCTAssertEqual(store.history.count, 3)
        XCTAssertEqual(store.historyIndex, 2)
        
        // Navigate Back to B
        store.navigateBack()
        XCTAssertEqual(store.selectedDocument?.url, noteB)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)
        XCTAssertEqual(store.historyIndex, 1)
        
        // Navigate Back to A
        store.navigateBack()
        XCTAssertEqual(store.selectedDocument?.url, noteA)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)
        XCTAssertEqual(store.historyIndex, 0)
        
        // Navigate Forward to B
        store.navigateForward()
        XCTAssertEqual(store.selectedDocument?.url, noteB)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)
        XCTAssertEqual(store.historyIndex, 1)
        
        // Branching: Select C again or new navigation from B clears forward history
        // Let's navigate to C from B via new selection
        store.select(url: noteC)
        XCTAssertEqual(store.selectedDocument?.url, noteC)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
        XCTAssertEqual(store.history.count, 3)
        XCTAssertEqual(store.historyIndex, 2)
    }
}
