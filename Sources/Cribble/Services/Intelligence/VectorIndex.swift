import Foundation

/// Semantic vector store for "Ask about this project". Behind a protocol so the
/// brute-force SQLite implementation here can later be swapped for the `sqlite-vec`
/// extension (design plan §15 Phase 3) without touching callers.
protocol VectorIndex: Sendable {
    /// Stores/updates the embedding for an artifact.
    func add(artifactID: String, vector: [Float]) async
    /// Returns the `limit` most similar artifact ids to `query`, best-first.
    func search(_ query: [Float], limit: Int) async -> [(id: String, score: Float)]
    /// Number of stored vectors.
    func count() async -> Int
}

/// Brute-force cosine similarity over vectors stored in the intelligence DB. Plenty
/// fast for local project scale (thousands of short vectors); no native extension
/// or extra dependency required.
struct SQLiteVectorIndex: VectorIndex {
    let db: IntelligenceDatabase
    let projectID: String

    func add(artifactID: String, vector: [Float]) async {
        await db.upsertEmbedding(artifactID: artifactID, projectID: projectID, vector: vector)
    }

    func count() async -> Int {
        await db.embeddingCount(projectID: projectID)
    }

    func search(_ query: [Float], limit: Int) async -> [(id: String, score: Float)] {
        guard !query.isEmpty else { return [] }
        let qNorm = Self.norm(query)
        guard qNorm > 0 else { return [] }

        let all = await db.embeddings(projectID: projectID)
        var scored: [(String, Float)] = []
        scored.reserveCapacity(all.count)
        for (id, vector) in all where vector.count == query.count {
            let n = Self.norm(vector)
            guard n > 0 else { continue }
            scored.append((id, Self.dot(query, vector) / (qNorm * n)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { (id: $0.0, score: $0.1) }
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<a.count { sum += a[i] * b[i] }
        return sum
    }

    private static func norm(_ v: [Float]) -> Float {
        var sum: Float = 0
        for x in v { sum += x * x }
        return sum.squareRoot()
    }
}
