import XCTest
@testable import Cribble

/// Deterministic engine for view-model tests: replies with scripted answers
/// and records the prompts / limits it was handed.
private final class ScriptedChatEngine: LocalChatEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String]
    private var prompts: [[EngineMessage]] = []
    private var maxTokensSeen: [Int] = []

    init(responses: [String]) {
        self.responses = responses
    }

    var recordedPrompts: [[EngineMessage]] { lock.withLock { prompts } }
    var recordedMaxTokens: [Int] { lock.withLock { maxTokensSeen } }

    func prepare(
        model: LocalModel,
        onProgress: @escaping @Sendable (ModelLoadProgress) -> Void
    ) async throws {
        onProgress(ModelLoadProgress(fraction: 1))
    }

    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let next: String = lock.withLock {
            prompts.append(messages)
            maxTokensSeen.append(maxTokens)
            return responses.isEmpty ? "" : responses.removeFirst()
        }
        onToken(next)
        return next
    }

    func cancelGeneration() async {}
}

final class ChatHUDLogicTests: XCTestCase {

    // MARK: - @mention detection

    func testMentionQueryAtEndOfString() {
        let result = ChatHUDViewModel.activeMentionQuery(in: "link these @ide")
        XCTAssertEqual(result?.query, "ide")
    }

    func testMentionQueryAtStart() {
        let result = ChatHUDViewModel.activeMentionQuery(in: "@notes")
        XCTAssertEqual(result?.query, "notes")
    }

    func testMentionRequiresWhitespaceBeforeAt() {
        // An "@" embedded in a word (e.g. an email) should not trigger.
        XCTAssertNil(ChatHUDViewModel.activeMentionQuery(in: "mail me at foo@bar"))
    }

    func testMentionEndsAtWhitespace() {
        // Once the user types a space, the mention is committed/closed.
        XCTAssertNil(ChatHUDViewModel.activeMentionQuery(in: "@notes and then"))
    }

    func testEmptyMentionAfterBareAt() {
        let result = ChatHUDViewModel.activeMentionQuery(in: "see @")
        XCTAssertEqual(result?.query, "")
    }

    // MARK: - CREATE block parsing

    func testParsesCreateBlock() {
        let output = """
        Sure, here is a new note:

        ```CREATE: ideas.md
        # Ideas

        - first
        - second
        ```
        """
        guard case let .create(fileName, content) = ChatOutputParser.parse(output) else {
            return XCTFail("Expected a create proposal")
        }
        XCTAssertEqual(fileName, "ideas.md")
        XCTAssertTrue(content.contains("# Ideas"))
        XCTAssertTrue(content.contains("- second"))
    }

    func testCreateBlockTakesPrecedenceOverProse() {
        let output = "```CREATE: a.md\nhello\n```"
        if case .create = ChatOutputParser.parse(output) {} else {
            XCTFail("Expected create")
        }
    }

    // MARK: - Diff parsing

    func testParsesUnifiedDiff() {
        let output = """
        Here are the link changes:

        --- a/NoteA.md
        +++ b/NoteA.md
        @@ -1,2 +1,2 @@
         # Note A
        -See also other.
        +See also [[Other]].
        """
        guard case let .diff(diff) = ChatOutputParser.parse(output) else {
            return XCTFail("Expected a diff proposal")
        }
        XCTAssertEqual(diff.files.first?.newPath, "NoteA.md")
    }

    func testPlainProseProducesNoAction() {
        let output = "Your notes are about cooking and travel. Nothing to change."
        XCTAssertEqual(ChatOutputParser.parse(output), .none)
    }

    // MARK: - Context assembly

    func testSystemPromptInlinesAttachedFiles() {
        let packet = ContextAssembler.contextPacket(
            modelName: "Gemma 4",
            currentNote: nil,
            files: [ResolvedFile(filename: "A.md", content: "alpha")]
        )
        let prompt = packet.systemPrompt
        XCTAssertTrue(prompt.contains("--- BEGIN FILE: A.md ---"))
        XCTAssertTrue(prompt.contains("alpha"))
        XCTAssertTrue(prompt.contains("--- END FILE: A.md ---"))
        XCTAssertTrue(prompt.contains("CONTEXT RECEIPT"))
        XCTAssertEqual(packet.receipt.items.first?.status, .included)
        XCTAssertTrue(prompt.contains("Unified Diff"))
        XCTAssertTrue(prompt.contains("CREATE:"))
    }

    func testContextReceiptDisplayHelpers() {
        let receipt = ContextReceipt(items: [
            ContextReceipt.Item(
                source: .currentNote,
                filename: "Current.md",
                status: .included,
                originalCharacters: 20,
                includedCharacters: 20,
                reason: nil
            ),
            ContextReceipt.Item(
                source: .explicitAttachment,
                filename: "Huge.md",
                status: .blockedNeedsSummary,
                originalCharacters: 80_000,
                includedCharacters: 0,
                reason: "explicit attachment exceeds per-file context budget"
            )
        ])

        XCTAssertEqual(ChatHUDViewModel.contextReceiptSummary(receipt), "1 source, 1 limited")
        XCTAssertTrue(ChatHUDViewModel.renderContextReceipt(receipt).contains("Current note: Current.md - included, 20/20 chars"))
        XCTAssertTrue(ChatHUDViewModel.renderContextReceipt(receipt).contains("Attachment: Huge.md - needs summary"))
    }

    func testExtensionLaneSummaryGuidesEmptyAndInstalledStates() {
        XCTAssertEqual(
            ChatHUDViewModel.extensionLaneSummary(actionCount: 0),
            "No extensions yet - start with Settings > Extensions > Contribution Guide"
        )
        XCTAssertEqual(ChatHUDViewModel.extensionLaneSummary(actionCount: 1), "1 extension action")
        XCTAssertEqual(ChatHUDViewModel.extensionLaneSummary(actionCount: 3), "3 extension actions")
    }

    func testSlashCommandIdeaHandoffKeepsExtensionGuardrails() {
        let handoff = ChatHUDViewModel.renderSlashCommandIdea(query: "  /brief  ")

        XCTAssertTrue(handoff.contains("# Extension quick-action idea"))
        XCTAssertTrue(handoff.contains("Missing command: /brief"))
        XCTAssertTrue(handoff.contains("declarative quick action"))
        XCTAssertTrue(handoff.contains("read-current-note only"))
        XCTAssertTrue(handoff.contains("native SwiftUI surfaces only"))
        XCTAssertTrue(handoff.contains("Settings > Extensions > Copy Proposal"))
    }

    func testSystemPromptIncludesCurrentNote() {
        let prompt = ContextAssembler.systemPrompt(
            modelName: "Gemma 4",
            currentNote: ResolvedFile(filename: "Reading.md", content: "setup steps"),
            files: []
        )
        XCTAssertTrue(prompt.contains("BEGIN CURRENT NOTE: Reading.md"))
        XCTAssertTrue(prompt.contains("setup steps"))
        XCTAssertTrue(prompt.contains("this note"))
    }

    func testSystemPromptWithoutNotes() {
        let prompt = ContextAssembler.systemPrompt(modelName: "Gemma 4", currentNote: nil, files: [])
        XCTAssertTrue(prompt.contains("No notes are attached"))
        XCTAssertFalse(prompt.contains("BEGIN FILE"))
    }

    func testEngineMessagesSkipEmptyStreamingTurn() {
        let history = [
            ChatMessage(role: .user, text: "hi"),
            ChatMessage(role: .assistant, text: "", isStreaming: true)
        ]
        let messages = ContextAssembler.engineMessages(
            modelName: "M", history: history, currentNote: nil, files: []
        )
        // system + user only; the empty streaming placeholder is dropped.
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.role, .system)
        XCTAssertEqual(messages.last?.role, .user)
    }

    func testRelatedNotesAppearInPrompt() {
        let prompt = ContextAssembler.systemPrompt(
            modelName: "M",
            currentNote: nil,
            files: [],
            related: [ResolvedFile(filename: "Found.md", content: "auto retrieved")]
        )
        XCTAssertTrue(prompt.contains("RELATED NOTES"))
        XCTAssertTrue(prompt.contains("BEGIN RELATED: Found.md"))
        XCTAssertTrue(prompt.contains("auto retrieved"))
    }

    func testSuggestedFileNameFromHeading() {
        XCTAssertEqual(ChatHUDViewModel.suggestedFileName(for: "# Bug Status Index\n\n- a"), "Bug Status Index")
        XCTAssertEqual(ChatHUDViewModel.suggestedFileName(for: "\n\n   "), "AI Note")
    }

    func testSlashCommandsFilter() {
        XCTAssertEqual(QuickActions.matching("").count, QuickActions.all.count)
        XCTAssertTrue(QuickActions.matching("sum").contains { $0.id == "summarize" })
        XCTAssertTrue(QuickActions.matching("index").contains { $0.id == "index" })
        XCTAssertTrue(QuickActions.matching("daily").contains { $0.id == "today-note" })
        XCTAssertTrue(QuickActions.matching("tasks").contains { $0.id == "extract-tasks" })
    }

    func testBuiltInQuickActionsHaveShortDescriptions() {
        let actions = QuickActions.builtIns(todayTitle: "2026-06-08")

        XCTAssertTrue(actions.allSatisfy { $0.description?.isEmpty == false })
        XCTAssertTrue(actions.allSatisfy { ($0.description?.count ?? 0) <= 48 })
    }

    func testSlashCommandsMatchAliasesAndRankStrongMatchesFirst() {
        let matches = QuickActions.matching("eli5")

        XCTAssertEqual(matches.first?.id, "simplify")
    }

    func testDailyQuickActionCreatesDatedDailyNoteBlock() {
        let action = QuickActions.builtIns(todayTitle: "2026-06-08")
            .first { $0.id == "today-note" }

        XCTAssertEqual(action?.title, "Draft today")
        XCTAssertEqual(action?.icon, "calendar.badge.plus")
        XCTAssertTrue(action?.prompt.contains("CREATE: Daily/2026-06-08.md") == true)
        XCTAssertTrue(action?.prompt.contains("block only") == true)
    }

    func testExtractTasksQuickActionCreatesReviewedTasksBlock() {
        let action = QuickActions.builtIns(todayTitle: "2026-06-08")
            .first { $0.id == "extract-tasks" }

        XCTAssertEqual(action?.title, "Extract tasks")
        XCTAssertEqual(action?.icon, "checklist")
        XCTAssertTrue(action?.prompt.contains("CREATE: Tasks.md") == true)
        XCTAssertTrue(action?.prompt.contains("Markdown checkboxes") == true)
        XCTAssertTrue(action?.prompt.contains("block only") == true)
    }

    func testSlashCommandsMatchExtensionSourceName() {
        let extensionAction = QuickAction(
            id: "remote-review",
            title: "Review with Runner",
            icon: "bolt.horizontal",
            prompt: "Review this note using the configured runner.",
            source: .extension("Remote Intelligence")
        )

        let matches = QuickActions.matching("remote", extensions: [extensionAction])

        XCTAssertTrue(matches.contains(extensionAction))
    }

    func testExtensionQuickActionsSuppressAmbientContext() {
        XCTAssertTrue(ChatHUDViewModel.includesAmbientContext(for: nil))
        XCTAssertTrue(ChatHUDViewModel.includesAmbientContext(for: .builtIn))
        XCTAssertFalse(ChatHUDViewModel.includesAmbientContext(for: .extension("Research Actions")))
    }

    @MainActor
    func testSlashCommandNoMatchStateCanBeCleared() {
        let viewModel = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))

        viewModel.updateDraft("/zzzzzz")

        XCTAssertTrue(viewModel.isSlashCommandQuery)
        XCTAssertTrue(viewModel.slashCommands.isEmpty)

        viewModel.clearSlashCommandQuery()

        XCTAssertFalse(viewModel.isSlashCommandQuery)
        XCTAssertTrue(viewModel.draft.isEmpty)
    }

    func testConnectionMessagesIncludeBothNotes() {
        let messages = ContextAssembler.connectionMessages(
            modelName: "Gemma 4",
            source: ResolvedFile(filename: "Auth.md", content: "tokens and login"),
            target: ResolvedFile(filename: "API.md", content: "endpoints and keys")
        )
        XCTAssertEqual(messages.first?.role, .system)
        let system = messages.first?.content ?? ""
        XCTAssertTrue(system.contains("NOTE A: Auth.md"))
        XCTAssertTrue(system.contains("tokens and login"))
        XCTAssertTrue(system.contains("NOTE B: API.md"))
        XCTAssertTrue(system.contains("endpoints and keys"))
        XCTAssertTrue(system.contains("single concise paragraph"))
        XCTAssertEqual(messages.last?.role, .user)
    }

    func testTotalContextBudgetBlocksExcessExplicitFiles() {
        // 12 files × ~10k each = ~120k, well past the 60k aggregate budget.
        let chunk = String(repeating: "x", count: 10_000)
        let files = (0..<12).map { ResolvedFile(filename: "F\($0).md", content: chunk) }
        let packet = ContextAssembler.contextPacket(modelName: "M", currentNote: nil, files: files)
        let prompt = packet.systemPrompt

        XCTAssertTrue(prompt.contains("blocked_needs_summary"))
        XCTAssertTrue(packet.receipt.hasBlockedExplicitAttachments)
        // The inlined content must respect the aggregate budget (plus a little
        // scaffolding for the intro, headers, receipts, warnings, and rules).
        XCTAssertLessThan(prompt.count, ContextAssembler.totalContextCharacterBudget + 6_000)
        // The first files survive; later ones are dropped.
        XCTAssertTrue(prompt.contains("BEGIN FILE: F0.md"))
        XCTAssertFalse(prompt.contains("BEGIN FILE: F11.md"))
        XCTAssertTrue(prompt.contains("F11.md: blocked_needs_summary"))
    }

    func testTotalContextBudgetKeepsSmallContexts() {
        // A handful of small files all fit — no omission notice.
        let files = (0..<3).map { ResolvedFile(filename: "F\($0).md", content: "small") }
        let packet = ContextAssembler.contextPacket(modelName: "M", currentNote: nil, files: files)
        let prompt = packet.systemPrompt
        XCTAssertFalse(prompt.contains("blocked_needs_summary"))
        XCTAssertFalse(packet.receipt.hasBlockedExplicitAttachments)
        XCTAssertTrue(prompt.contains("BEGIN FILE: F2.md"))
    }

    func testCurrentNoteAndTaggedFilesPrioritizedOverRelated() {
        // Budget exhausted by the current note + tagged file; loose related notes
        // are the first to be dropped.
        let big = String(repeating: "y", count: ContextAssembler.perFileCharacterBudget)
        let prompt = ContextAssembler.systemPrompt(
            modelName: "M",
            currentNote: ResolvedFile(filename: "Open.md", content: big),
            files: (0..<5).map { ResolvedFile(filename: "Tag\($0).md", content: big) },
            related: [ResolvedFile(filename: "Loose.md", content: big)]
        )
        XCTAssertTrue(prompt.contains("BEGIN CURRENT NOTE: Open.md"))
        XCTAssertFalse(prompt.contains("BEGIN RELATED: Loose.md"))
        XCTAssertTrue(prompt.contains("blocked_needs_summary"))
        XCTAssertTrue(prompt.contains("context_budget_exceeded"))
    }

    func testOversizedExplicitAttachmentIsBlockedNeedsSummary() {
        let big = String(repeating: "x", count: ContextAssembler.perFileCharacterBudget + 500)
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: nil,
            files: [ResolvedFile(filename: "Big.md", content: big)]
        )
        XCTAssertFalse(packet.systemPrompt.contains("BEGIN FILE: Big.md"))
        XCTAssertTrue(packet.systemPrompt.contains("Big.md: blocked_needs_summary"))
        XCTAssertEqual(packet.receipt.items.first?.status, .blockedNeedsSummary)
        XCTAssertEqual(packet.receipt.items.first?.originalCharacters, big.count)
        XCTAssertEqual(packet.receipt.items.first?.includedCharacters, 0)
    }

    func testOversizedExplicitAttachmentUsesDigestWhenAvailable() {
        let big = String(repeating: "x", count: ContextAssembler.perFileCharacterBudget + 500)
        let digest = "Whole-file digest with beginning, middle, and end."
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: nil,
            attachments: [ContextAttachment(filename: "Big.md", content: big, digest: digest)]
        )

        XCTAssertTrue(packet.systemPrompt.contains("BEGIN FILE SUMMARY: Big.md"))
        XCTAssertTrue(packet.systemPrompt.contains(digest))
        XCTAssertFalse(packet.systemPrompt.contains("Big.md: blocked_needs_summary"))
        XCTAssertEqual(packet.receipt.items.first?.status, .summarized)
        XCTAssertEqual(packet.receipt.items.first?.includedCharacters, digest.count)
    }

    func testCurrentNoteCanStillTruncateWithReceipt() {
        let big = String(repeating: "x", count: ContextAssembler.perFileCharacterBudget + 500)
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: ResolvedFile(filename: "Big.md", content: big),
            files: []
        )
        XCTAssertTrue(packet.systemPrompt.contains("[truncated]"))
        XCTAssertEqual(packet.receipt.items.first?.status, .truncated)
    }

    func testUnavailableExplicitAttachmentHasReceipt() {
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: nil,
            attachments: [ContextAttachment(unavailable: "Missing.md", reason: "could not read UTF-8 contents")]
        )
        XCTAssertTrue(packet.systemPrompt.contains("attachment_unavailable"))
        XCTAssertTrue(packet.systemPrompt.contains("Missing.md: unavailable"))
        XCTAssertEqual(packet.receipt.items.first?.status, .unavailable)
    }

    // MARK: - Catalog

    func testCatalogHasDefaultAndUniqueIDs() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
        XCTAssertTrue(ModelCatalog.all.contains { $0.id == ModelCatalog.defaultModel.id })
        XCTAssertEqual(Set(ModelCatalog.all.map(\.id)).count, ModelCatalog.all.count)
    }

    func testCatalogHasLocalAndCloudModels() {
        XCTAssertFalse(ModelCatalog.localModels.isEmpty)
        XCTAssertFalse(ModelCatalog.cloudModels.isEmpty)
        // Default works out of the box → must be a cloud provider.
        XCTAssertTrue(ModelCatalog.defaultModel.kind.isCloud)
    }

    func testModelDataBoundaryLabelsDistinguishLocalAndCloudChoices() {
        let local = ModelCatalog.localModels.first!
        XCTAssertTrue(local.dataBoundaryLabel.contains("stay on this Mac"))

        let claude = ModelCatalog.all.first { $0.kind == .claudeCLI }!
        XCTAssertTrue(claude.dataBoundaryLabel.contains("Claude CLI"))
        XCTAssertTrue(claude.dataBoundaryLabel.contains("note context is sent"))

        let codex = ModelCatalog.all.first { $0.kind == .codexCLI }!
        XCTAssertTrue(codex.dataBoundaryLabel.contains("Codex CLI"))
        XCTAssertTrue(codex.dataBoundaryLabel.contains("note context is sent"))
    }

    @MainActor
    func testEngineChooserShowsForFreshDefaults() {
        withCleanEngineChoiceDefaults {
            let viewModel = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            XCTAssertTrue(viewModel.needsEngineChoice)
            XCTAssertEqual(viewModel.selectedModel.id, ModelCatalog.defaultModel.id)
        }
    }

    @MainActor
    func testEngineChooserShowsWhenVersionMarkerRemainsButChoiceKeysAreDeleted() {
        withCleanEngineChoiceDefaults {
            UserDefaults.standard.set(1, forKey: "chatHUD.engineChoiceVersion")
            let viewModel = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            XCTAssertTrue(viewModel.needsEngineChoice)
            XCTAssertEqual(viewModel.selectedModel.id, ModelCatalog.defaultModel.id)
        }
    }

    @MainActor
    func testEngineChoicePersistsAcrossViewModelRecreation() {
        withCleanEngineChoiceDefaults {
            let chosen = ModelCatalog.cloudModels.last ?? ModelCatalog.defaultModel
            let first = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            first.chooseEngine(chosen)

            XCTAssertFalse(first.needsEngineChoice)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "chatHUD.selectedModelID"), chosen.id)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: "chatHUD.hasChosenEngine"))
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "chatHUD.engineChoiceVersion"), 1)

            let recreated = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            XCTAssertFalse(recreated.needsEngineChoice)
            XCTAssertEqual(recreated.selectedModel.id, chosen.id)
        }
    }

    @MainActor
    func testEngineChoiceSyncRestoresChooserWhenChoiceFlagIsDeleted() {
        withCleanEngineChoiceDefaults {
            let chosen = ModelCatalog.cloudModels.last ?? ModelCatalog.defaultModel
            let viewModel = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            viewModel.chooseEngine(chosen)
            XCTAssertFalse(viewModel.needsEngineChoice)

            UserDefaults.standard.removeObject(forKey: "chatHUD.hasChosenEngine")
            viewModel.syncEngineChoiceFromDefaults()

            XCTAssertTrue(viewModel.needsEngineChoice)
            XCTAssertEqual(viewModel.selectedModel.id, chosen.id)
        }
    }

    func testCLIFlattenIncludesSystemAndTurns() {
        let prompt = CLIChatEngine.flatten([
            EngineMessage(role: .system, content: "RULES"),
            EngineMessage(role: .user, content: "hello"),
            EngineMessage(role: .assistant, content: "hi"),
            EngineMessage(role: .user, content: "again")
        ])
        XCTAssertTrue(prompt.contains("RULES"))
        XCTAssertTrue(prompt.contains("User: hello"))
        XCTAssertTrue(prompt.contains("Assistant: hi"))
        XCTAssertTrue(prompt.hasSuffix("Assistant:"))
    }

    // MARK: - Transcript persistence

    @MainActor
    func testTranscriptRoundTripSettlesStreamingTurns() {
        let store = makeTemporaryTranscriptStore()
        defer { store.clear() }

        store.save([
            ChatMessage(role: .user, text: "question"),
            ChatMessage(role: .assistant, text: "partial answer", isStreaming: true),
            ChatMessage(role: .assistant, text: "", isStreaming: true)
        ])
        let restored = store.load()

        // The empty in-flight placeholder is dropped; the partial answer is
        // kept but settled so the HUD never restores mid-generation.
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].text, "question")
        XCTAssertEqual(restored[1].text, "partial answer")
        XCTAssertFalse(restored.contains { $0.isStreaming })
    }

    @MainActor
    func testTranscriptBoundsPersistedLength() {
        let store = makeTemporaryTranscriptStore()
        defer { store.clear() }

        let long = (0..<(ChatTranscriptStore.maxPersistedMessages + 40)).map {
            ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "turn \($0)")
        }
        store.save(long)
        let restored = store.load()

        XCTAssertEqual(restored.count, ChatTranscriptStore.maxPersistedMessages)
        XCTAssertEqual(restored.last?.text, long.last?.text)
    }

    @MainActor
    func testTranscriptClearedBySavingEmptyConversation() {
        let store = makeTemporaryTranscriptStore()
        store.save([ChatMessage(role: .user, text: "hi")])
        XCTAssertFalse(store.load().isEmpty)

        store.save([])
        XCTAssertTrue(store.load().isEmpty)
    }

    @MainActor
    func testConversationSurvivesViewModelRecreation() async throws {
        let store = makeTemporaryTranscriptStore()
        defer { store.clear() }

        let first = ChatHUDViewModel(
            library: MarkdownLibraryStore(restore: false, includeBundledDemo: false),
            engine: ScriptedChatEngine(responses: ["remembered answer"]),
            transcriptStore: store
        )
        first.updateDraft("remember me")
        first.send()
        try await waitUntilSettled(first)

        let recreated = ChatHUDViewModel(
            library: MarkdownLibraryStore(restore: false, includeBundledDemo: false),
            engine: ScriptedChatEngine(responses: []),
            transcriptStore: store
        )
        XCTAssertEqual(recreated.messages.count, 2)
        XCTAssertEqual(recreated.messages.first?.text, "remember me")
        XCTAssertEqual(recreated.messages.last?.text, "remembered answer")

        // New Chat clears the persisted transcript too.
        recreated.newChat()
        XCTAssertTrue(store.load().isEmpty)
    }

    @MainActor
    private func makeTemporaryTranscriptStore() -> ChatTranscriptStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cribble-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ChatTranscript.json")
        return ChatTranscriptStore(fileURL: url)
    }

    func testProjectIntelligenceGetsDedicatedPromptLane() {
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: nil,
            attachments: [],
            related: [ResolvedFile(filename: "Loose.md", content: "semantic match")],
            intelligence: [ResolvedFile(filename: "Project — Intelligence Index", content: "workspace map")]
        )
        let prompt = packet.systemPrompt

        XCTAssertTrue(prompt.contains("PROJECT INTELLIGENCE"))
        XCTAssertTrue(prompt.contains("BEGIN INTELLIGENCE: Project — Intelligence Index"))
        XCTAssertTrue(prompt.contains("workspace map"))
        // The loose semantic lane stays separate.
        XCTAssertTrue(prompt.contains("BEGIN RELATED: Loose.md"))
        XCTAssertTrue(packet.receipt.items.contains {
            $0.source == .projectIntelligence && $0.status == .included
        })
    }

    func testProjectIntelligenceOutranksRelatedNotesInBudget() {
        // Attachments leave 10k of budget; the 8k curated index must fit whole
        // while the 4k loose semantic match gets squeezed (truncated), proving
        // the intelligence lane is budgeted first.
        let attachments = (0..<5).map {
            ContextAttachment(filename: "A\($0).md", content: String(repeating: "a", count: 10_000))
        }
        let packet = ContextAssembler.contextPacket(
            modelName: "M",
            currentNote: nil,
            attachments: attachments,
            related: [ResolvedFile(filename: "Loose.md", content: String(repeating: "r", count: 4_000))],
            intelligence: [ResolvedFile(filename: "Index.md", content: String(repeating: "i", count: 8_000))]
        )

        let intelligenceItem = packet.receipt.items.first { $0.source == .projectIntelligence }
        let relatedItem = packet.receipt.items.first { $0.source == .relatedNote }
        XCTAssertEqual(intelligenceItem?.status, .included)
        XCTAssertNotEqual(relatedItem?.status, .included)
    }

    // MARK: - Intelligence offer

    @MainActor
    func testIntelligenceOfferShownOnlyWhenAvailableAndOff() {
        let viewModel = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))

        // No provider wired (no intelligence engine): never offer.
        XCTAssertFalse(viewModel.canOfferIntelligence)

        viewModel.intelligenceAvailabilityProvider = { true }
        XCTAssertTrue(viewModel.canOfferIntelligence)

        // Once the user opts in, the offer disappears.
        viewModel.useProjectIntelligence = true
        XCTAssertFalse(viewModel.canOfferIntelligence)

        // No index available: nothing to offer even when off.
        viewModel.useProjectIntelligence = false
        viewModel.intelligenceAvailabilityProvider = { false }
        XCTAssertFalse(viewModel.canOfferIntelligence)
    }

    // MARK: - Regenerate

    @MainActor
    func testRegenerateReplacesLastAssistantAnswer() async throws {
        let engine = ScriptedChatEngine(responses: ["first answer", "second answer"])
        let viewModel = ChatHUDViewModel(
            library: MarkdownLibraryStore(restore: false, includeBundledDemo: false),
            engine: engine
        )

        XCTAssertFalse(viewModel.canRegenerate)

        viewModel.updateDraft("hello there")
        viewModel.send()
        try await waitUntilSettled(viewModel)

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.text, "first answer")
        XCTAssertTrue(viewModel.canRegenerate)

        viewModel.regenerateLastAnswer()
        try await waitUntilSettled(viewModel)

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.text, "second answer")
        XCTAssertTrue(viewModel.canRegenerate)

        // The regenerated prompt must end at the original user turn — the
        // discarded first answer must not leak back into the conversation.
        let resentPrompt = engine.recordedPrompts.last ?? []
        XCTAssertEqual(resentPrompt.last?.role, .user)
        XCTAssertEqual(resentPrompt.last?.content, "hello there")
        XCTAssertFalse(resentPrompt.contains { $0.content == "first answer" })
    }

    @MainActor
    func testRecallLastQuestionRestoresDraft() async throws {
        let engine = ScriptedChatEngine(responses: ["an answer"])
        let viewModel = ChatHUDViewModel(
            library: MarkdownLibraryStore(restore: false, includeBundledDemo: false),
            engine: engine
        )

        // Nothing to recall on a fresh chat.
        XCTAssertFalse(viewModel.recallLastQuestion())

        viewModel.updateDraft("what links these notes?")
        viewModel.send()
        try await waitUntilSettled(viewModel)
        XCTAssertTrue(viewModel.draft.isEmpty)

        XCTAssertTrue(viewModel.recallLastQuestion())
        XCTAssertEqual(viewModel.draft, "what links these notes?")

        // A non-empty draft is never clobbered by recall.
        viewModel.updateDraft("edited question")
        XCTAssertFalse(viewModel.recallLastQuestion())
        XCTAssertEqual(viewModel.draft, "edited question")
    }

    @MainActor
    func testGenerationUsesRaisedAnswerTokenLimit() async throws {
        let engine = ScriptedChatEngine(responses: ["ok"])
        let viewModel = ChatHUDViewModel(
            library: MarkdownLibraryStore(restore: false, includeBundledDemo: false),
            engine: engine
        )

        viewModel.updateDraft("hi")
        viewModel.send()
        try await waitUntilSettled(viewModel)

        XCTAssertEqual(engine.recordedMaxTokens.last, ChatHUDViewModel.answerTokenLimit)
        XCTAssertGreaterThanOrEqual(ChatHUDViewModel.answerTokenLimit, 2048)
    }

    @MainActor
    private func waitUntilSettled(
        _ viewModel: ChatHUDViewModel,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.isGenerating {
            if Date() > deadline {
                return XCTFail("Generation did not settle within \(timeout)s")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func withCleanEngineChoiceDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let selectedModelID = defaults.object(forKey: "chatHUD.selectedModelID")
        let hasChosenEngine = defaults.object(forKey: "chatHUD.hasChosenEngine")
        let engineChoiceVersion = defaults.object(forKey: "chatHUD.engineChoiceVersion")
        defaults.removeObject(forKey: "chatHUD.selectedModelID")
        defaults.removeObject(forKey: "chatHUD.hasChosenEngine")
        defaults.removeObject(forKey: "chatHUD.engineChoiceVersion")
        defer {
            if let selectedModelID {
                defaults.set(selectedModelID, forKey: "chatHUD.selectedModelID")
            } else {
                defaults.removeObject(forKey: "chatHUD.selectedModelID")
            }

            if let hasChosenEngine {
                defaults.set(hasChosenEngine, forKey: "chatHUD.hasChosenEngine")
            } else {
                defaults.removeObject(forKey: "chatHUD.hasChosenEngine")
            }

            if let engineChoiceVersion {
                defaults.set(engineChoiceVersion, forKey: "chatHUD.engineChoiceVersion")
            } else {
                defaults.removeObject(forKey: "chatHUD.engineChoiceVersion")
            }
        }
        body()
    }
}
