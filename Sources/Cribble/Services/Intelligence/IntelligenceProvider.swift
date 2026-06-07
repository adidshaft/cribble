import Foundation

/// A provider capable of running intelligence jobs: bounded text generation plus
/// optional embeddings. Deliberately separate from `LocalChatEngine` (which is
/// tuned for interactive streaming chat) — intelligence work is request/response,
/// schema-shaped, and batch-scheduled. Concrete providers *wrap* the existing
/// engines rather than replacing them (see the intelligence design doc §6).
protocol IntelligenceProvider: Sendable {
    /// Human-readable name for the HUD (e.g. "Qwen 3.5 4B (MLX)").
    var displayName: String { get }

    /// Whether this provider can run right now (model downloaded / server up).
    func checkAvailability() async -> ProviderAvailability

    /// Generates a bounded completion. `schema`, when supplied and supported,
    /// requests structured output; providers that can't enforce it fall back to
    /// prompt-only shaping.
    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String

    /// Generates an embedding vector, or nil if unsupported.
    func embed(text: String) async throws -> [Float]?
}

extension IntelligenceProvider {
    /// Convenience overload for the common no-schema case.
    func generate(prompt: [EngineMessage], maxTokens: Int) async throws -> String {
        try await generate(prompt: prompt, schema: nil, maxTokens: maxTokens)
    }
}

enum ProviderAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)   // "Model not downloaded", "Ollama not running"
    case degraded(reason: String)      // "Running on CPU — slow"

    var isUsable: Bool {
        switch self {
        case .available, .degraded: true
        case .unavailable: false
        }
    }
}

/// A minimal, provider-agnostic description of the desired output shape. Kept
/// intentionally light: MLX has no schema enforcement (we inline an example into
/// the prompt), while OpenAI-compatible runners can map this onto
/// `response_format`. We avoid pulling in a full JSON Schema type for Phase 1.
struct JSONSchemaHint: Sendable, Equatable {
    /// A short name for the structure (used in `response_format.json_schema.name`).
    let name: String
    /// A representative example of valid output, inlined into the prompt for
    /// providers that can't constrain generation.
    let example: String
}

/// Wraps any existing `LocalChatEngine` (MLX in-process or CLI) as an
/// `IntelligenceProvider`. Generation delegates to the engine; embeddings use the
/// app's existing Apple `EmbeddingEngine` so Phase 1 adds no new model downloads.
///
/// `@unchecked Sendable`: the wrapped engine is already `Sendable`, and this type
/// only forwards calls — it holds no mutable state of its own.
final class LocalEngineIntelligenceProvider: IntelligenceProvider, @unchecked Sendable {
    let displayName: String
    private let engine: LocalChatEngine
    private let model: LocalModel
    private let embeddingEngine: EmbeddingEngine
    private let prepareIfNeeded: Bool

    init(
        engine: LocalChatEngine,
        model: LocalModel,
        embeddingEngine: EmbeddingEngine,
        prepareIfNeeded: Bool = true
    ) {
        let kindLabel: String = switch model.kind {
        case .localMLX: "MLX"
        case .claudeCLI, .codexCLI: "CLI"
        case .localRunner: "Runner"
        }
        self.displayName = "\(model.name) (\(kindLabel))"
        self.engine = engine
        self.model = model
        self.embeddingEngine = embeddingEngine
        self.prepareIfNeeded = prepareIfNeeded
    }

    func checkAvailability() async -> ProviderAvailability {
        // For MLX, availability hinges on whether the model is on disk. We treat a
        // missing model as `unavailable` so Tier-1 jobs still run while the user
        // is prompted to download. CLI providers are assumed installed if chosen.
        switch model.kind {
        case .localMLX:
            // Refuse to load a model that needs more RAM than this Mac has — on a
            // small machine that's a fast path to swap-thrash or an OOM crash.
            let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            if Double(model.recommendedMemoryGB) > physicalGB {
                return .unavailable(reason: "Needs ~\(model.recommendedMemoryGB) GB RAM; this Mac has \(Int(physicalGB.rounded())) GB")
            }
            return ModelInventory.isDownloaded(model) ? .available : .unavailable(reason: "Model not downloaded")
        case .claudeCLI, .codexCLI:
            return .available
        case .localRunner:
            // Intelligence reaches runner models through OpenAICompatibleProvider,
            // never through this on-device wrapper.
            return .unavailable(reason: "Runner models use the OpenAI-compatible provider, not the on-device wrapper.")
        }
    }

    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String {
        if prepareIfNeeded {
            try await engine.prepare(model: model) { _ in }
        }
        var messages = prompt
        // No schema enforcement on the base engines: inline the example so the
        // model has a concrete target to imitate.
        if let schema {
            messages.append(EngineMessage(
                role: .system,
                content: "Respond ONLY with output matching this \(schema.name) format. Example:\n\(schema.example)"
            ))
        }
        return try await engine.generate(messages: messages, maxTokens: maxTokens) { _ in }
    }

    func embed(text: String) async throws -> [Float]? {
        guard await embeddingEngine.ensureReady() else { return nil }
        return await embeddingEngine.vector(for: text)
    }
}
