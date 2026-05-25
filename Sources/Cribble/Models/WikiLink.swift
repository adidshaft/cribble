import Foundation

struct WikiLink: Equatable, Hashable {
    let original: String
    let target: String
    let label: String
    let anchor: String?

    var normalizedTarget: String {
        LinkIndex.normalize(target)
    }
}

struct ResolvedLink: Equatable, Hashable {
    let link: WikiLink
    let targetURL: URL?
    let anchor: String?

    var isResolved: Bool {
        targetURL != nil
    }
}
