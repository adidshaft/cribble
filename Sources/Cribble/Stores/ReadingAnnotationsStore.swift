import Foundation

@MainActor
final class ReadingAnnotationsStore: ObservableObject {
    @Published private(set) var bookmarks: [String: ReadingBookmark] = [:]
    @Published private(set) var highlights: [String: [ReadingHighlight]] = [:]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func bookmark(for documentURL: URL) -> ReadingBookmark? {
        bookmarks[key(for: documentURL)]
    }

    func dropBookmark(for documentURL: URL, offsetY: Double, sectionTitle: String?) {
        let key = key(for: documentURL)
        bookmarks[key] = ReadingBookmark(
            documentPath: key,
            scrollOffsetY: max(0, offsetY),
            sectionTitle: sectionTitle,
            updatedAt: Date()
        )
        save()
    }

    func highlights(for documentURL: URL) -> [ReadingHighlight] {
        highlights[key(for: documentURL)] ?? []
    }

    func addHighlight(for documentURL: URL, quote: String, note: String) {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else { return }

        let key = key(for: documentURL)
        var documentHighlights = highlights[key] ?? []
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = documentHighlights.firstIndex(where: { highlightMatches($0, quote: trimmedQuote) }) {
            if !trimmedNote.isEmpty {
                documentHighlights[index].note = trimmedNote
            }
            highlights[key] = documentHighlights
            save()
            return
        }

        documentHighlights.append(
            ReadingHighlight(
                id: UUID(),
                documentPath: key,
                quote: trimmedQuote,
                note: trimmedNote,
                createdAt: Date()
            )
        )
        highlights[key] = documentHighlights
        save()
    }

    @discardableResult
    func updateHighlightNote(for documentURL: URL, matching quote: String, note: String) -> Bool {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else { return false }

        let key = key(for: documentURL)
        guard var documentHighlights = highlights[key],
              let index = documentHighlights.firstIndex(where: { highlightMatches($0, quote: trimmedQuote) })
        else {
            return false
        }

        documentHighlights[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        highlights[key] = documentHighlights
        save()
        return true
    }

    func highlight(for documentURL: URL, matching quote: String) -> ReadingHighlight? {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else { return nil }
        return highlights(for: documentURL).first { highlightMatches($0, quote: trimmedQuote) }
    }

    @discardableResult
    func removeHighlight(for documentURL: URL, matching quote: String) -> Bool {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else { return false }

        let key = key(for: documentURL)
        guard var documentHighlights = highlights[key],
              let index = documentHighlights.firstIndex(where: { highlightMatches($0, quote: trimmedQuote) })
        else {
            return false
        }

        documentHighlights.remove(at: index)
        if documentHighlights.isEmpty {
            highlights.removeValue(forKey: key)
        } else {
            highlights[key] = documentHighlights
        }
        save()
        return true
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let payload = try? JSONDecoder.cribble.decode(Payload.self, from: data) else { return }
        bookmarks = Dictionary(uniqueKeysWithValues: payload.bookmarks.map { ($0.documentPath, $0) })
        highlights = Dictionary(grouping: payload.highlights, by: \.documentPath)
    }

    private func save() {
        let payload = Payload(
            bookmarks: bookmarks.values.sorted { $0.documentPath < $1.documentPath },
            highlights: highlights.values.flatMap { $0 }.sorted { $0.createdAt < $1.createdAt }
        )

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyCribble.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            DiagnosticsCenter.shared.record(level: .error, message: "Failed to save reading annotations: \(error.localizedDescription)")
        }
    }

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func highlightMatches(_ highlight: ReadingHighlight, quote: String) -> Bool {
        let stored = highlight.quote.normalizedAnnotationText
        let selected = quote.normalizedAnnotationText
        guard !stored.isEmpty, !selected.isEmpty else { return false }
        return stored == selected || stored.contains(selected) || selected.contains(stored)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
            .appendingPathComponent("ReadingAnnotations.json")
    }

    private struct Payload: Codable {
        var bookmarks: [ReadingBookmark]
        var highlights: [ReadingHighlight]
    }
}

private extension String {
    var normalizedAnnotationText: String {
        lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private extension JSONEncoder {
    static var prettyCribble: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var cribble: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
