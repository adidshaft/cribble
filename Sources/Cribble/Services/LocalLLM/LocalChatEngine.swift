import Foundation

/// A role/content pair handed to the engine. Mirrors the chat-template roles
/// MLX expects ("system" / "user" / "assistant").
struct EngineMessage: Sendable, Hashable {
    enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}

/// Abstraction over the on-device text generator. Kept free of any MLX types
/// so the whole app (and the test suite) compiles and runs without the MLX
/// toolchain — only `MLXChatEngine` imports MLX. The HUD view model talks to
/// this protocol exclusively, which is also what makes it unit-testable.
protocol LocalChatEngine: AnyObject, Sendable {
    /// Downloads (if needed) and loads the given model into memory. `onProgress`
    /// reports download fraction in `0...1`; loading/compile may report 1.0
    /// repeatedly. Safe to call repeatedly; a no-op when already prepared for
    /// the same model.
    func prepare(
        model: LocalModel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws

    /// Streams a completion for `messages`, invoking `onToken` on the main actor
    /// for each new text chunk. Returns the full text. Throws `CancellationError`
    /// if cancelled via `cancelGeneration()`.
    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String

    /// Requests cancellation of the in-flight `generate` call, if any.
    func cancelGeneration() async
}

enum LocalChatEngineError: LocalizedError {
    case engineUnavailable
    case modelLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            "The on-device model engine is not available in this build."
        case .modelLoadFailed(let detail):
            "Couldn't load the model: \(detail)"
        case .generationFailed(let detail):
            "The model stopped unexpectedly: \(detail)"
        }
    }
}
