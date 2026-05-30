import Foundation

/// Process-wide cache of chat engines keyed by model kind, so the chat HUD and
/// Pathfinder share a single loaded on-device model instead of each loading
/// their own (which would duplicate gigabytes of weights in memory).
@MainActor
final class LocalLLM {
    static let shared = LocalLLM()

    private var engines: [ModelKind: LocalChatEngine] = [:]

    private init() {}

    func engine(for model: LocalModel) -> LocalChatEngine {
        if let existing = engines[model.kind] { return existing }
        let engine = LocalChatEngineFactory.make(for: model)
        engines[model.kind] = engine
        return engine
    }
}
