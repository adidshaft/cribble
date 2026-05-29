import XCTest
@testable import Cribble

final class FolderPinningTests: XCTestCase {
    @MainActor
    func testTogglePinFloatsFolderToTopOfSiblings() throws {
        let root = try Fixture.makeFolder()
        for name in ["Apple", "Banana", "Cherry"] {
            let sub = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try "# \(name)".write(to: sub.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        }

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)
        let exp = expectation(description: "scan")
        Task { await store.waitForLoadToComplete(); exp.fulfill() }
        wait(for: [exp], timeout: 3.0)

        let banana = root.appendingPathComponent("Banana")

        XCTAssertFalse(store.isPinned(banana))
        // Default order is alphabetical.
        XCTAssertEqual(childFolderNames(of: store), ["Apple", "Banana", "Cherry"])

        store.togglePin(banana)
        XCTAssertTrue(store.isPinned(banana))
        // Pinned folder floats to the top of its sibling group.
        XCTAssertEqual(childFolderNames(of: store), ["Banana", "Apple", "Cherry"])

        store.togglePin(banana)
        XCTAssertFalse(store.isPinned(banana))
        XCTAssertEqual(childFolderNames(of: store), ["Apple", "Banana", "Cherry"])
    }

    @MainActor
    private func childFolderNames(of store: MarkdownLibraryStore) -> [String] {
        guard let rootNode = store.filteredNodes.first else { return [] }
        return rootNode.children.filter { $0.kind == .folder }.map(\.name)
    }
}
