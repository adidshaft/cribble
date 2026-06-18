import Foundation

enum RichMarkdownBlock: Identifiable, Equatable {
    case markdown(id: String, text: String)
    case fencedCode(id: String, language: String?, code: String)
    case taskList(id: String, items: [TaskListItem])
    case callout(id: String, callout: CalloutBlock)
    case embed(id: String, reference: EmbedReference)

    var id: String {
        switch self {
        case .markdown(let id, _), .fencedCode(let id, _, _), .taskList(let id, _), .callout(let id, _), .embed(let id, _):
            id
        }
    }

    static func blocks(from markdown: String) -> [RichMarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [RichMarkdownBlock] = []
        var markdownLines: [String] = []
        var index = 0
        var blockIndex = 0

        // Flush the accumulated non-fence lines, splitting out contiguous runs
        // of GFM task-list items into their own `.taskList` blocks so the reader
        // can render interactive checkboxes. Prose between/around task runs stays
        // as ordinary `.markdown` blocks.
        func appendMarkdown() {
            let pending = markdownLines
            markdownLines.removeAll(keepingCapacity: true)

            func flushProse(_ proseLines: [String]) {
                var current: [String] = []

                func emit(_ lines: [String]) {
                    let text = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                    guard !text.isEmpty else { return }
                    blocks.append(.markdown(id: "markdown-\(blockIndex)", text: text))
                    blockIndex += 1
                }

                var lineIndex = 0
                while lineIndex < proseLines.count {
                    let line = proseLines[lineIndex]

                    if line.isCalloutStartLine {
                        emit(current)
                        current.removeAll(keepingCapacity: true)

                        var quoteLines: [String] = []
                        while lineIndex < proseLines.count, proseLines[lineIndex].isBlockquoteLine {
                            quoteLines.append(proseLines[lineIndex])
                            lineIndex += 1
                        }

                        if let callout = CalloutBlock.parse(id: "callout-\(blockIndex)", blockquoteLines: quoteLines) {
                            blocks.append(.callout(id: callout.id, callout: callout))
                            blockIndex += 1
                        } else {
                            emit(quoteLines)
                        }
                        continue
                    }

                    if let embed = line.standaloneEmbedReference() {
                        emit(current)
                        current.removeAll(keepingCapacity: true)
                        blocks.append(.embed(id: "embed-\(blockIndex)", reference: embed))
                        blockIndex += 1
                    } else if line.isStandaloneMarkdownImageLine {
                        emit(current)
                        current.removeAll(keepingCapacity: true)
                        emit([line])
                    } else {
                        current.append(line)
                    }
                    lineIndex += 1
                }
                emit(current)
            }

            var prose: [String] = []
            var tasks: [TaskListItem] = []

            func flushTasks() {
                guard !tasks.isEmpty else { return }
                blocks.append(.taskList(id: "task-\(blockIndex)", items: tasks))
                blockIndex += 1
                tasks.removeAll(keepingCapacity: true)
            }

            for line in pending {
                if let parsed = TaskCheckbox.parse(line: line) {
                    flushProse(prose)
                    prose.removeAll(keepingCapacity: true)
                    tasks.append(TaskListItem(
                        id: "task-\(blockIndex)-\(tasks.count)",
                        label: parsed.label,
                        isChecked: parsed.isChecked,
                        indent: parsed.indent
                    ))
                } else {
                    flushTasks()
                    prose.append(line)
                }
            }
            flushTasks()
            flushProse(prose)
        }

        while index < lines.count {
            let line = lines[index]
            if let openingFence = MarkdownFence(line: line) {
                appendMarkdown()
                index += 1

                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if openingFence.closes(candidate) {
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }

                if index < lines.count {
                    index += 1
                }

                let language = openingFence.language?.isEmpty == false ? openingFence.language : nil
                blocks.append(
                    .fencedCode(
                        id: "fence-\(blockIndex)",
                        language: language,
                        code: codeLines.joined(separator: "\n")
                    )
                )
                blockIndex += 1
            } else {
                markdownLines.append(line)
                index += 1
            }
        }

        appendMarkdown()
        return blocks
    }
}

private extension String {
    var isStandaloneMarkdownImageLine: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return false }
        guard let closeAlt = trimmed.firstIndex(of: "]"),
              closeAlt < trimmed.index(before: trimmed.endIndex)
        else { return false }
        let openParen = trimmed.index(after: closeAlt)
        guard trimmed[openParen] == "(" else { return false }
        return trimmed.hasSuffix(")")
    }

    var isBlockquoteLine: Bool {
        trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    var isCalloutStartLine: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return false }
        let stripped = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        return stripped.range(of: #"^\[![\w-]+\][+-]?\s*.*$"#, options: .regularExpression) != nil
    }

    func standaloneEmbedReference() -> EmbedReference? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        let embeds = WikiLinkParser.parseEmbeds(trimmed)
        guard trimmed.hasPrefix("![["),
              trimmed.hasSuffix("]]"),
              embeds.count == 1,
              let embed = embeds.first,
              embed.original == trimmed
        else {
            return nil
        }
        return EmbedReference(
            original: embed.original,
            target: embed.target,
            label: embed.label,
            heading: embed.heading,
            blockID: embed.blockID,
            sourceRange: embed.sourceRange
        )
    }
}

private struct MarkdownFence {
    let marker: Character
    let length: Int
    let language: String?

    init?(line: String) {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmedLeading.first, first == "`" || first == "~" else { return nil }

        let markerCount = trimmedLeading.prefix(while: { $0 == first }).count
        guard markerCount >= 3 else { return nil }

        let remainder = String(trimmedLeading.dropFirst(markerCount)).trimmingCharacters(in: .whitespaces)
        marker = first
        length = markerCount
        language = remainder
            .split(whereSeparator: \.isWhitespace)
            .first
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased() }
    }

    func closes(_ line: String) -> Bool {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        let closingMarkerCount = trimmedLeading.prefix(while: { $0 == marker }).count
        guard closingMarkerCount >= length else { return false }
        let remainder = trimmedLeading.dropFirst(closingMarkerCount)
        return remainder.allSatisfy(\.isWhitespace)
    }
}
