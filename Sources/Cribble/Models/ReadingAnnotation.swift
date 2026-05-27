import Foundation

struct ReadingBookmark: Codable, Equatable {
    let documentPath: String
    var scrollOffsetY: Double
    var sectionTitle: String?
    var updatedAt: Date
}

struct HighlightAnchor: Codable, Equatable {
    var sectionAnchor: String
    var blockIndex: Int
    var blockSignature: String
    var startOffset: Int
    var length: Int
}

struct ReadingHighlight: Codable, Equatable, Identifiable {
    var id: UUID
    let documentPath: String
    var quote: String
    var note: String
    var createdAt: Date
    var anchor: HighlightAnchor?   // Optional to decode v1.0.4 highlights cleanly
}
