import Foundation

struct BacklinkIndex: Sendable {
    typealias SnippetProvider = @Sendable (URL, NSRange) -> String?

    private struct IndexedOccurrence: Sendable {
        let link: WikiLink
        let sourceRange: NSRange
    }

    private struct SourceEntry: Sendable {
        let sourceURL: URL
        let sourceTitle: String
        var occurrences: [IndexedOccurrence]
    }

    private var backlinksByTargetPath: [String: [SourceEntry]] = [:]

    init(documentMetas: [MarkdownDocumentMeta], rootURL: URL) {
        let linkIndex = LinkIndex(documentMetas: documentMetas, rootURL: rootURL)
        var entriesByTargetAndSource: [String: [String: SourceEntry]] = [:]

        for document in documentMetas.sorted(by: { $0.url.path < $1.url.path }) {
            let sourceURL = document.url.standardizedFileURL
            for link in document.outboundLinks {
                guard let sourceRange = link.sourceRange,
                      let targetURL = linkIndex.resolve(link).targetURL?.standardizedFileURL,
                      targetURL != sourceURL else {
                    continue
                }

                let targetPath = targetURL.path
                let sourcePath = sourceURL.path
                var sourceEntry = entriesByTargetAndSource[targetPath]?[sourcePath]
                    ?? SourceEntry(sourceURL: sourceURL, sourceTitle: document.title, occurrences: [])
                sourceEntry.occurrences.append(IndexedOccurrence(link: link, sourceRange: sourceRange))
                entriesByTargetAndSource[targetPath, default: [:]][sourcePath] = sourceEntry
            }
        }

        backlinksByTargetPath = entriesByTargetAndSource.mapValues { sourceMap in
            sourceMap.values.sorted {
                let titleOrder = $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle)
                if titleOrder == .orderedSame {
                    return $0.sourceURL.path < $1.sourceURL.path
                }
                return titleOrder == .orderedAscending
            }
        }
    }

    func backlinks(for targetURL: URL, snippetProvider: SnippetProvider? = nil) -> [Backlink] {
        let targetPath = targetURL.standardizedFileURL.path
        guard let entries = backlinksByTargetPath[targetPath] else { return [] }

        return entries.map { entry in
            Backlink(
                sourceURL: entry.sourceURL,
                sourceTitle: entry.sourceTitle,
                occurrences: entry.occurrences.enumerated().map { index, occurrence in
                    BacklinkOccurrence(
                        id: "\(entry.sourceURL.standardizedFileURL.path)#\(occurrence.sourceRange.location)-\(index)",
                        linkLabel: occurrence.link.label,
                        snippet: snippetProvider?(entry.sourceURL, occurrence.sourceRange) ?? "",
                        headingContext: nil
                    )
                }
            )
        }
    }

    static func snippet(in markdown: String, around sourceRange: NSRange, maxLength: Int = 160) -> String {
        guard let range = Range(sourceRange, in: markdown) else { return "" }
        let sentenceRange = markdown.lineRange(for: range)
        var text = String(markdown[sentenceRange])
        text = replaceWikiLinksWithLabels(in: text)
        text = text.replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: max(0, maxLength - 1))
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func replaceWikiLinksWithLabels(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in regex.matches(in: text, range: nsRange).reversed() {
            guard let innerRange = Range(match.range(at: 1), in: result),
                  let outerRange = Range(match.range(at: 0), in: result) else {
                continue
            }
            let inner = String(result[innerRange])
            let display = inner.components(separatedBy: "|").last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = inner.components(separatedBy: "#").first ?? inner
            result.replaceSubrange(outerRange, with: display?.isEmpty == false ? display! : fallback)
        }
        return result
    }
}
