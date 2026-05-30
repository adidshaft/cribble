import Foundation

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
// Required so the `#hubDownloader()` / `#huggingFaceTokenizerLoader()` macros can
// bridge to a concrete HuggingFace client and tokenizer at this call site.
import HuggingFace
import Tokenizers

/// MLX-backed on-device chat engine. This is the only file in the app that
/// imports MLX, keeping the heavy dependency contained. Metal acceleration is
/// implicit on Apple Silicon — MLX runs on the GPU by default.
///
/// Wrapped in `#if canImport(MLXLLM)` so the project still builds before the
/// `mlx-swift-lm` package is resolved; `LocalChatEngineFactory` falls back to
/// `UnavailableChatEngine` in that case.
final class MLXChatEngine: LocalChatEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var container: ModelContainer?
    private var loadedModelID: String?
    private var cancelRequested = false

    func prepare(
        model: LocalModel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let alreadyLoaded = lock.withLock { loadedModelID == model.id && container != nil }
        if alreadyLoaded { return }

        // Cap memory growth so a large model can't balloon the working set on
        // smaller Macs; MLX recycles its buffer cache against this budget.
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)

        let configuration = ModelConfiguration(id: model.huggingFaceRepo)
        do {
            let newContainer = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { progress in
                onProgress(progress.fractionCompleted)
            }
            lock.withLock {
                container = newContainer
                loadedModelID = model.id
            }
            onProgress(1.0)
        } catch {
            throw LocalChatEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let container = lock.withLock { self.container }
        guard let container else {
            throw LocalChatEngineError.modelLoadFailed("No model is loaded.")
        }

        lock.withLock { cancelRequested = false }

        // The leading system turn becomes the session instructions; the rest is
        // replayed as the conversation. A fresh session per send keeps the file
        // context current and the implementation simple.
        let instructions = messages.first(where: { $0.role == .system })?.content
        let chat: [Chat.Message] = messages.compactMap { message in
            switch message.role {
            case .system: nil
            case .user: .user(message.content)
            case .assistant: .assistant(message.content)
            }
        }

        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.7)
        )

        var full = ""
        do {
            for try await chunk in session.streamResponse(to: chat) {
                if lock.withLock({ cancelRequested }) || Task.isCancelled {
                    break
                }
                full += chunk
                onToken(chunk)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalChatEngineError.generationFailed(error.localizedDescription)
        }
        return full
    }

    func cancelGeneration() async {
        lock.withLock { cancelRequested = true }
    }
}
#endif

/// Engine used when MLX is unavailable (e.g. a build without the dependency).
/// Surfaces a clear error rather than crashing.
final class UnavailableChatEngine: LocalChatEngine, @unchecked Sendable {
    func prepare(model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        throw LocalChatEngineError.engineUnavailable
    }

    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw LocalChatEngineError.engineUnavailable
    }

    func cancelGeneration() async {}
}

/// Resolves the concrete engine for this build.
enum LocalChatEngineFactory {
    static func make() -> LocalChatEngine {
        #if canImport(MLXLLM)
        return MLXChatEngine()
        #else
        return UnavailableChatEngine()
        #endif
    }
}
