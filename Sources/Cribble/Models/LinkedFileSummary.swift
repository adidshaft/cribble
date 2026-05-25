import Foundation

struct LinkedFileSummary: Identifiable, Equatable {
    let id: URL
    let title: String
    let subtitle: String
    let url: URL
    let anchor: String?
}
