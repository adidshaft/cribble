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
}
