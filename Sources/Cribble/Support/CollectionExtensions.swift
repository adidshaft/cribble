import Foundation

extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
