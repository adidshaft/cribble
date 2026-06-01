import XCTest
@testable import Cribble

/// Verifies the CLI engine's streaming decoder reassembles UTF-8 scalars that
/// the OS pipe splits across read boundaries, instead of dropping the chunk.
final class StreamingUTF8DecoderTests: XCTestCase {
    func testReassemblesScalarSplitAcrossChunks() {
        let decoder = StreamingUTF8Decoder()
        // "é" is 0xC3 0xA9 in UTF-8; deliver the bytes in two reads.
        let bytes = Array("café".utf8) // 63 61 66 C3 A9
        let first = Data(bytes[0..<4])  // "caf" + lead byte of é
        let second = Data(bytes[4...])  // continuation byte of é

        let emittedFirst = decoder.consume(first)
        XCTAssertEqual(emittedFirst, "caf", "Partial trailing scalar must be held back")
        let emittedSecond = decoder.consume(second)
        XCTAssertEqual(emittedSecond, "é", "Held-back byte completes the scalar")
        XCTAssertEqual(decoder.value, "café")
    }

    func testEmojiSplitAcrossThreeChunks() {
        let decoder = StreamingUTF8Decoder()
        let bytes = Array("👍".utf8) // 4 bytes: F0 9F 91 8D
        var out = ""
        out += decoder.consume(Data(bytes[0..<1]))
        out += decoder.consume(Data(bytes[1..<3]))
        out += decoder.consume(Data(bytes[3...]))
        XCTAssertEqual(out, "👍")
        XCTAssertEqual(decoder.value, "👍")
    }

    func testCodeFenceSurvivesChunkBoundary() {
        // The real-world symptom: a multi-byte char right before a ``` fence must
        // not cause the fence to vanish.
        let decoder = StreamingUTF8Decoder()
        let source = "Total: 100€\n```swift\nlet x = 1\n```"
        let bytes = Array(source.utf8)
        var out = ""
        // Cut mid-way through the € sign (0xE2 0x82 0xAC).
        let euroLead = bytes.firstIndex(of: 0xE2)!
        out += decoder.consume(Data(bytes[0...euroLead]))      // up to & incl. first euro byte
        out += decoder.consume(Data(bytes[(euroLead + 1)...]))  // the rest
        out += decoder.finish()
        XCTAssertEqual(out, source)
        XCTAssertTrue(out.contains("```swift"), "Fence must survive the boundary")
    }

    func testPlainASCIIPassesThroughUnchanged() {
        let decoder = StreamingUTF8Decoder()
        XCTAssertEqual(decoder.consume(Data("hello".utf8)), "hello")
        XCTAssertEqual(decoder.finish(), "")
        XCTAssertEqual(decoder.value, "hello")
    }
}
