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
            files: [ResolvedFile(filename: "A.md", content: "alpha")]
        )
        XCTAssertTrue(prompt.contains("--- BEGIN FILE: A.md ---"))
        XCTAssertTrue(prompt.contains("alpha"))
        XCTAssertTrue(prompt.contains("--- END FILE: A.md ---"))
        XCTAssertTrue(prompt.contains("Unified Diff"))
        XCTAssertTrue(prompt.contains("CREATE:"))
    }

    func testSystemPromptWithoutFiles() {
        let prompt = ContextAssembler.systemPrompt(modelName: "Gemma 4", files: [])
        XCTAssertTrue(prompt.contains("not attached any notes"))
        XCTAssertFalse(prompt.contains("BEGIN FILE"))
    }

    func testEngineMessagesSkipEmptyStreamingTurn() {
        let history = [
            ChatMessage(role: .user, text: "hi"),
            ChatMessage(role: .assistant, text: "", isStreaming: true)
        ]
        let messages = ContextAssembler.engineMessages(modelName: "M", history: history, files: [])
        // system + user only; the empty streaming placeholder is dropped.
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.role, .system)
        XCTAssertEqual(messages.last?.role, .user)
    }

    func testPerFileTruncation() {
        let big = String(repeating: "x", count: ContextAssembler.perFileCharacterBudget + 500)
        let prompt = ContextAssembler.systemPrompt(
            modelName: "M",
            files: [ResolvedFile(filename: "Big.md", content: big)]
        )
        XCTAssertTrue(prompt.contains("[truncated]"))
    }

    // MARK: - Catalog

    func testCatalogHasDefaultAndUniqueIDs() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
        XCTAssertEqual(ModelCatalog.defaultModel.id, ModelCatalog.all[0].id)
        XCTAssertEqual(Set(ModelCatalog.all.map(\.id)).count, ModelCatalog.all.count)
    }
}
