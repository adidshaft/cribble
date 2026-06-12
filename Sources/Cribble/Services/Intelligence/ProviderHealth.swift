import Foundation

enum ProviderFix: Equatable {
    case downloadModel(LocalModel)
    case openModelPicker
    case startLocalRunner(name: String, url: String)
    case authenticateCLI(name: String, command: String)
}

enum ProviderHealth: Equatable {
    case ready
    case unavailable(reason: String, fix: ProviderFix)
}

enum ProviderHealthMapper {
    static func health(
        availability: ProviderAvailability?,
        modelID: String,
        localRunnerBaseURL: String?
    ) -> ProviderHealth {
        guard let availability else {
            return .unavailable(reason: "Choose an intelligence model.", fix: .openModelPicker)
        }

        switch availability {
        case .available, .degraded:
            return .ready
        case .unavailable(let reason):
            return .unavailable(
                reason: reason,
                fix: fix(reason: reason, modelID: modelID, localRunnerBaseURL: localRunnerBaseURL)
            )
        }
    }

    static func fix(reason: String, modelID: String, localRunnerBaseURL: String?) -> ProviderFix {
        if let localRunnerBaseURL {
            let name = runnerName(for: localRunnerBaseURL)
            return .startLocalRunner(name: name, url: localRunnerBaseURL)
        }

        guard let model = ModelCatalog.model(withID: modelID) else {
            return .openModelPicker
        }

        switch model.kind {
        case .localMLX:
            if reason.localizedCaseInsensitiveContains("not downloaded") {
                return .downloadModel(model)
            }
            return .openModelPicker
        case .claudeCLI:
            return .authenticateCLI(name: model.name, command: "claude login")
        case .codexCLI:
            return .authenticateCLI(name: model.name, command: "codex login")
        }
    }

    private static func runnerName(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "Local Runner" }
        let normalized = normalize(url)
        return OpenAICompatibleProvider.knownLocalEndpoints.first { endpoint in
            normalize(endpoint.url) == normalized
        }?.name ?? "Local Runner"
    }

    private static func normalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if components.host?.lowercased() == "localhost" {
            components.host = "127.0.0.1"
        }
        return (components.url ?? url).absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
