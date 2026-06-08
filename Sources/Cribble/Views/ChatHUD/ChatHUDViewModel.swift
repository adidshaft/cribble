import AppKit
import Foundation

private struct ContextDigestCacheKey: Hashable {
    let path: String
    let contentHash: String
}

private enum ContextDigestLimits {
    static let chunkSize = 10_000
    static let maxChunks = 8
    static let budget = 3_500
}

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
        case downloading(ModelLoadProgress)
        case loading
        case ready
        case failed(String)
    }

    // MARK: Conversation
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var attachments: [TaggedFileToken] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastContextReceipt: ContextReceipt?

    // MARK: Autocomplete
    @Published private(set) var autocomplete: FileAutocompleteState?
    /// Slash-command palette suggestions (non-empty when the draft starts "/").
    @Published private(set) var slashCommands: [QuickAction] = []
    @Published private(set) var isSlashCommandQuery = false
    @Published private(set) var extensionQuickActions: [QuickAction] = []

    // MARK: Model
    @Published var selectedModel: LocalModel
    @Published private(set) var modelPhase: ModelPhase = .idle

    /// True until the user has explicitly picked an engine at least once. Drives
    /// the first-run engine chooser shown over the empty state.
    @Published var needsEngineChoice: Bool

    private enum ModelDefaultsKey {
        static let selectedModelID = "chatHUD.selectedModelID"
        static let hasChosenEngine = "chatHUD.hasChosenEngine"
        static let engineChoiceVersion = "chatHUD.engineChoiceVersion"
    }

    /// Status line shown under the model chip / in the input area.
    @Published private(set) var statusMessage: String?

    let greetingName: String

    private let library: MarkdownLibraryStore
    private let semanticIndex: SemanticSearchIndex?
    /// Optional project-intelligence context (project index + summaries) folded
    /// into chat answers as related notes (design plan Phase 1). Set by
    /// `ChatHUDController` when an `IntelligenceEngine` is available.
    var intelligenceContextProvider: (@MainActor () -> [ResolvedFile])?

    /// Whether the user has enabled folding project intelligence into chat. Mirror
    /// of `IntelligenceSettings.useInChat`; toggling calls `onIntelligenceToggle`.
    @Published var useProjectIntelligence = false {
        didSet { if useProjectIntelligence != oldValue { onIntelligenceToggle?(useProjectIntelligence) } }
    }
    var onIntelligenceToggle: ((Bool) -> Void)?
    /// Test/preview override; when set it's used for every model.
    private let injectedEngine: LocalChatEngine?
    private var loadedModelID: String?
    private var generationTask: Task<Void, Never>?
    private var contextDigestCache: [ContextDigestCacheKey: String] = [:]
    private var pendingQuickActionSource: QuickAction.Source?

    /// If no token (and no completion) arrives within this window after the model
    /// is ready, the generation is treated as wedged and force-stopped, so the
    /// HUD never stays stuck with `isGenerating == true` (which would lock out
    /// Send and New Chat). The timer resets on every streamed token, so a slow-
    /// but-progressing answer is never cut off.
    private let generationStallLimit: TimeInterval = 240
    private var lastGenerationActivity = Date()
    init(library: MarkdownLibraryStore, semanticIndex: SemanticSearchIndex? = nil, engine: LocalChatEngine? = nil) {
        self.library = library
        self.semanticIndex = semanticIndex
        self.injectedEngine = engine
        let defaults = UserDefaults.standard
        let savedID = defaults.string(forKey: ModelDefaultsKey.selectedModelID)
        self.selectedModel = savedID.flatMap(ModelCatalog.model(withID:)) ?? ModelCatalog.defaultModel
        self.needsEngineChoice = !Self.hasCompletedEngineChoice(defaults: defaults)
        let fullName = NSFullUserName()
        self.greetingName = fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    func syncEngineChoiceFromDefaults() {
        let defaults = UserDefaults.standard
        if let savedID = defaults.string(forKey: ModelDefaultsKey.selectedModelID),
           let savedModel = ModelCatalog.model(withID: savedID) {
            selectedModel = savedModel
        }
        needsEngineChoice = !Self.hasCompletedEngineChoice(defaults: defaults)
    }

    private static func hasCompletedEngineChoice(defaults: UserDefaults) -> Bool {
        return (defaults.object(forKey: ModelDefaultsKey.hasChosenEngine) as? Bool) == true
    }

    /// The engine for the currently selected model, shared process-wide so the
    /// HUD and Pathfinder reuse one loaded on-device model.
    private func currentEngine() -> LocalChatEngine {
        injectedEngine ?? LocalLLM.shared.engine(for: selectedModel)
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

        // `/` at the very start opens the command palette.
        if text.hasPrefix("/") {
            isSlashCommandQuery = true
            slashCommands = QuickActions.matching(String(text.dropFirst()), extensions: extensionQuickActions)
            autocomplete = nil
            return
        }
        isSlashCommandQuery = false
        slashCommands = []

        guard let mention = Self.activeMentionQuery(in: text) else {
            autocomplete = nil
            return
        }
        autocomplete = FileAutocompleteState(
            query: mention.query,
            matches: searchFiles(matching: mention.query)
        )
    }

    /// Runs a quick action's prompt as a message.
    func runQuickAction(_ action: QuickAction) {
        guard !isGenerating else { return }
        isSlashCommandQuery = false
        slashCommands = []
        autocomplete = nil
        pendingQuickActionSource = action.source
        draft = action.prompt
        send()
    }

    func clearSlashCommandQuery() {
        guard isSlashCommandQuery else { return }
        draft = ""
        slashCommands = []
        isSlashCommandQuery = false
        autocomplete = nil
    }

    func updateExtensionQuickActions(_ actions: [QuickAction]) {
        extensionQuickActions = actions
        if draft.hasPrefix("/") {
            slashCommands = QuickActions.matching(String(draft.dropFirst()), extensions: extensionQuickActions)
        }
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

    /// Download / cloud state for a model, for the picker's state icons.
    func availability(of model: LocalModel) -> ModelAvailability {
        ModelInventory.availability(of: model)
    }

    /// Live download UI state for a model row in the picker.
    struct DownloadDisplay {
        var isActive: Bool
        var fraction: Double?
        var speed: String?
        var loading: Bool
    }

    func downloadDisplay(for model: LocalModel) -> DownloadDisplay {
        guard model.id == selectedModel.id else {
            return DownloadDisplay(isActive: false, fraction: nil, speed: nil, loading: false)
        }
        switch modelPhase {
        case .downloading(let progress):
            return DownloadDisplay(
                isActive: true,
                fraction: progress.fraction > 0 ? progress.fraction : nil,
                speed: Self.formatTransferSpeed(progress.bytesPerSecond),
                loading: false
            )
        case .loading:
            return DownloadDisplay(isActive: true, fraction: nil, speed: nil, loading: true)
        default:
            return DownloadDisplay(isActive: false, fraction: nil, speed: nil, loading: false)
        }
    }

    /// Explicitly downloads (and warms) an on-device model so the user can watch
    /// it complete before chatting, instead of it downloading on first send.
    func downloadModel(_ model: LocalModel) {
        guard model.kind == .localMLX, !ModelInventory.isDownloaded(model) else { return }
        if model.id != selectedModel.id { selectModel(model) }
        Task { _ = await ensureModelReady() }
    }

    // MARK: - Conversation control

    func newChat() {
        guard !isGenerating else { return }
        messages = []
        statusMessage = nil
        lastContextReceipt = nil
    }

    // MARK: - Message actions

    var canInsertIntoCurrentNote: Bool { library.selectedDocument != nil }

    func copyMessage(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        statusMessage = "Copied to clipboard"
    }

    func copyLastContextReceipt() {
        guard let receipt = lastContextReceipt, !receipt.items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.renderContextReceipt(receipt), forType: .string)
        statusMessage = "Copied context receipt"
    }

    func saveMessageAsNote(_ message: ChatMessage) {
        library.presentNewNoteProposal(
            fileName: Self.suggestedFileName(for: message.text),
            content: message.text
        )
        bringMainWindowForward()
        statusMessage = "Review the new note in the main window"
    }

    func insertMessageIntoCurrentNote(_ message: ChatMessage) {
        guard let url = library.selectedDocument?.url else {
            statusMessage = "Open a note first to insert into it"
            return
        }
        library.presentAppendProposal(to: url, content: message.text)
        bringMainWindowForward()
        statusMessage = "Review the insertion in the main window"
    }

    nonisolated static func contextReceiptSummary(_ receipt: ContextReceipt) -> String {
        let included = receipt.items.filter { item in
            item.status == .included || item.status == .summarized || item.status == .truncated
        }.count
        let limited = receipt.items.count - included
        var parts = ["\(included) source\(included == 1 ? "" : "s")"]
        if limited > 0 {
            parts.append("\(limited) limited")
        }
        return parts.joined(separator: ", ")
    }

    nonisolated static func contextReceiptLine(_ item: ContextReceipt.Item) -> String {
        let source = switch item.source {
        case .currentNote: "Current note"
        case .explicitAttachment: "Attachment"
        case .relatedNote: "Related note"
        }
        let status = switch item.status {
        case .included: "included"
        case .truncated: "truncated"
        case .summarized: "summarized"
        case .omitted: "omitted"
        case .blockedNeedsSummary: "needs summary"
        case .unavailable: "unavailable"
        }
        var line = "\(source): \(item.filename) - \(status), \(item.includedCharacters)/\(item.originalCharacters) chars"
        if let reason = item.reason, !reason.isEmpty {
            line += " (\(reason))"
        }
        return line
    }

    nonisolated static func renderContextReceipt(_ receipt: ContextReceipt) -> String {
        guard !receipt.items.isEmpty else { return "No context sources were sent." }
        return receipt.items.map(contextReceiptLine).joined(separator: "\n")
    }

    nonisolated static func extensionLaneSummary(actionCount: Int) -> String {
        if actionCount > 0 {
            return "\(actionCount) extension action\(actionCount == 1 ? "" : "s")"
        }
        return "No extensions yet - start with Help > Open Extension Contribution Guide"
    }

    /// Derives a filename from the answer's first heading/line.
    nonisolated static func suggestedFileName(for text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "AI Note"
        let cleaned = firstLine
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        let title = cleaned.isEmpty ? "AI Note" : String(cleaned.prefix(50))
        return title
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        let quickActionSource = pendingQuickActionSource
        pendingQuickActionSource = nil

        messages.append(ChatMessage(role: .user, text: text, attachments: attachments))
        draft = ""
        attachments = []
        autocomplete = nil
        slashCommands = []

        let placeholder = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(placeholder)
        isGenerating = true

        generationTask = Task { [weak self] in
            await self?.runGeneration(assistantID: placeholder.id, quickActionSource: quickActionSource)
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
        let defaults = UserDefaults.standard
        defaults.set(model.id, forKey: ModelDefaultsKey.selectedModelID)
        defaults.synchronize()
        // Force a reload on next send; loading is lazy and on-demand.
        modelPhase = .idle
        loadedModelID = nil
        statusMessage = nil
    }

    /// Commits the first-run engine choice: persists the pick and dismisses the
    /// chooser. Selecting the already-current model still records the choice.
    func chooseEngine(_ model: LocalModel) {
        let defaults = UserDefaults.standard
        if model.id != selectedModel.id {
            selectModel(model)
        } else {
            defaults.set(model.id, forKey: ModelDefaultsKey.selectedModelID)
        }
        defaults.set(true, forKey: ModelDefaultsKey.hasChosenEngine)
        defaults.set(1, forKey: ModelDefaultsKey.engineChoiceVersion)
        defaults.synchronize()
        needsEngineChoice = false
    }

    // MARK: - Generation

    private func runGeneration(assistantID: UUID, quickActionSource: QuickAction.Source?) async {
        guard await ensureModelReady() else {
            failGeneration("Couldn't load \(selectedModel.name).", assistantID: assistantID)
            return
        }

        let engine = currentEngine()
        let context = await resolveContext(
            engine: engine,
            includesAmbientContext: Self.includesAmbientContext(for: quickActionSource)
        )
        let packet = ContextAssembler.contextPacket(
            modelName: selectedModel.name,
            currentNote: context.current,
            attachments: context.attachments,
            related: context.related
        )
        lastContextReceipt = packet.receipt

        let prompt = ContextAssembler.engineMessages(packet: packet, history: messages)

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

        // Backstop watchdog: force-stop a wedged generation so the HUD recovers
        // on its own even if the user walks away. Resets on each token below.
        lastGenerationActivity = Date()
        let watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                if Date().timeIntervalSince(self.lastGenerationActivity) > self.generationStallLimit {
                    self.timeoutGeneration(assistantID: assistantID)
                    return
                }
            }
        }
        defer { watchdog.cancel() }

        for await delta in stream {
            lastGenerationActivity = Date()
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
        modelPhase = selectedModel.kind.isCloud ? .loading : .downloading(ModelLoadProgress(fraction: 0))
        statusMessage = "Preparing \(selectedModel.name)…"
        let model = selectedModel
        let engine = currentEngine()
        do {
            try await engine.prepare(model: model) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.selectedModel.id == model.id else { return }
                    self.modelPhase = progress.fraction < 1 ? .downloading(progress) : .loading
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

    /// Invoked by the watchdog when a generation stalls. Force-stops the engine
    /// and surfaces a clear, recoverable message.
    private func timeoutGeneration(assistantID: UUID) {
        guard isGenerating else { return }
        cancel()
        failGeneration(
            "Cribble stopped waiting — the model didn't respond. Try again, or pick a different model.",
            assistantID: assistantID
        )
    }

    private func completeGeneration(finalText: String, assistantID: UUID) {
        guard isGenerating else { return }
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].text = finalText.isEmpty ? messages[index].text : finalText
            messages[index].isStreaming = false
        }
        isGenerating = false
        routeActionableOutput(finalText.isEmpty ? currentText(of: assistantID) : finalText)
    }

    private func markCancelled(assistantID: UUID) {
        guard isGenerating else { return }
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
        guard isGenerating else { return }
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

    /// Builds the model context: the note currently open in the reader (so "this
    /// note" / "here" works without tagging) plus every file tagged across the
    /// conversation, deduped by URL.
    nonisolated static func includesAmbientContext(for quickActionSource: QuickAction.Source?) -> Bool {
        guard let quickActionSource else { return true }
        switch quickActionSource {
        case .builtIn:
            return true
        case .extension:
            return false
        }
    }

    private func resolveContext(
        engine: LocalChatEngine,
        includesAmbientContext: Bool
    ) async -> (current: ResolvedFile?, attachments: [ContextAttachment], related: [ResolvedFile]) {
        var seen = Set<URL>()

        // Explicit `@`/`+` attachments are the authoritative context for the
        // conversation — resolve them first.
        var attachments: [ContextAttachment] = []
        var remainingAttachmentBudget = ContextAssembler.totalContextCharacterBudget
        for message in messages where message.role == .user {
            for token in message.attachments where seen.insert(token.fileURL).inserted {
                if let content = readContents(of: token.fileURL) {
                    if content.count <= ContextAssembler.perFileCharacterBudget,
                       content.count <= remainingAttachmentBudget {
                        remainingAttachmentBudget -= content.count
                        attachments.append(ContextAttachment(filename: token.pathLabel, content: content))
                    } else {
                        let digest = await digestForAttachment(
                            token: token,
                            content: content,
                            engine: engine
                        )
                        if let digest {
                            remainingAttachmentBudget = max(0, remainingAttachmentBudget - digest.count)
                        }
                        attachments.append(ContextAttachment(filename: token.pathLabel, content: content, digest: digest))
                    }
                } else {
                    attachments.append(ContextAttachment(
                        unavailable: token.pathLabel,
                        reason: "could not read UTF-8 contents"
                    ))
                }
            }
        }

        // Whether the user has scoped this chat by attaching specific files. When
        // they have, those files ARE the context: injecting the note that happens
        // to be open in the reader (as "CURRENT NOTE") or loose semantic matches
        // (as "RELATED NOTES") only confuses the model — e.g. a fresh "summarize
        // these two files" chat answering about whatever unrelated note is open.
        let userScopedWithAttachments = messages.contains {
            $0.role == .user && !$0.attachments.isEmpty
        }

        // Ambient context — only when the user hasn't scoped with attachments.
        var current: ResolvedFile?
        var related: [ResolvedFile] = []
        if !userScopedWithAttachments {
            if let doc = library.selectedDocument {
                current = ResolvedFile(filename: doc.url.lastPathComponent, content: doc.rawMarkdown)
                seen.insert(doc.url)
            }
        }

        if includesAmbientContext && !userScopedWithAttachments {
            // Vault-aware: pull a few semantically-related notes for the latest
            // question so the assistant can answer about the whole workspace, not
            // just what's open.
            related = await resolveRelatedNotes(excluding: seen)
        }

        // Fold in generated project intelligence (project index) when available,
        // so chat answers benefit from the living knowledge base.
        if includesAmbientContext, let intelligenceContextProvider {
            related.append(contentsOf: intelligenceContextProvider())
        }

        return (current, attachments, related)
    }

    private func digestForAttachment(token: TaggedFileToken, content: String, engine: LocalChatEngine) async -> String? {
        let key = ContextDigestCacheKey(path: token.fileURL.standardizedFileURL.path, contentHash: ContentHasher.hash(content))
        if let cached = contextDigestCache[key] { return cached }

        statusMessage = "Summarizing \(token.filename) for context..."
        do {
            let digest = try await generateAttachmentDigest(
                filename: token.pathLabel,
                content: content,
                engine: engine
            )
            contextDigestCache[key] = digest
            return digest
        } catch is CancellationError {
            return nil
        } catch {
            let digest = Self.extractiveDigest(filename: token.pathLabel, content: content)
            contextDigestCache[key] = digest
            statusMessage = "Using extractive context digest for \(token.filename)"
            return digest
        }
    }

    private func generateAttachmentDigest(filename: String, content: String, engine: LocalChatEngine) async throws -> String {
        let chunks = Self.sampledChunks(
            content,
            chunkSize: ContextDigestLimits.chunkSize,
            maxChunks: ContextDigestLimits.maxChunks
        )
        guard !chunks.isEmpty else { return "" }

        var partials: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let messages = Self.digestMessages(
                filename: filename,
                content: chunk.text,
                label: "chunk \(chunk.index + 1) of \(chunk.total)"
            )
            let partial = try await engine.generate(messages: messages, maxTokens: 360) { _ in }
            partials.append(Self.boundedDigest(partial, maxCharacters: 900))
        }

        if partials.count == 1 {
            return Self.boundedDigest(partials[0], maxCharacters: ContextDigestLimits.budget)
        }

        let sampledNotice = chunks.count < (chunks.first?.total ?? 0)
            ? "Sampled \(chunks.count) chunks across the file, including the beginning and end."
            : "Covered all \(chunks.count) chunks."
        let combined = ([sampledNotice] + partials.enumerated().map { index, partial in
            "## Chunk \(index + 1)\n\(partial)"
        }).joined(separator: "\n\n")
        let messages = Self.digestMessages(
            filename: filename,
            content: combined,
            label: "combined chunk summaries"
        )
        let final = try await engine.generate(messages: messages, maxTokens: 520) { _ in }
        return Self.boundedDigest(final, maxCharacters: ContextDigestLimits.budget)
    }

    nonisolated private static func digestMessages(filename: String, content: String, label: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You create compact context digests for Cribble Chat. Summarize only what is present.
            Preserve concrete names, decisions, constraints, TODOs, unresolved questions, and source facts.
            Do not add advice unless the file says it. Keep the digest dense and under 180 words.
            """),
            EngineMessage(role: .user, content: """
            File: \(filename)
            Segment: \(label)

            --- BEGIN ATTACHED FILE SEGMENT ---
            \(content)
            --- END ATTACHED FILE SEGMENT ---
            """)
        ]
    }

    nonisolated private static func sampledChunks(_ content: String, chunkSize: Int, maxChunks: Int) -> [(index: Int, total: Int, text: String)] {
        guard !content.isEmpty, chunkSize > 0, maxChunks > 0 else { return [] }
        var chunks: [String] = []
        var start = content.startIndex
        while start < content.endIndex {
            let end = content.index(start, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
            chunks.append(String(content[start..<end]))
            start = end
        }
        guard chunks.count > maxChunks else {
            return chunks.enumerated().map { ($0.offset, chunks.count, $0.element) }
        }

        let span = Double(chunks.count - 1)
        let steps = Double(maxChunks - 1)
        var indices = Set<Int>()
        for slot in 0..<maxChunks {
            indices.insert(Int((Double(slot) * span / steps).rounded()))
        }
        return indices.sorted().map { ($0, chunks.count, chunks[$0]) }
    }

    nonisolated private static func boundedDigest(_ text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return String(trimmed[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n...[digest truncated]..."
    }

    nonisolated private static func extractiveDigest(filename: String, content: String) -> String {
        let target = max(1, ContextDigestLimits.budget / 3)
        let head = String(content.prefix(target))
        let tail = String(content.suffix(target))
        let middleStart = content.index(content.startIndex, offsetBy: max(0, (content.count - target) / 2), limitedBy: content.endIndex) ?? content.startIndex
        let middleEnd = content.index(middleStart, offsetBy: target, limitedBy: content.endIndex) ?? content.endIndex
        let middle = String(content[middleStart..<middleEnd])
        return boundedDigest("""
        Extractive context digest for \(filename). A model summary was unavailable, so Cribble included bounded excerpts from the beginning, middle, and end of the attached file.

        ## Beginning
        \(head)

        ## Middle
        \(middle)

        ## End
        \(tail)
        """, maxCharacters: ContextDigestLimits.budget)
    }

    /// Up to 3 related notes found by the on-device semantic index for the most
    /// recent user message. Each is trimmed so the prompt stays lean.
    private func resolveRelatedNotes(excluding: Set<URL>) async -> [ResolvedFile] {
        guard let semanticIndex,
              let query = messages.last(where: { $0.role == .user })?.text,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }

        let hits = await semanticIndex.relatedNotes(to: query, limit: 3, excluding: excluding)
        return hits.compactMap { hit in
            guard let content = readContents(of: hit.url) else { return nil }
            let trimmed = content.count > 3000 ? String(content.prefix(3000)) + "\n…" : content
            return ResolvedFile(filename: hit.url.lastPathComponent, content: trimmed)
        }
    }

    /// Reads a file, honoring security scope for files attached via Finder.
    private func readContents(of url: URL) -> String? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func searchFiles(matching query: String) -> [TaggedFileToken] {
        let documents = library.documents
        let ranked: [MarkdownDocumentMeta]
        if query.isEmpty {
            ranked = Array(documents.prefix(6))
        } else {
            // Path-aware: match the relative path (so "folder/file" and folder
            // names work), the filename, and the title.
            let lowered = query.lowercased()
            let contains = documents.filter { doc in
                let rel = (library.relativePath(for: doc.url) ?? doc.url.lastPathComponent).lowercased()
                return rel.contains(lowered) || doc.title.lowercased().contains(lowered)
            }
            ranked = contains.isEmpty ? library.fuzzyMatches(for: query) : contains
        }
        return ranked.prefix(6).map { token(for: $0.url) }
    }

    private func token(for url: URL) -> TaggedFileToken {
        TaggedFileToken(
            filename: url.lastPathComponent,
            fileURL: url,
            relativePath: library.relativePath(for: url)
        )
    }

    /// Total notes available to attach (for the "Attach all" menu item).
    var allNotesCount: Int { library.documents.count }

    /// Attaches every note in the workspace as context.
    func attachAllNotes() {
        for doc in library.documents { addAttachment(token(for: doc.url)) }
    }

    /// Opens a Finder panel to attach any file as context — including files that
    /// aren't part of the workspace (used, not added).
    func chooseFileToAttach() {
        let panel = NSOpenPanel()
        panel.title = "Choose files to use as context"
        panel.prompt = "Attach"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let folder = library.activeRootURL { panel.directoryURL = folder }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let rel = library.relativePath(for: url)
            addAttachment(TaggedFileToken(
                filename: url.lastPathComponent,
                fileURL: url,
                relativePath: rel,
                isExternal: rel == nil
            ))
        }
    }

    private func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: { $0.canBecomeMain && !($0 is CribbleChatPanel) })?
            .makeKeyAndOrderFront(nil)
    }

    nonisolated static func formatTransferSpeed(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
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
