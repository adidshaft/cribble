import XCTest
@testable import Cribble

final class RelatedNotesCacheTests: XCTestCase {
    func testStoresAndReadsByStandardizedURL() {
        var cache = RelatedNotesCache(limit: 2)
        let base = URL(fileURLWithPath: "/tmp/notes")
        let raw = base.appendingPathComponent("../notes/Current.md")
        let hit = SemanticHit(
            url: base.appendingPathComponent("Other.md"),
            title: "Other",
            score: 0.7
        )

        cache.store([hit], for: raw)

        XCTAssertEqual(cache.hits(for: base.appendingPathComponent("Current.md")), [hit])
    }

    func testBoundsEntriesByLeastRecentlyUsed() {
        var cache = RelatedNotesCache(limit: 2)
        let first = URL(fileURLWithPath: "/tmp/A.md")
        let second = URL(fileURLWithPath: "/tmp/B.md")
        let third = URL(fileURLWithPath: "/tmp/C.md")
        let hit = SemanticHit(url: third, title: "C", score: 0.7)

        cache.store([hit], for: first)
        cache.store([hit], for: second)
        _ = cache.hits(for: first)
        cache.store([hit], for: third)

        XCTAssertNotNil(cache.hits(for: first))
        XCTAssertNil(cache.hits(for: second))
        XCTAssertNotNil(cache.hits(for: third))
        XCTAssertEqual(cache.count, 2)
    }

    func testRemoveAllClearsEntries() {
        var cache = RelatedNotesCache(limit: 2)
        let url = URL(fileURLWithPath: "/tmp/A.md")
        cache.store([SemanticHit(url: url, title: "A", score: 0.9)], for: url)

        cache.removeAll()

        XCTAssertNil(cache.hits(for: url))
        XCTAssertEqual(cache.count, 0)
    }
}
