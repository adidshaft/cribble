import XCTest
@testable import Cribble

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

    @MainActor
    func testEngineChooserShowsForFreshDefaults() {
        withCleanEngineChoiceDefaults {
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
