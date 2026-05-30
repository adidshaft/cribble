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
        let prompt = ContextAssembler.systemPrompt(
            modelName: "Gemma 4",
            currentNote: nil,
            files: [ResolvedFile(filename: "A.md", content: "alpha")]
        )
        XCTAssertTrue(prompt.contains("--- BEGIN FILE: A.md ---"))
        XCTAssertTrue(prompt.contains("alpha"))
        XCTAssertTrue(prompt.contains("--- END FILE: A.md ---"))
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

    func testPerFileTruncation() {
        let big = String(repeating: "x", count: ContextAssembler.perFileCharacterBudget + 500)
        let prompt = ContextAssembler.systemPrompt(
            modelName: "M",
            currentNote: nil,
            files: [ResolvedFile(filename: "Big.md", content: big)]
        )
        XCTAssertTrue(prompt.contains("[truncated]"))
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
}
