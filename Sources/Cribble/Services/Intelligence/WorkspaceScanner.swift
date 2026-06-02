import Foundation

/// Detected source language from a file extension. Drives which parser/prompt a
/// file gets. Unknown text files still get summarized; binaries are skipped.
enum SourceLanguage: String, Sendable {
    case swift, markdown, javascript, typescript, python, go, rust, json, yaml, shell, other

    static func detect(extension ext: String) -> SourceLanguage? {
        switch ext.lowercased() {
        case "swift": .swift
        case "md", "markdown", "mdx": .markdown
        case "js", "mjs", "cjs", "jsx": .javascript
        case "ts", "tsx": .typescript
        case "py": .python
        case "go": .go
        case "rs": .rust
        case "json": .json
        case "yml", "yaml": .yaml
        case "sh", "bash", "zsh": .shell
        case "txt", "text", "c", "h", "cpp", "hpp", "m", "java", "rb", "php", "css", "html", "toml":
            .other
        default: nil   // unknown / binary — skip
        }
    }
}

/// Walks a project folder, keeps the `files` table in sync with disk via content
/// hashing, parses code symbols, and enqueues follow-up jobs for changed files.
/// This is the Tier-1 (deterministic, model-free) entry point of the pipeline.
///
/// Filesystem-native and store-agnostic: it walks the directory directly rather
/// than depending on `MarkdownLibraryStore`, so the engine is unit-testable
/// against a temp folder. The store can drive it later by passing its root URLs.
struct WorkspaceScanner: Sendable {
    let db: IntelligenceDatabase
    let projectID: String
    let rootURL: URL

    /// Directories never descended into.
    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".cribble", "node_modules", ".swiftpm",
        "DerivedData", ".venv", "venv", "dist", "build", ".next", "Pods"
    ]
    /// Files larger than this are skipped for summarization (still hashed cheaply
    /// would be wasteful — we skip entirely). 512 KB keeps prompts bounded.
    private static let maxFileBytes = 512 * 1024

    struct ScanResult: Sendable, Equatable {
        var scanned = 0
        var changed = 0
        var added = 0
        var removed = 0
        var skipped = 0
        var jobsEnqueued = 0
    }

    /// Performs a full incremental scan and returns a summary.
    func scan() async -> ScanResult {
        var result = ScanResult()
        let fileManager = FileManager.default

        var seenPaths: Set<String> = []
        let onDisk = enumerateFiles(fileManager: fileManager)

        for url in onDisk {
            let relativePath = relativePath(of: url)
            seenPaths.insert(relativePath)

            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? Int else {
                result.skipped += 1
                continue
            }
            guard size <= Self.maxFileBytes else { result.skipped += 1; continue }
            guard let language = SourceLanguage.detect(extension: url.pathExtension) else {
                result.skipped += 1
                continue
            }
            guard let hash = ContentHasher.hashFile(at: url) else { result.skipped += 1; continue }

            result.scanned += 1
            let existing = await db.file(projectID: projectID, path: relativePath)
            let isNew = existing == nil
            let isChanged = existing.map { $0.hash != hash } ?? false
            guard isNew || isChanged else { continue }

            if let oldHash = existing?.hash {
                await db.markArtifactsStale(projectID: projectID, containingSourceHash: oldHash)
            }
            let fileID = await db.upsertFile(
                projectID: projectID, path: relativePath,
                hash: hash, sizeBytes: size, language: language.rawValue
            )

            if isNew { result.added += 1 } else { result.changed += 1 }

            // Tier-1: parse symbols for Swift files immediately (no model needed).
            if language == .swift, let source = try? String(contentsOf: url, encoding: .utf8) {
                let symbols = SwiftSymbolExtractor.extract(from: source)
                await db.replaceSymbols(fileID: fileID, symbols: symbols)
            }

            // Tier-2: enqueue a summary job for the changed/added file.
            let enqueued = await db.enqueueJobIfNeeded(IntelligenceJob(
                projectID: projectID,
                type: .summarizeFile,
                inputHash: hash,
                inputPaths: [relativePath]
            ))
            if enqueued { result.jobsEnqueued += 1 }
        }

        // Reconcile deletions: anything tracked but no longer on disk.
        for tracked in await db.files(projectID: projectID) where !seenPaths.contains(tracked.path) {
            await db.markArtifactsStale(projectID: projectID, containingSourceHash: tracked.hash)
            await db.deleteFile(projectID: projectID, path: tracked.path)
            result.removed += 1
        }

        return result
    }

    // MARK: - Helpers

    private func enumerateFiles(fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if Self.ignoredDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                urls.append(url)
            }
        }
        return urls
    }

    private func relativePath(of url: URL) -> String {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
