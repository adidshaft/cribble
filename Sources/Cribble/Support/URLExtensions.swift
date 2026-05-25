import Foundation

extension URL {
    func relativePath(from baseURL: URL) -> String {
        let base = baseURL.standardizedFileURL.pathComponents
        let target = standardizedFileURL.pathComponents
        let shared = zip(base, target).prefix { $0 == $1 }.count
        let remaining = target.dropFirst(shared)
        return remaining.joined(separator: "/")
    }
}
