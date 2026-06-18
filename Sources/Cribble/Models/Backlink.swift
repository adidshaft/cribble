import Foundation

struct Backlink: Equatable, Sendable, Identifiable {
    let sourceURL: URL
    let sourceTitle: String
    let occurrences: [BacklinkOccurrence]

    var id: URL { sourceURL }
}

struct BacklinkOccurrence: Equatable, Sendable, Identifiable {
    let id: String
    let linkLabel: String
    let snippet: String
    let headingContext: String?
}
