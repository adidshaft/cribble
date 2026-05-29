import Foundation
import Markdown

struct DocumentLoader {
    func load(url: URL) throws -> MarkdownDocument {
        let raw = try Self.readText(at: url)
        let headings = parseHeadings(from: raw)
        let title = headings.first(where: { $0.level == 1 })?.title ?? url.deletingPathExtension().lastPathComponent
        let outboundLinks = WikiLinkParser.parse(raw)
        return MarkdownDocument(url: url, title: title, rawMarkdown: raw, headings: headings, outboundLinks: outboundLinks)
    }

    /// Reads a note's text resiliently. Real-world libraries (Obsidian vaults,
    /// iCloud folders) contain `.md` files that aren't strict UTF-8 — Latin-1,
    /// UTF-16, Windows-1252, or files with a few invalid bytes. Plain
    /// `String(contentsOf:encoding:.utf8)` throws "isn't in the correct format"
    /// on any of these. We try UTF-8, then the OS's encoding sniff, then common
    /// fallbacks, and finally a lossy UTF-8 decode that never fails — so a
    /// single odd file can still open instead of breaking the whole folder.
    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        var sniffed: String.Encoding = .utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &sniffed) {
            return detected
        }

        for encoding: String.Encoding in [.utf16, .isoLatin1, .windowsCP1252, .macOSRoman] {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }

        // Last resort: lossy UTF-8 (invalid bytes become U+FFFD). Never throws.
        return String(decoding: data, as: UTF8.self)
    }

    private func parseHeadings(from raw: String) -> [DocumentHeading] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let text = String(line)
            guard text.hasPrefix("#") else { return nil }
            let markerCount = text.prefix { $0 == "#" }.count
            guard (1...6).contains(markerCount) else { return nil }
            let rest = text.dropFirst(markerCount)
            guard rest.first == " " else { return nil }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return DocumentHeading(level: markerCount, title: title)
        }
    }
}
