import XCTest
import AppKit
@testable import Cribble

@MainActor
final class HighlightedMarkdownParserOffsetTests: XCTestCase {
    func testColoringAcrossStyleBoundaries() throws {
        let baseURL = URL(fileURLWithPath: "/")
        
        // Markdown: "Plain **bold** `code` more"
        // Rendered characters: "Plain bold code more"
        // Style runs:
        // 1. "Plain " -> plain text
        // 2. "bold"   -> bold style
        // 3. " "      -> plain text
        // 4. "code"   -> monospace style
        // 5. " more"  -> plain text
        let input = "Plain **bold** `code` more"
        
        // Let's target the range covering "bold code"
        // "Plain " is 6 chars -> start at 6
        // "bold code" is 9 chars ("bold" (4) + " " (1) + "code" (4)) -> length 9
        let highlight = ResolvedHighlight(
            id: UUID(),
            note: "Cross boundary test",
            strategy: .offset(start: 6, length: 9)
        )
        
        let parser = HighlightedMarkdownParser(baseURL: baseURL, highlights: [highlight])
        let attributedString = try parser.attributedString(for: input)
        
        // Let's verify the characters match the expectation
        let chars = String(attributedString.characters)
        XCTAssertEqual(chars, "Plain bold code more")
        
        // Verify that every index in 6..<15 has systemYellow background color in the AppKit scope
        let targetColor = NSColor.systemYellow.withAlphaComponent(0.35)
        
        for index in 6..<15 {
            let attrIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: index)
            let nextIndex = attributedString.characters.index(after: attrIndex)
            
            let substring = attributedString[attrIndex..<nextIndex]
            let bgColor = substring.appKit.backgroundColor
            XCTAssertNotNil(bgColor, "Background color must not be nil at index \(index)")
            
            // Check color values
            if let color = bgColor,
               let actualRGB = color.usingColorSpace(NSColorSpace.deviceRGB),
               let targetRGB = targetColor.usingColorSpace(NSColorSpace.deviceRGB) {
                XCTAssertEqual(actualRGB.redComponent, targetRGB.redComponent, accuracy: 0.01)
                XCTAssertEqual(actualRGB.greenComponent, targetRGB.greenComponent, accuracy: 0.01)
                XCTAssertEqual(actualRGB.blueComponent, targetRGB.blueComponent, accuracy: 0.01)
                XCTAssertEqual(actualRGB.alphaComponent, targetRGB.alphaComponent, accuracy: 0.01)
            } else {
                XCTFail("Failed to get color components at index \(index)")
            }
        }
        
        // Verify that indices outside the highlight do not have the highlight background color
        let indicesOutside = [0, 1, 2, 3, 4, 5, 15, 16, 17, 18, 19]
        for index in indicesOutside {
            let attrIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: index)
            let nextIndex = attributedString.characters.index(after: attrIndex)
            
            let substring = attributedString[attrIndex..<nextIndex]
            let bgColor = substring.appKit.backgroundColor
            XCTAssertNil(bgColor, "Background color at index \(index) should be nil")
        }
    }

    func testOffsetHighlightUsesUTF16OffsetsAroundEmoji() throws {
        let input = "Intro 😀 **target** tail"
        let rendered = "Intro 😀 target tail"
        let range = rendered.range(of: "target")!
        let startUTF16 = rendered.utf16.distance(
            from: rendered.utf16.startIndex,
            to: range.lowerBound.samePosition(in: rendered.utf16)!
        )
        let lengthUTF16 = "target".utf16.count
        let startCharacter = rendered.distance(from: rendered.startIndex, to: range.lowerBound)

        let highlight = ResolvedHighlight(
            id: UUID(),
            note: "",
            strategy: .offset(start: startUTF16, length: lengthUTF16)
        )

        let parser = HighlightedMarkdownParser(baseURL: URL(fileURLWithPath: "/"), highlights: [highlight])
        let attributedString = try parser.attributedString(for: input)

        XCTAssertEqual(String(attributedString.characters), rendered)

        for index in startCharacter..<(startCharacter + "target".count) {
            let attrIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: index)
            let nextIndex = attributedString.characters.index(after: attrIndex)
            XCTAssertNotNil(
                attributedString[attrIndex..<nextIndex].appKit.backgroundColor,
                "Expected highlight at character index \(index)"
            )
        }

        let emojiIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: 6)
        let afterEmoji = attributedString.characters.index(after: emojiIndex)
        XCTAssertNil(attributedString[emojiIndex..<afterEmoji].appKit.backgroundColor)
    }
}
