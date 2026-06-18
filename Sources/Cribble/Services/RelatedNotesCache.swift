import Foundation

struct RelatedNotesCache {
    private var entries: [URL: [SemanticHit]] = [:]
    private var order: [URL] = []
    private let limit: Int

    init(limit: Int = 64) {
        self.limit = max(1, limit)
    }

    mutating func hits(for url: URL) -> [SemanticHit]? {
        let key = url.standardizedFileURL
        guard let hits = entries[key] else { return nil }
        touch(key)
        return hits
    }

    mutating func store(_ hits: [SemanticHit], for url: URL) {
        let key = url.standardizedFileURL
        entries[key] = hits
        touch(key)
        while order.count > limit {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    var count: Int { entries.count }

    private mutating func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}
