import Foundation

struct ReadingBookmark: Codable, Equatable {
    let documentPath: String
    var scrollOffsetY: Double
    var sectionTitle: String?
    var updatedAt: Date
}

struct ReadingHighlight: Codable, Equatable, Identifiable {
    var id: UUID
    let documentPath: String
    var quote: String
    var note: String
    var createdAt: Date
}
