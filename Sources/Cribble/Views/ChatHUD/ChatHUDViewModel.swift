import AppKit
import Foundation

/// Drives the Local Chat HUD: conversation state, `@file` autocomplete, model
/// loading, streaming generation, and routing of actionable model output into
/// the existing safe diff/create pipeline.
///
/// This is the contract the HUD views bind to. The visual layer should read and
/// call these published properties / methods and add no logic of its own.
@MainActor
final class ChatHUDViewModel: ObservableObject {
    /// Lifecycle of the selected model.
    enum ModelPhase: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    // MARK: Conversation
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var attachments: [TaggedFileToken] = []
    @Published private(set) var isGenerating = false

    // MARK: Autocomplete
    @Published private(set) var autocomplete: FileAutocompleteState?

    // MARK: Model
    @Published var selectedModel: LocalModel
    @Published private(set) var modelPhase: ModelPhase = .idle

    /// Status line shown under the model chip / in the input area.
    @Published private(set) var statusMessage: String?

    let greetingName: String

    private let library: MarkdownLibraryStore
    /// Test/preview override; when set it's used for every model.
    private let injectedEngine: LocalChatEngine?
    /// One engine instance per kind, created lazily.
    private var engineCache: [ModelKind: LocalChatEngine] = [:]
    private var loadedModelID: String?
    private var generationTask: Task<Void, Never>?

    init(library: MarkdownLibraryStore, engine: LocalChatEngine? = nil) {
        self.library = library
        self.injectedEngine = engine
        self.selectedModel = ModelCatalog.defaultModel
        let fullName = NSFullUserName()
        self.greetingName = fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    /// The engine for the currently selected model (cached per kind).
    private func currentEngine() -> LocalChatEngine {
        if let injectedEngine { return injectedEngine }
        if let existing = engineCache[selectedModel.kind] { return existing }
        let engine = LocalChatEngineFactory.make(for: selectedModel)
        engineCache[selectedModel.kind] = engine
        return engine
    }

    var hasConversation: Bool { !messages.isEmpty }

    var canSend: Bool {
        !isGenerating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Input & autocomplete

    /// Call from the input field's text binding so `@` mentions are detected as
    /// the user types.
    func updateDraft(_ text: String) {
        draft = text
        guard let mention = Self.activeMentionQuery(in: text) else {
            autocomplete = nil
            return
        }
        autocomplete = FileAutocompleteState(
            query: mention.query,
            matches: searchFiles(matching: mention.query)
        )
    }

    /// Commits an autocomplete pick: strips the in-progress `@query` and pins
    /// the file as an attachment.
    func applyAutocomplete(_ token: TaggedFileToken) {
        if let mention = Self.activeMentionQuery(in: draft) {
            draft.removeSubrange(mention.range)
        }
        addAttachment(token)
        autocomplete = nil
    }

    func dismissAutocomplete() {
        autocomplete = nil
    }

    func addAttachment(_ token: TaggedFileToken) {
        guard !attachments.contains(where: { $0.fileURL == token.fileURL }) else { return }
        attachments.append(token)
    }

    func removeAttachment(_ token: TaggedFileToken) {
        attachments.removeAll { $0.id == token.id }
    }

    /// A short list of notes for the `+` quick-attach menu.
    var quickAttachFiles: [TaggedFileToken] {
        searchFiles(matching: "")
    }

    // MARK: - Conversation control

    func newChat() {
        guard !isGenerating else { return }
        messages = []
        statusMessage = nil
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(ChatMessage(role: .user, text: text, attachments: attachments))
        draft = ""
        attachments = []
        autocomplete = nil

        let placeholder = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(placeholder)
        isGenerating = true

        generationTask = Task { [weak self] in
            await self?.runGeneration(assistantID: placeholder.id)
        }
    }

    func cancel() {
        generationTask?.cancel()
        let engine = currentEngine()
        Task { await engine.cancelGeneration() }
    }

    func selectModel(_ model: LocalModel) {
        guard model.id != selectedModel.id else { return }
        selectedModel = model
        // Force a reload on next send; loading is lazy and on-demand.
        modelPhase = .idle
        loadedModelID = nil
        statusMessage = nil
    }

    // MARK: - Generation

    private func runGeneration(assistantID: UUID) async {
        guard await ensureModelReady() else {
            failGeneration("Couldn't load \(selectedModel.name).", assistantID: assistantID)
            return
        }

        let resolved = resolveAttachments()
        let prompt = ContextAssembler.engineMessages(
            modelName: selectedModel.name,
            history: messages,
            files: resolved
        )

        let engine = currentEngine()
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let producer = Task<Result<String, Error>, Never> {
            do {
                let full = try await engine.generate(messages: prompt, maxTokens: 1024) { delta in
                    continuation.yield(delta)
                }
                continuation.finish()
                return .success(full)
            } catch {
                continuation.finish()
                return .failure(error)
            }
        }

        for await delta in stream {
            appendToken(delta, assistantID: assistantID)
        }

        switch await producer.value {
        case .success(let full):
            completeGeneration(finalText: full, assistantID: assistantID)
        case .failure(let error):
            if error is CancellationError {
                markCancelled(assistantID: assistantID)
            } else {
                failGeneration(error.localizedDescription, assistantID: assistantID)
            }
        }
    }

    private func ensureModelReady() async -> Bool {
        if modelPhase == .ready, loadedModelID == selectedModel.id {
            return true
        }
        modelPhase = selectedModel.kind.isCloud ? .loading : .downloading(0)
        statusMessage = "Preparing \(selectedModel.name)…"
        let model = selectedModel
        let engine = currentEngine()
        do {
            try await engine.prepare(model: model) { fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.selectedModel.id == model.id else { return }
                    self.modelPhase = fraction < 1 ? .downloading(fraction) : .loading
                }
            }
            modelPhase = .ready
            loadedModelID = model.id
            statusMessage = nil
            return true
        } catch {
            modelPhase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func appendToken(_ delta: String, assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].text += delta
    }

    private func completeGeneration(finalText: String, assistantID: UUID) {
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].text = finalText.isEmpty ? messages[index].text : finalText
            messages[index].isStreaming = false
        }
        isGenerating = false
        routeActionableOutput(finalText.isEmpty ? currentText(of: assistantID) : finalText)
    }

    private func markCancelled(assistantID: UUID) {
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].isStreaming = false
            if messages[index].text.isEmpty {
                messages[index].text = "_(stopped)_"
            }
        }
        isGenerating = false
        statusMessage = "Stopped"
    }

    private func failGeneration(_ message: String, assistantID: UUID) {
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            if messages[index].text.isEmpty {
                messages[index].text = "⚠️ \(message)"
            }
            messages[index].isStreaming = false
        }
        isGenerating = false
        statusMessage = message
    }

    /// Routes a completed answer into the existing safe write pipeline. The HUD
    /// never touches disk directly — diffs and new-file proposals flow through
    /// `MarkdownLibraryStore`'s review/apply sheets on the main window.
    private func routeActionableOutput(_ text: String) {
        switch ChatOutputParser.parse(text) {
        case .none:
            break
        case .diff(let diff):
            library.pendingDiff = diff
            bringMainWindowForward()
            statusMessage = "Review proposed changes in the main window"
        case .create(let fileName, let content):
            library.presentNewNoteProposal(fileName: fileName, content: content)
            bringMainWindowForward()
            statusMessage = "Review the new note in the main window"
        }
    }

    // MARK: - Helpers

    private func currentText(of assistantID: UUID) -> String {
        messages.first(where: { $0.id == assistantID })?.text ?? ""
    }

    /// Reads the contents of every file tagged across the conversation, deduped
    /// by URL, so follow-up questions keep their note context.
    private func resolveAttachments() -> [ResolvedFile] {
        var seen = Set<URL>()
        var resolved: [ResolvedFile] = []
        for message in messages where message.role == .user {
            for token in message.attachments where seen.insert(token.fileURL).inserted {
                if let content = try? String(contentsOf: token.fileURL, encoding: .utf8) {
                    resolved.append(ResolvedFile(filename: token.filename, content: content))
                }
            }
        }
        return resolved
    }

    private func searchFiles(matching query: String) -> [TaggedFileToken] {
        let documents = library.documents
        let ranked: [MarkdownDocument]
        if query.isEmpty {
            ranked = Array(documents.prefix(5))
        } else {
            let lowered = query.lowercased()
            let contains = documents.filter {
                $0.url.deletingPathExtension().lastPathComponent.lowercased().contains(lowered)
                    || $0.title.lowercased().contains(lowered)
            }
            ranked = contains.isEmpty ? library.fuzzyMatches(for: query) : contains
        }
        return ranked.prefix(5).map {
            TaggedFileToken(filename: $0.url.lastPathComponent, fileURL: $0.url)
        }
    }

    private func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: { $0.canBecomeMain && !($0 is CribbleChatPanel) })?
            .makeKeyAndOrderFront(nil)
    }

    /// Locates an in-progress `@mention` at the caret (we treat end-of-string as
    /// the caret). Requires the `@` to start the string or follow whitespace, and
    /// the query to be whitespace-free.
    nonisolated static func activeMentionQuery(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex > text.startIndex {
            let before = text[text.index(before: atIndex)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let query = String(text[queryStart...])
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return (atIndex..<text.endIndex, query)
    }
}
