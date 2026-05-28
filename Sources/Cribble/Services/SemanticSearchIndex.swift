import Foundation
import NaturalLanguage

/// A semantic match for the current query, resolved enough to render and open
/// without touching the index again.
struct SemanticHit: Identifiable, Equatable {
    let url: URL
    let title: String
    let score: Double

    var id: URL { url }
}

/// On-device embedding engine. Prefers Apple's transformer-based
/// `NLContextualEmbedding` (Neural Engine on Apple Silicon) and falls back to
/// classic sentence embeddings when contextual assets aren't installed — so
/// search degrades gracefully instead of breaking. All work stays local.
///
/// Kept as an `actor` because the underlying `NL*` model objects are not
/// thread-safe; serializing through the actor also keeps the heavy embedding
/// work off the main thread. Only plain `[Float]` vectors ever cross back out.
actor EmbeddingEngine {
    private enum Backend {
        case contextual(NLContextualEmbedding)
        case sentence(NLEmbedding)
    }

    private var backend: Backend?
    private var didSetup = false
    private(set) var isAvailable = false

    func ensureReady() async -> Bool {
        if didSetup { return isAvailable }
        didSetup = true

        if let contextual = NLContextualEmbedding(language: .english) {
            var hasAssets = contextual.hasAvailableAssets
            if !hasAssets {
                hasAssets = await withCheckedContinuation { continuation in
                    contextual.requestAssets { result, _ in
                        continuation.resume(returning: result == .available)
                    }
                }
            }
            if hasAssets, (try? contextual.load()) != nil {
                backend = .contextual(contextual)
                isAvailable = true
                return true
            }
        }

        if let sentence = NLEmbedding.sentenceEmbedding(for: .english) {
            backend = .sentence(sentence)
            isAvailable = true
            return true
        }

        isAvailable = false
        return false
    }

    func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch backend {
        case .contextual(let embedding):
            return contextualVector(trimmed, embedding: embedding)
        case .sentence(let embedding):
            guard let raw = embedding.vector(for: trimmed) else { return nil }
            return Self.normalized(raw.map(Float.init))
        case nil:
            return nil
        }
    }

    private func contextualVector(_ text: String, embedding: NLContextualEmbedding) -> [Float]? {
        guard let result = try? embedding.embeddingResult(for: text, language: .english) else { return nil }

        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
            let upper = min(sum.count, tokenVector.count)
            for index in 0..<upper {
                sum[index] += tokenVector[index]
            }
            count += 1
            return true
        }

        guard count > 0 else { return nil }
        return Self.normalized(sum.map { Float($0 / Double(count)) })
    }

    private static func normalized(_ vector: [Float]) -> [Float]? {
        var magnitude: Float = 0
        for value in vector { magnitude += value * value }
        magnitude = magnitude.squareRoot()
        guard magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }
}

/// Builds and queries a local semantic index over the open Markdown library.
/// Vectors are persisted (keyed by a stable content hash) so launches are warm
/// and only changed files are re-embedded.
@MainActor
final class SemanticSearchIndex: ObservableObject {
    enum Availability {
        case unknown
        case available
        case unavailable
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount = 0
    @Published private(set) var results: [SemanticHit] = []

    private struct Entry: Codable {
        let hash: UInt64
        let title: String
        let vector: [Float]
    }

    private let engine = EmbeddingEngine()
    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
        indexedCount = entries.count
    }

    /// Re-embeds any new or changed documents in the background and drops
    /// entries for files that no longer exist. Cheap when nothing changed.
    func reindex(documents: [MarkdownDocument]) {
        indexTask?.cancel()
        let documents = documents
        indexTask = Task { @MainActor in
            guard await engine.ensureReady() else {
                availability = .unavailable
                return
            }
            availability = .available

            isIndexing = true
            defer { isIndexing = false }

            var updated: [String: Entry] = [:]
            updated.reserveCapacity(documents.count)
            var changed = false

            for document in documents {
                if Task.isCancelled { return }
                let path = document.url.standardizedFileURL.path
                let hash = Self.stableHash(for: document)

                if let existing = entries[path], existing.hash == hash {
                    updated[path] = existing
                    continue
                }

                if let vector = await engine.vector(for: Self.embeddingText(for: document)) {
                    updated[path] = Entry(hash: hash, title: document.title, vector: vector)
                    changed = true
                }
            }

            if Task.isCancelled { return }
            if updated.count != entries.count { changed = true }

            entries = updated
            indexedCount = entries.count
            if changed { persist() }
        }
    }

    /// Debounced semantic query. Publishes the top matches to `results`.
    func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 3, availability == .available, !entries.isEmpty else {
            results = []
            return
        }

        let snapshot = entries
        searchTask = Task { @MainActor in
            // Cancellable debounce: rapid typing cancels the pending search.
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }

            guard let queryVector = await engine.vector(for: trimmed) else {
                results = []
                return
            }
            if Task.isCancelled { return }

            let hits: [SemanticHit] = snapshot.compactMap { path, entry in
                let score = Self.cosine(queryVector, entry.vector)
                guard score > 0.16 else { return nil }
                return SemanticHit(url: URL(fileURLWithPath: path), title: entry.title, score: Double(score))
            }
            .sorted { $0.score > $1.score }

            results = Array(hits.prefix(6))
        }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
    }

    /// Finds conceptual "stepping stone" notes that bridge `source` to `target`
    /// using embedding similarity — a greedy walk that hops toward the target
    /// while staying connected to where it currently is. Returns the
    /// intermediate notes only (endpoints excluded); empty means the two notes
    /// relate directly (or aren't indexed yet).
    func bridge(from source: URL, to target: URL, maxSteps: Int = 2) -> [SemanticHit] {
        let sourcePath = source.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard let sourceEntry = entries[sourcePath], let targetEntry = entries[targetPath] else { return [] }

        let targetVector = targetEntry.vector
        var chain: [SemanticHit] = []
        var visited: Set<String> = [sourcePath, targetPath]
        var currentVector = sourceEntry.vector
        var currentToTarget = Self.cosine(currentVector, targetVector)

        for _ in 0..<maxSteps {
            var best: (path: String, entry: Entry, stepScore: Float, toTarget: Float)?
            for (path, entry) in entries where !visited.contains(path) {
                let connectivity = Self.cosine(currentVector, entry.vector)
                let toTarget = Self.cosine(entry.vector, targetVector)
                let stepScore = connectivity * toTarget
                if best == nil || stepScore > best!.stepScore {
                    best = (path, entry, stepScore, toTarget)
                }
            }

            guard let chosen = best else { break }
            // Only accept a stone that moves us meaningfully closer to the
            // target while still being clearly related to the current node.
            guard chosen.toTarget > currentToTarget,
                  Self.cosine(currentVector, chosen.entry.vector) > 0.3
            else { break }

            chain.append(SemanticHit(url: URL(fileURLWithPath: chosen.path), title: chosen.entry.title, score: Double(chosen.toTarget)))
            visited.insert(chosen.path)
            currentVector = chosen.entry.vector
            currentToTarget = chosen.toTarget
        }

        return chain
    }

    var isReady: Bool { availability == .available && !entries.isEmpty }

    // MARK: - Text & math helpers

    private static func embeddingText(for document: MarkdownDocument) -> String {
        var parts: [String] = [document.title]
        parts.append(contentsOf: document.headings.prefix(16).map(\.title))
        parts.append(strip(String(document.rawMarkdown.prefix(1500))))
        return parts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Light markdown de-noising so syntax characters don't dominate the
    /// embedding. Intentionally conservative — we keep the words.
    private static func strip(_ text: String) -> String {
        var output = text
        for token in ["#", "*", "`", ">", "_", "~"] {
            output = output.replacingOccurrences(of: token, with: " ")
        }
        return output
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        // Vectors are stored normalized, so cosine similarity is the dot product.
        guard lhs.count == rhs.count else { return 0 }
        var dot: Float = 0
        for index in 0..<lhs.count {
            dot += lhs[index] * rhs[index]
        }
        return dot
    }

    /// Stable across launches (unlike `hashValue`, which is per-process salted).
    static func stableHash(for document: MarkdownDocument) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in document.title.utf8 {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        hash = (hash ^ 0x2f) &* prime
        for byte in document.rawMarkdown.utf8 {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        return hash
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            DiagnosticsCenter.shared.record(level: .warning, message: "Failed to persist semantic index: \(error.localizedDescription)")
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
            .appendingPathComponent("SemanticIndex.json")
    }
}
