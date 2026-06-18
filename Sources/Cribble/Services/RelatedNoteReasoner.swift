import Foundation

enum RelatedNoteReasoner {
    static let inputCharacterLimit = 2_400

    @MainActor
    static func availableLocalModel(entitlement: LLMEntitlementStore) -> LocalModel? {
        guard entitlement.isUnlocked,
              ModelCatalog.isOnDeviceAvailable,
              let model = ModelCatalog.recommendedOnDevice,
              ModelInventory.availability(of: model) == .downloaded
        else { return nil }
        return model
    }

    static func messages(
        modelName: String,
        sourceTitle: String,
        sourceText: String,
        relatedTitle: String,
        relatedText: String
    ) -> [EngineMessage] {
        [
            EngineMessage(
                role: .system,
                content: """
                You explain connections between two local Markdown notes. Use only the supplied note text.
                Reply with one plain sentence, 22 words or fewer. No bullets, no preamble, no Markdown.
                """
            ),
            EngineMessage(
                role: .user,
                content: """
                Model: \(modelName)

                Current note: \(sourceTitle)
                \(bounded(sourceText))

                Related note: \(relatedTitle)
                \(bounded(relatedText))

                Why are these notes related?
                """
            )
        ]
    }

    static func clean(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(oneLine.prefix(180))
    }

    @MainActor
    static func generateReason(sourceURL: URL, related hit: SemanticHit, model: LocalModel) async throws -> String {
        let source = try await load(url: sourceURL)
        let related = try await load(url: hit.url)
        let engine = LocalLLM.shared.engine(for: model)
        try await engine.prepare(model: model) { _ in }
        let output = try await engine.generate(
            messages: messages(
                modelName: model.name,
                sourceTitle: source.title,
                sourceText: source.rawMarkdown,
                relatedTitle: hit.title,
                relatedText: related.rawMarkdown
            ),
            maxTokens: 64
        ) { _ in }
        let cleaned = clean(output)
        return cleaned.isEmpty ? "The local model did not return a reason." : cleaned
    }

    private static func bounded(_ text: String) -> String {
        String(text.prefix(inputCharacterLimit))
    }

    private static func load(url: URL) async throws -> MarkdownDocument {
        try await Task.detached(priority: .utility) {
            try DocumentLoader().load(url: url)
        }.value
    }
}
