import Foundation

struct ExtensionIntelligenceProviderProfile: Identifiable, Equatable {
    let id: String
    let title: String
    let baseURL: URL
    let modelID: String
    let embeddingModelID: String?
    let trustLabel: String
    let sourceName: String

    var isLoopback: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".localhost")
    }

    var privacyLabel: String {
        isLoopback ? "Local runner" : "Remote runner"
    }

    var handoffSummary: String {
        var lines = [
            "Runner: \(title)",
            "Endpoint: \(baseURL.absoluteString)",
            "Model: \(modelID)",
            "Trust label: \(trustLabel)",
            "Source extension: \(sourceName)",
            "Context boundary: \(isLoopback ? "stays on this Mac/local network endpoint" : "note context may leave this Mac")",
            "API key: enter in the Intelligence HUD; store in Keychain when needed",
            "Disable/revoke: disable the extension in Settings or choose a different runner"
        ]
        if let embeddingModelID, !embeddingModelID.isEmpty {
            lines.insert("Embeddings: \(embeddingModelID)", after: "Model: \(modelID)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    mutating func insert(_ newElement: String, after marker: String) {
        guard let index = firstIndex(of: marker) else {
            append(newElement)
            return
        }
        insert(newElement, at: self.index(after: index))
    }
}
