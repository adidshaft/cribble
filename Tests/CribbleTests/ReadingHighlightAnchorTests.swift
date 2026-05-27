import XCTest
@testable import Cribble

final class ReadingHighlightAnchorTests: XCTestCase {
    func testHighlightAnchorRoundtrip() throws {
        let anchor = HighlightAnchor(
            sectionAnchor: "introduction",
            blockIndex: 2,
            blockSignature: "a1b2c3d4",
            startOffset: 12,
            length: 15
        )
        let highlight = ReadingHighlight(
            id: UUID(),
            documentPath: "/path/to/doc.md",
            quote: "This is a quote",
            note: "My important note",
            createdAt: Date(),
            anchor: anchor
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(highlight)
        let decoded = try decoder.decode(ReadingHighlight.self, from: data)
        
        XCTAssertEqual(decoded.id, highlight.id)
        XCTAssertEqual(decoded.documentPath, highlight.documentPath)
        XCTAssertEqual(decoded.quote, highlight.quote)
        XCTAssertEqual(decoded.note, highlight.note)
        XCTAssertEqual(decoded.anchor, anchor)
    }
    
    func testLegacyHighlightDecodingWithoutAnchor() throws {
        // v1.0.4 format without anchor field
        let legacyJSON = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "documentPath": "/path/to/doc.md",
            "quote": "This is a legacy quote",
            "note": "A legacy note",
            "createdAt": "2026-05-27T18:00:00Z"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let decoded = try decoder.decode(ReadingHighlight.self, from: legacyJSON)
        
        XCTAssertEqual(decoded.id, UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        XCTAssertEqual(decoded.documentPath, "/path/to/doc.md")
        XCTAssertEqual(decoded.quote, "This is a legacy quote")
        XCTAssertEqual(decoded.note, "A legacy note")
        XCTAssertNil(decoded.anchor)
    }
}
