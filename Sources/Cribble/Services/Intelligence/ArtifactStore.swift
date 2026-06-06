import Foundation

/// Persists generated artifact content to the local cache and records its
/// metadata in the database. Artifacts start life as **virtual** (cache only);
/// publishing to `.cribble/intelligence/` happens later via the existing
/// `UnifiedDiff` → `DiffPreviewSheet` flow (design plan §4.3) and is not part of
/// this Phase-1 foundation.
struct ArtifactStore: Sendable {
    let db: IntelligenceDatabase
    let projectID: String
    /// `.cribble/cache/artifacts/` — where virtual artifact content lives.
    let cacheDirectory: URL

    /// Writes `content` to the cache and upserts the artifact record. Returns the
    /// stored artifact. The artifact `id` is derived from its logical relative
    /// path so regenerating the same artifact updates in place rather than
    /// accumulating duplicates.
    @discardableResult
    func store(
        type: IntelligenceArtifactType,
        relativePath: String,
        title: String?,
        content: String,
        sourceHashes: [String],
        provenance: [ArtifactProvenance] = []
    ) async throws -> IntelligenceArtifact {
        let id = ContentHasher.hash("\(projectID)\u{1}\(relativePath)")
        let contentHash = ContentHasher.hash(content)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let fileURL = cacheDirectory.appendingPathComponent("\(id).md")
        try content.data(using: .utf8)?.write(to: fileURL, options: .atomic)

        let artifact = IntelligenceArtifact(
            id: id,
            projectID: projectID,
            type: type,
            relativePath: relativePath,
            title: title,
            contentHash: contentHash,
            sourceHashes: sourceHashes,
            isPublished: false
        )
        await db.insertArtifact(artifact)
        for p in provenance {
            await db.insertProvenance(ArtifactProvenance(
                artifactID: id,
                claimAnchor: p.claimAnchor,
                fileID: p.fileID,
                startLine: p.startLine,
                endLine: p.endLine,
                symbolID: p.symbolID,
                confidence: p.confidence
            ))
        }
        return artifact
    }

    /// Reads back stored artifact content, if present.
    func content(for artifact: IntelligenceArtifact) -> String? {
        let fileURL = cacheDirectory.appendingPathComponent("\(artifact.id).md")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    @discardableResult
    func rewriteContent(for artifact: IntelligenceArtifact, content: String) async throws -> IntelligenceArtifact {
        let contentHash = ContentHasher.hash(content)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let fileURL = cacheDirectory.appendingPathComponent("\(artifact.id).md")
        try content.data(using: .utf8)?.write(to: fileURL, options: .atomic)

        let updated = IntelligenceArtifact(
            id: artifact.id,
            projectID: artifact.projectID,
            type: artifact.type,
            relativePath: artifact.relativePath,
            title: artifact.title,
            contentHash: contentHash,
            sourceHashes: artifact.sourceHashes,
            isPublished: artifact.isPublished
        )
        await db.insertArtifact(updated)
        return updated
    }

    func delete(_ artifact: IntelligenceArtifact) async {
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(artifact.id).md"))
        await db.deleteArtifact(id: artifact.id)
    }
}
