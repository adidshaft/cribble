import Foundation
import SQLite3

// SQLite's `sqlite3_bind_text` needs to know whether it owns the bytes. The C
// `SQLITE_TRANSIENT` sentinel (-1) tells it to copy them, which is correct for
// Swift `String`s whose storage we don't keep alive. The constant isn't imported
// into Swift, so we reconstruct it.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum IntelligenceDatabaseError: LocalizedError {
    case openFailed(String)
    case migrationFailed(version: Int, message: String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m): "Couldn't open the intelligence database: \(m)"
        case .migrationFailed(let v, let m): "Intelligence DB migration \(v) failed: \(m)"
        case .queryFailed(let m): "Intelligence DB query failed: \(m)"
        }
    }
}

/// Single source of truth for all intelligence state: tracked files, parsed
/// symbols, the job queue, generated artifacts, and claim-level provenance.
///
/// Modeled as an `actor` for the same reason `EmbeddingEngine` is: the underlying
/// `sqlite3` connection handle is not thread-safe, and serializing every access
/// through the actor keeps the (single) writer correct without locks. Only plain
/// value types (`Sendable` structs, strings, ints) ever cross the actor boundary.
///
/// Storage note: timestamps that we read back into Swift `Date`s are stored as
/// REAL epoch seconds (simplest reliable round-trip). Write-only audit stamps
/// (`started_at`, `finished_at`) stay as TEXT `datetime('now')`.
actor IntelligenceDatabase {
    /// Owns the raw connection and closes it on deallocation. Wrapping the pointer
    /// here (rather than in the actor) keeps cleanup out of the actor's nonisolated
    /// `deinit`, which Swift 6 forbids from touching the non-Sendable handle.
    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer
        init(handle: OpaquePointer) { self.handle = handle }
        deinit { sqlite3_close(handle) }
    }

    private let connection: Connection
    private var db: OpaquePointer? { connection.handle }
    let path: String

    /// Ordered schema migrations. Each runs inside a transaction; `schema_version`
    /// records the highest applied version. Append new migrations — never edit
    /// shipped ones.
    private static let migrations: [(version: Int, sql: String)] = [
        (1, """
        CREATE TABLE files (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id  TEXT NOT NULL,
            path        TEXT NOT NULL,
            hash        TEXT NOT NULL,
            size_bytes  INTEGER NOT NULL,
            language    TEXT,
            updated_at  REAL NOT NULL,
            UNIQUE(project_id, path)
        );
        CREATE INDEX idx_files_hash ON files(hash);

        CREATE TABLE symbols (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id     INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            name        TEXT NOT NULL,
            kind        TEXT NOT NULL,
            start_line  INTEGER,
            end_line    INTEGER,
            signature   TEXT,
            hash        TEXT NOT NULL
        );
        CREATE INDEX idx_symbols_file ON symbols(file_id);

        CREATE TABLE jobs (
            id                  TEXT PRIMARY KEY,
            project_id          TEXT NOT NULL,
            job_type            TEXT NOT NULL,
            input_hash          TEXT NOT NULL,
            input_paths         TEXT,
            status              TEXT NOT NULL DEFAULT 'pending',
            priority            INTEGER NOT NULL DEFAULT 100,
            model_id            TEXT,
            attempt_count       INTEGER NOT NULL DEFAULT 0,
            max_attempts        INTEGER NOT NULL DEFAULT 3,
            error_message       TEXT,
            output_artifact_id  TEXT,
            created_at          REAL NOT NULL,
            started_at          TEXT,
            finished_at         TEXT
        );
        CREATE INDEX idx_jobs_status ON jobs(status, priority);
        CREATE INDEX idx_jobs_input_hash ON jobs(input_hash);

        CREATE TABLE artifacts (
            id              TEXT PRIMARY KEY,
            project_id      TEXT NOT NULL,
            artifact_type   TEXT NOT NULL,
            relative_path   TEXT NOT NULL,
            title           TEXT,
            content_hash    TEXT NOT NULL,
            source_hashes   TEXT NOT NULL,
            is_published    INTEGER NOT NULL DEFAULT 0,
            is_stale        INTEGER NOT NULL DEFAULT 0,
            created_at      REAL NOT NULL,
            updated_at      REAL NOT NULL
        );
        CREATE INDEX idx_artifacts_type ON artifacts(artifact_type);
        CREATE INDEX idx_artifacts_project ON artifacts(project_id);

        CREATE TABLE artifact_provenance (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            artifact_id  TEXT NOT NULL REFERENCES artifacts(id) ON DELETE CASCADE,
            claim_anchor TEXT NOT NULL,
            file_id      INTEGER REFERENCES files(id),
            start_line   INTEGER,
            end_line     INTEGER,
            symbol_id    INTEGER REFERENCES symbols(id),
            confidence   REAL
        );
        CREATE INDEX idx_provenance_artifact ON artifact_provenance(artifact_id);

        CREATE TABLE git_commits (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id    TEXT NOT NULL,
            sha           TEXT NOT NULL,
            message       TEXT,
            author        TEXT,
            timestamp     TEXT NOT NULL,
            is_summarized INTEGER NOT NULL DEFAULT 0,
            UNIQUE(project_id, sha)
        );
        """),
        (2, """
        -- Embedding vectors for semantic retrieval ("Ask about this project").
        -- Stored as a packed Float32 BLOB; brute-force cosine in Swift keeps this
        -- dependency-free. Swappable for the sqlite-vec extension behind VectorIndex.
        CREATE TABLE embeddings (
            artifact_id  TEXT PRIMARY KEY REFERENCES artifacts(id) ON DELETE CASCADE,
            project_id   TEXT NOT NULL,
            dim          INTEGER NOT NULL,
            vector       BLOB NOT NULL
        );
        CREATE INDEX idx_embeddings_project ON embeddings(project_id);
        """)
    ]

    /// Opens (creating if needed) the database at `path` and runs pending
    /// migrations. Pass `:memory:` for tests.
    init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw IntelligenceDatabaseError.openFailed(message)
        }
        self.connection = Connection(handle: handle)
        // WAL + foreign keys: WAL lets read-mostly HUD queries proceed while a
        // job writes; FK enforcement makes the ON DELETE CASCADE rules real.
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        // Migration runs against the raw handle: `init` on an actor is a
        // nonisolated context, so it can't touch the actor-isolated `db` property
        // or call isolated methods. Operating on the local `handle` keeps it sound
        // (no other reference to the connection exists yet).
        try Self.runMigrations(on: handle)
    }

    // MARK: - Migrations

    private static func runMigrations(on db: OpaquePointer) throws {
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);", nil, nil, nil)
        let current = currentSchemaVersion(on: db)
        for migration in migrations where migration.version > current {
            sqlite3_exec(db, "BEGIN;", nil, nil, nil)
            if let error = execReturningError(migration.sql, on: db) {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw IntelligenceDatabaseError.migrationFailed(version: migration.version, message: error)
            }
            let stamp = "INSERT INTO schema_version (version, applied_at) VALUES (\(migration.version), \(Date().timeIntervalSince1970));"
            if let error = execReturningError(stamp, on: db) {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw IntelligenceDatabaseError.migrationFailed(version: migration.version, message: error)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    private static func currentSchemaVersion(on db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private static func execReturningError(_ sql: String, on db: OpaquePointer) -> String? {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if rc != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error (code \(rc))"
            sqlite3_free(errorPointer)
            return message
        }
        return nil
    }

    // MARK: - Files

    /// Inserts or updates a file row; returns its row id.
    @discardableResult
    func upsertFile(projectID: String, path: String, hash: String, sizeBytes: Int, language: String?) -> Int64 {
        let sql = """
        INSERT INTO files (project_id, path, hash, size_bytes, language, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, path) DO UPDATE SET
            hash = excluded.hash,
            size_bytes = excluded.size_bytes,
            language = excluded.language,
            updated_at = excluded.updated_at;
        """
        run(sql) { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, path)
            bindText(stmt, 3, hash)
            sqlite3_bind_int64(stmt, 4, Int64(sizeBytes))
            bindTextOrNull(stmt, 5, language)
            sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        }
        return file(projectID: projectID, path: path)?.id ?? sqlite3_last_insert_rowid(db)
    }

    func file(projectID: String, path: String) -> IntelligenceFile? {
        var result: IntelligenceFile?
        query("SELECT id, project_id, path, hash, size_bytes, language FROM files WHERE project_id = ? AND path = ?;") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, path)
        } each: { stmt in
            result = Self.readFile(stmt)
        }
        return result
    }

    func files(projectID: String) -> [IntelligenceFile] {
        var rows: [IntelligenceFile] = []
        query("SELECT id, project_id, path, hash, size_bytes, language FROM files WHERE project_id = ? ORDER BY path;") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            rows.append(Self.readFile(stmt))
        }
        return rows
    }

    func deleteFile(projectID: String, path: String) {
        run("DELETE FROM files WHERE project_id = ? AND path = ?;") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, path)
        }
    }

    private static func readFile(_ stmt: OpaquePointer?) -> IntelligenceFile {
        IntelligenceFile(
            id: sqlite3_column_int64(stmt, 0),
            projectID: columnText(stmt, 1) ?? "",
            path: columnText(stmt, 2) ?? "",
            hash: columnText(stmt, 3) ?? "",
            sizeBytes: Int(sqlite3_column_int64(stmt, 4)),
            language: columnText(stmt, 5)
        )
    }

    // MARK: - Symbols

    func replaceSymbols(fileID: Int64, symbols: [SwiftSymbol]) {
        run("DELETE FROM symbols WHERE file_id = ?;") { stmt in
            sqlite3_bind_int64(stmt, 1, fileID)
        }
        let sql = "INSERT INTO symbols (file_id, name, kind, start_line, end_line, signature, hash) VALUES (?, ?, ?, ?, ?, ?, ?);"
        for symbol in symbols {
            run(sql) { stmt in
                sqlite3_bind_int64(stmt, 1, fileID)
                bindText(stmt, 2, symbol.name)
                bindText(stmt, 3, symbol.kind.rawValue)
                sqlite3_bind_int(stmt, 4, Int32(symbol.startLine))
                sqlite3_bind_int(stmt, 5, Int32(symbol.endLine))
                bindTextOrNull(stmt, 6, symbol.signature)
                bindText(stmt, 7, ContentHasher.hash(symbol.signature ?? symbol.name))
            }
        }
    }

    /// All symbols in a project, joined with their file paths. Used to build the
    /// dependency graph and the project index without a model.
    func allSymbols(projectID: String) -> [SymbolRecord] {
        var rows: [SymbolRecord] = []
        query("""
        SELECT f.id, f.path, s.name, s.kind, s.start_line, s.end_line, s.signature
        FROM symbols s JOIN files f ON s.file_id = f.id
        WHERE f.project_id = ? ORDER BY f.path, s.start_line;
        """) { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            rows.append(SymbolRecord(
                fileID: sqlite3_column_int64(stmt, 0),
                filePath: Self.columnText(stmt, 1) ?? "",
                name: Self.columnText(stmt, 2) ?? "",
                kind: Self.columnText(stmt, 3) ?? "",
                startLine: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4)),
                endLine: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5)),
                signature: Self.columnText(stmt, 6)
            ))
        }
        return rows
    }

    func symbolCount(fileID: Int64) -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM symbols WHERE file_id = ?;") { stmt in
            sqlite3_bind_int64(stmt, 1, fileID)
        } each: { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    // MARK: - Jobs

    /// Enqueues a job unless an equivalent one (same project, type, input hash)
    /// is already pending, running, or completed. Returns true if enqueued.
    @discardableResult
    func enqueueJobIfNeeded(_ job: IntelligenceJob) -> Bool {
        var exists = false
        query("""
        SELECT 1 FROM jobs
        WHERE project_id = ? AND job_type = ? AND input_hash = ?
          AND status IN ('pending', 'running', 'completed') LIMIT 1;
        """) { stmt in
            bindText(stmt, 1, job.projectID)
            bindText(stmt, 2, job.type.rawValue)
            bindText(stmt, 3, job.inputHash)
        } each: { _ in exists = true }
        guard !exists else { return false }

        let pathsJSON = (try? String(data: JSONEncoder().encode(job.inputPaths), encoding: .utf8)) ?? "[]"
        run("""
        INSERT INTO jobs (id, project_id, job_type, input_hash, input_paths, status, priority, model_id, attempt_count, max_attempts, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """) { stmt in
            bindText(stmt, 1, job.id)
            bindText(stmt, 2, job.projectID)
            bindText(stmt, 3, job.type.rawValue)
            bindText(stmt, 4, job.inputHash)
            bindTextOrNull(stmt, 5, pathsJSON)
            bindText(stmt, 6, job.status.rawValue)
            sqlite3_bind_int(stmt, 7, Int32(job.priority))
            bindTextOrNull(stmt, 8, job.modelID)
            sqlite3_bind_int(stmt, 9, Int32(job.attemptCount))
            sqlite3_bind_int(stmt, 10, Int32(job.maxAttempts))
            sqlite3_bind_double(stmt, 11, job.createdAt.timeIntervalSince1970)
        }
        return true
    }

    /// Returns the highest-priority pending job whose tier is `<= maxTier`, and
    /// atomically marks it `running`. Returns nil if none are eligible.
    func dequeueNextJob(projectID: String, maxTier: IntelligenceJobTier, deterministicOnly: Bool = false) -> IntelligenceJob? {
        let allowedTypes = IntelligenceJobType.allCases
            .filter { $0.tier != .none && $0.tier <= maxTier && (!deterministicOnly || !$0.requiresProvider) }
            .map { "'\($0.rawValue)'" }
            .joined(separator: ",")
        guard !allowedTypes.isEmpty else { return nil }

        var job: IntelligenceJob?
        query("""
        SELECT id, project_id, job_type, input_hash, input_paths, status, priority, model_id, attempt_count, max_attempts, error_message, output_artifact_id, created_at
        FROM jobs
        WHERE project_id = ? AND status = 'pending' AND job_type IN (\(allowedTypes))
        ORDER BY priority ASC, created_at ASC LIMIT 1;
        """) { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            job = Self.readJob(stmt)
        }

        guard let job else { return nil }
        run("UPDATE jobs SET status = 'running', started_at = datetime('now') WHERE id = ?;") { stmt in
            bindText(stmt, 1, job.id)
        }
        var running = job
        running.status = .running
        return running
    }

    func completeJob(id: String, artifactID: String?) {
        run("UPDATE jobs SET status = 'completed', output_artifact_id = ?, finished_at = datetime('now') WHERE id = ?;") { stmt in
            bindTextOrNull(stmt, 1, artifactID)
            bindText(stmt, 2, id)
        }
    }

    /// Records a failed attempt. If attempts remain the job returns to `pending`
    /// for retry; otherwise it is marked `failed` with the error preserved.
    func recordFailure(id: String, error: String) {
        run("""
        UPDATE jobs SET
            attempt_count = attempt_count + 1,
            error_message = ?,
            status = CASE WHEN attempt_count + 1 >= max_attempts THEN 'failed' ELSE 'pending' END,
            finished_at = datetime('now')
        WHERE id = ?;
        """) { stmt in
            bindText(stmt, 1, error)
            bindText(stmt, 2, id)
        }
    }

    /// On launch, revert orphaned `running` jobs (from a crash/quit) back to
    /// `pending` so they get picked up again.
    func resetRunningJobs() {
        exec("UPDATE jobs SET status = 'pending', started_at = NULL WHERE status = 'running';")
    }

    /// Returns a single job to `pending` without counting an attempt. Used when a
    /// job was dequeued but can't run yet (e.g. its required provider isn't ready),
    /// so we don't burn its retry budget.
    func requeueJob(id: String) {
        run("UPDATE jobs SET status = 'pending', started_at = NULL WHERE id = ?;") { stmt in
            bindText(stmt, 1, id)
        }
    }

    func cancelJobs(projectID: String) {
        run("UPDATE jobs SET status = 'cancelled' WHERE project_id = ? AND status IN ('pending', 'running');") { stmt in
            bindText(stmt, 1, projectID)
        }
    }

    func jobs(projectID: String, status: IntelligenceJobStatus? = nil) -> [IntelligenceJob] {
        var rows: [IntelligenceJob] = []
        let base = """
        SELECT id, project_id, job_type, input_hash, input_paths, status, priority, model_id, attempt_count, max_attempts, error_message, output_artifact_id, created_at
        FROM jobs WHERE project_id = ?
        """
        let sql = status == nil ? base + " ORDER BY priority ASC, created_at ASC;"
                                : base + " AND status = ? ORDER BY priority ASC, created_at ASC;"
        query(sql) { stmt in
            bindText(stmt, 1, projectID)
            if let status { bindText(stmt, 2, status.rawValue) }
        } each: { stmt in
            rows.append(Self.readJob(stmt))
        }
        return rows
    }

    func pendingJobCount(projectID: String) -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM jobs WHERE project_id = ? AND status = 'pending';") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    private static func readJob(_ stmt: OpaquePointer?) -> IntelligenceJob {
        let pathsJSON = columnText(stmt, 4) ?? "[]"
        let paths = (try? JSONDecoder().decode([String].self, from: Data(pathsJSON.utf8))) ?? []
        return IntelligenceJob(
            id: columnText(stmt, 0) ?? "",
            projectID: columnText(stmt, 1) ?? "",
            type: IntelligenceJobType(rawValue: columnText(stmt, 2) ?? "") ?? .scanWorkspace,
            inputHash: columnText(stmt, 3) ?? "",
            inputPaths: paths,
            status: IntelligenceJobStatus(rawValue: columnText(stmt, 5) ?? "") ?? .pending,
            priority: Int(sqlite3_column_int(stmt, 6)),
            attemptCount: Int(sqlite3_column_int(stmt, 8)),
            maxAttempts: Int(sqlite3_column_int(stmt, 9)),
            modelID: columnText(stmt, 7),
            errorMessage: columnText(stmt, 10),
            outputArtifactID: columnText(stmt, 11),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        )
    }

    // MARK: - Artifacts

    func insertArtifact(_ artifact: IntelligenceArtifact) {
        let hashesJSON = (try? String(data: JSONEncoder().encode(artifact.sourceHashes), encoding: .utf8)) ?? "[]"
        let now = Date().timeIntervalSince1970
        run("""
        INSERT INTO artifacts (id, project_id, artifact_type, relative_path, title, content_hash, source_hashes, is_published, is_stale, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            relative_path = excluded.relative_path,
            title = excluded.title,
            content_hash = excluded.content_hash,
            source_hashes = excluded.source_hashes,
            is_stale = 0,
            updated_at = excluded.updated_at;
        """) { stmt in
            bindText(stmt, 1, artifact.id)
            bindText(stmt, 2, artifact.projectID)
            bindText(stmt, 3, artifact.type.rawValue)
            bindText(stmt, 4, artifact.relativePath)
            bindTextOrNull(stmt, 5, artifact.title)
            bindText(stmt, 6, artifact.contentHash)
            bindText(stmt, 7, hashesJSON)
            sqlite3_bind_int(stmt, 8, artifact.isPublished ? 1 : 0)
            sqlite3_bind_double(stmt, 9, now)
            sqlite3_bind_double(stmt, 10, now)
        }
    }

    func artifacts(projectID: String) -> [IntelligenceArtifact] {
        var rows: [IntelligenceArtifact] = []
        query("""
        SELECT id, project_id, artifact_type, relative_path, title, content_hash, source_hashes, is_published
        FROM artifacts WHERE project_id = ? ORDER BY artifact_type, relative_path;
        """) { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            let hashesJSON = Self.columnText(stmt, 6) ?? "[]"
            let hashes = (try? JSONDecoder().decode([String].self, from: Data(hashesJSON.utf8))) ?? []
            rows.append(IntelligenceArtifact(
                id: Self.columnText(stmt, 0) ?? "",
                projectID: Self.columnText(stmt, 1) ?? "",
                type: IntelligenceArtifactType(rawValue: Self.columnText(stmt, 2) ?? "") ?? .fileSummary,
                relativePath: Self.columnText(stmt, 3) ?? "",
                title: Self.columnText(stmt, 4),
                contentHash: Self.columnText(stmt, 5) ?? "",
                sourceHashes: hashes,
                isPublished: sqlite3_column_int(stmt, 7) == 1
            ))
        }
        return rows
    }

    func artifacts(projectID: String, type: IntelligenceArtifactType) -> [IntelligenceArtifact] {
        artifacts(projectID: projectID).filter { $0.type == type }
    }

    /// Total bytes recorded for a project's artifacts is not tracked in the DB
    /// (content lives on disk); the engine computes disk usage from the cache
    /// directory. This returns artifact ids ordered oldest-first for LRU eviction.
    func artifactIDsOldestFirst(projectID: String) -> [String] {
        var ids: [String] = []
        query("SELECT id FROM artifacts WHERE project_id = ? AND is_published = 0 ORDER BY updated_at ASC;") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            if let id = Self.columnText(stmt, 0) { ids.append(id) }
        }
        return ids
    }

    func deleteArtifact(id: String) {
        run("DELETE FROM artifacts WHERE id = ?;") { stmt in bindText(stmt, 1, id) }
    }

    /// Wipes all artifacts and jobs for a project so intelligence can be rebuilt
    /// from scratch (used by Clear Cache and poison-recovery).
    func reset(projectID: String) {
        run("DELETE FROM artifacts WHERE project_id = ?;") { stmt in bindText(stmt, 1, projectID) }
        run("DELETE FROM jobs WHERE project_id = ?;") { stmt in bindText(stmt, 1, projectID) }
        run("DELETE FROM git_commits WHERE project_id = ?;") { stmt in bindText(stmt, 1, projectID) }
    }

    func markArtifactPublished(id: String) {
        run("UPDATE artifacts SET is_published = 1 WHERE id = ?;") { stmt in bindText(stmt, 1, id) }
    }

    /// Marks every artifact that was produced from `sourceHash` as stale, so the
    /// scheduler knows to regenerate it. Implements the bottom-up invalidation
    /// from the design plan (§7.3).
    func markArtifactsStale(projectID: String, containingSourceHash sourceHash: String) {
        // `source_hashes` is a JSON array; a substring match on the quoted hash is
        // sufficient and avoids a JSON1 dependency.
        run("UPDATE artifacts SET is_stale = 1 WHERE project_id = ? AND instr(source_hashes, ?) > 0;") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, "\"\(sourceHash)\"")
        }
    }

    func staleArtifactCount(projectID: String) -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM artifacts WHERE project_id = ? AND is_stale = 1;") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    // MARK: - Git commits

    /// Records a commit if not already present. Returns true if newly inserted.
    @discardableResult
    func recordCommitIfNeeded(projectID: String, sha: String, message: String, author: String, timestamp: String) -> Bool {
        var exists = false
        query("SELECT 1 FROM git_commits WHERE project_id = ? AND sha = ? LIMIT 1;") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, sha)
        } each: { _ in exists = true }
        guard !exists else { return false }
        run("INSERT INTO git_commits (project_id, sha, message, author, timestamp) VALUES (?, ?, ?, ?, ?);") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, sha)
            bindText(stmt, 3, message)
            bindText(stmt, 4, author)
            bindText(stmt, 5, timestamp)
        }
        return true
    }

    func unsummarizedCommits(projectID: String, limit: Int = 20) -> [GitCommitRecord] {
        var rows: [GitCommitRecord] = []
        query("""
        SELECT sha, message, author, timestamp, is_summarized FROM git_commits
        WHERE project_id = ? AND is_summarized = 0 ORDER BY timestamp DESC LIMIT ?;
        """) { stmt in
            bindText(stmt, 1, projectID)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        } each: { stmt in
            rows.append(GitCommitRecord(
                sha: Self.columnText(stmt, 0) ?? "",
                message: Self.columnText(stmt, 1) ?? "",
                author: Self.columnText(stmt, 2) ?? "",
                timestamp: Self.columnText(stmt, 3) ?? "",
                isSummarized: sqlite3_column_int(stmt, 4) == 1
            ))
        }
        return rows
    }

    func markCommitSummarized(projectID: String, sha: String) {
        run("UPDATE git_commits SET is_summarized = 1 WHERE project_id = ? AND sha = ?;") { stmt in
            bindText(stmt, 1, projectID)
            bindText(stmt, 2, sha)
        }
    }

    // MARK: - Embeddings (vector index)

    func upsertEmbedding(artifactID: String, projectID: String, vector: [Float]) {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        run("""
        INSERT INTO embeddings (artifact_id, project_id, dim, vector) VALUES (?, ?, ?, ?)
        ON CONFLICT(artifact_id) DO UPDATE SET dim = excluded.dim, vector = excluded.vector;
        """) { stmt in
            bindText(stmt, 1, artifactID)
            bindText(stmt, 2, projectID)
            sqlite3_bind_int(stmt, 3, Int32(vector.count))
            data.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
            }
        }
    }

    /// All stored embeddings for a project, as (artifactID, vector) pairs.
    func embeddings(projectID: String) -> [(artifactID: String, vector: [Float])] {
        var rows: [(String, [Float])] = []
        query("SELECT artifact_id, dim, vector FROM embeddings WHERE project_id = ?;") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in
            let id = Self.columnText(stmt, 0) ?? ""
            let dim = Int(sqlite3_column_int(stmt, 1))
            guard let blob = sqlite3_column_blob(stmt, 2) else { return }
            let bytes = Int(sqlite3_column_bytes(stmt, 2))
            guard bytes == dim * MemoryLayout<Float>.size else { return }
            let buffer = UnsafeRawBufferPointer(start: blob, count: bytes)
            let vector = Array(buffer.bindMemory(to: Float.self))
            rows.append((id, vector))
        }
        return rows
    }

    func embeddingCount(projectID: String) -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM embeddings WHERE project_id = ?;") { stmt in
            bindText(stmt, 1, projectID)
        } each: { stmt in count = Int(sqlite3_column_int64(stmt, 0)) }
        return count
    }

    // MARK: - Provenance

    func insertProvenance(_ p: ArtifactProvenance) {
        run("""
        INSERT INTO artifact_provenance (artifact_id, claim_anchor, file_id, start_line, end_line, symbol_id, confidence)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """) { stmt in
            bindText(stmt, 1, p.artifactID)
            bindText(stmt, 2, p.claimAnchor)
            bindInt64OrNull(stmt, 3, p.fileID)
            bindIntOrNull(stmt, 4, p.startLine)
            bindIntOrNull(stmt, 5, p.endLine)
            bindInt64OrNull(stmt, 6, p.symbolID)
            if let c = p.confidence { sqlite3_bind_double(stmt, 7, c) } else { sqlite3_bind_null(stmt, 7) }
        }
    }

    func provenance(artifactID: String) -> [ArtifactProvenance] {
        var rows: [ArtifactProvenance] = []
        query("""
        SELECT artifact_id, claim_anchor, file_id, start_line, end_line, symbol_id, confidence
        FROM artifact_provenance WHERE artifact_id = ?;
        """) { stmt in
            bindText(stmt, 1, artifactID)
        } each: { stmt in
            rows.append(ArtifactProvenance(
                artifactID: Self.columnText(stmt, 0) ?? "",
                claimAnchor: Self.columnText(stmt, 1) ?? "",
                fileID: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                startLine: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3)),
                endLine: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4)),
                symbolID: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
                confidence: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6)
            ))
        }
        return rows
    }

    // MARK: - Low-level SQLite helpers

    /// Runs a non-returning statement with caller-provided bindings.
    private func run(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind(stmt)
        sqlite3_step(stmt)
    }

    /// Runs a query, invoking `each` once per result row.
    private func query(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }, each: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW { each(stmt) }
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindIntOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int(stmt, index, Int32(value)) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindInt64OrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int64?) {
        if let value { sqlite3_bind_int64(stmt, index, value) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }
}
