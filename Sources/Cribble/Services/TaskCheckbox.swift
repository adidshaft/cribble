import Foundation

/// One GFM task-list item (`- [ ] …` / `- [x] …`) parsed for interactive
/// rendering in the reader.
struct TaskListItem: Identifiable, Equatable {
    let id: String
    let label: String
    let isChecked: Bool
    let indent: Int
}

/// Parsing + safe persistence for Markdown task-list checkboxes. The only write
/// Cribble performs to a note from the reader is flipping a single checkbox
/// state character — done at the byte level so the rest of the file (including
/// non-UTF-8 bytes, line endings, and trailing whitespace) is preserved exactly.
enum TaskCheckbox {
    /// Parses a single line as a task item, or returns nil if it isn't one.
    /// Matches `<indent><-|*|+><space>[<space|x|X>] <label>`.
    static func parse(line: String) -> (indent: Int, isChecked: Bool, label: String)? {
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            indent += line[index] == "\t" ? 4 : 1
            index = line.index(after: index)
        }

        guard index < line.endIndex, "-*+".contains(line[index]) else { return nil }
        index = line.index(after: index)

        guard index < line.endIndex, line[index] == " " || line[index] == "\t" else { return nil }
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }

        // Need at least "[x]"
        guard index < line.endIndex, line[index] == "[" else { return nil }
        let stateIndex = line.index(after: index)
        guard stateIndex < line.endIndex else { return nil }
        let closeIndex = line.index(after: stateIndex)
        guard closeIndex < line.endIndex, line[closeIndex] == "]" else { return nil }

        let stateChar = line[stateIndex]
        guard stateChar == " " || stateChar == "x" || stateChar == "X" else { return nil }

        var labelIndex = line.index(after: closeIndex)
        // A real task item has a space after the brackets (or ends there).
        if labelIndex < line.endIndex {
            guard line[labelIndex] == " " || line[labelIndex] == "\t" else { return nil }
            while labelIndex < line.endIndex, line[labelIndex] == " " || line[labelIndex] == "\t" {
                labelIndex = line.index(after: labelIndex)
            }
        }

        let label = String(line[labelIndex...]).trimmingCharacters(in: .whitespaces)
        return (indent, stateChar == "x" || stateChar == "X", label)
    }

    static func isTaskLine(_ line: String) -> Bool {
        parse(line: line) != nil
    }

    enum ToggleResult: Equatable {
        case toggled        // wrote the new state
        case stateMismatch  // the on-disk checkbox wasn't in the expected state (skip — likely edited)
        case notFound       // no checkbox at that ordinal
    }

    /// Flips the `ordinal`-th task checkbox in `fileURL` (counting in document
    /// order, skipping YAML front matter and fenced code — matching how the
    /// reader counts them). Only writes if the on-disk state still matches
    /// `expectedCurrentChecked`, guarding against external edits. Byte-level: it
    /// rewrites just the one state character.
    @discardableResult
    static func toggle(fileURL: URL, ordinal: Int, expectedCurrentChecked: Bool) throws -> ToggleResult {
        var data = try Data(contentsOf: fileURL)
        let newline: UInt8 = 0x0A

        var lineRanges: [Range<Int>] = []
        var start = data.startIndex
        var cursor = data.startIndex
        while cursor < data.endIndex {
            if data[cursor] == newline {
                lineRanges.append(start..<cursor)
                start = cursor + 1
            }
            cursor += 1
        }
        lineRanges.append(start..<data.endIndex)

        var inFrontMatter = false
        var sawFirstLine = false
        var inFence = false
        var fenceMarker: Character = "`"
        var count = 0

        for range in lineRanges {
            let line = String(decoding: data[range], as: UTF8.self)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Leading YAML front matter is stripped before rendering, so the
            // reader never counts checkboxes inside it — neither do we.
            if !sawFirstLine {
                sawFirstLine = true
                if trimmed == "---" {
                    inFrontMatter = true
                    continue
                }
            }
            if inFrontMatter {
                if trimmed == "---" || trimmed == "..." { inFrontMatter = false }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker: Character = trimmed.first == "`" ? "`" : "~"
                if !inFence {
                    inFence = true
                    fenceMarker = marker
                } else if marker == fenceMarker {
                    inFence = false
                }
                continue
            }
            if inFence { continue }

            guard let parsed = parse(line: line) else { continue }

            if count == ordinal {
                guard parsed.isChecked == expectedCurrentChecked else {
                    return .stateMismatch
                }
                guard let bracketIndex = range.firstIndex(where: { data[$0] == 0x5B }) else {
                    return .notFound
                }
                let stateByteIndex = bracketIndex + 1
                guard stateByteIndex < range.upperBound else { return .notFound }
                // 0x20 = space (unchecked), 0x78 = 'x' (checked)
                data[stateByteIndex] = expectedCurrentChecked ? 0x20 : 0x78
                try data.write(to: fileURL, options: [.atomic])
                return .toggled
            }
            count += 1
        }

        return .notFound
    }
}
