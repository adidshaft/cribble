import Foundation

/// The single audited path for every mutation Cribble makes to a user's notes.
///
/// Guarantees, in service of "no accidental writes or deletions":
/// - **Atomic** writes (no torn files on crash/power loss).
/// - **Recoverable** overwrites — the previous contents of any file we replace
///   are copied into a capped backup store first, so every app-initiated change
///   can be undone even after the fact.
/// - **No silent clobber** — `create` refuses to overwrite an existing file.
/// - **No hard deletes** of user files — deletions go to the system Trash.
///
/// Caches and app-managed state (the intelligence DB, embeddings, artifact
/// cache) are deliberately out of scope; this is for the user's own `.md` files.
enum SafeFileWriter {
    enum WriteError: LocalizedError {
        case targetExists(URL)
        case externalChange(URL)

        var errorDescription: String? {
            switch self {
            case .targetExists(let url):
                "A file already exists at \(url.lastPathComponent)."
            case .externalChange(let url):
                "\(url.lastPathComponent) changed on disk since Cribble last read it — not overwriting."
            }
        }
    }

    // MARK: - Public API

    /// Overwrites `url` with `content`, backing up the prior contents first.
    /// When `expectedPriorContent` is provided, the write is aborted if the file
    /// on disk no longer matches it (an external edit happened) — guarding
    /// against clobbering changes made in another editor.
    static func overwrite(
        _ content: String,
        at url: URL,
        expectedPriorContent: String? = nil
    ) throws {
        let standardized = url.standardizedFileURL
        let existing = try? Data(contentsOf: standardized)

        if let expectedPriorContent,
           let existing,
           String(decoding: existing, as: UTF8.self) != expectedPriorContent {
            throw WriteError.externalChange(standardized)
        }

        if let existing {
            backUp(existing, for: standardized)
        }
        try writeAtomically(content, to: standardized)
    }

    /// Creates a new file, refusing to overwrite one that already exists.
    static func create(_ content: String, at url: URL) throws {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            throw WriteError.targetExists(standardized)
        }
        try writeAtomically(content, to: standardized)
    }

    /// Moves a user file to the system Trash (recoverable) rather than deleting.
    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url.standardizedFileURL, resultingItemURL: nil)
    }

    /// Restores the most recent backup for `url`, if any. The current contents
    /// are themselves backed up first, so an undo can be redone. Returns the
    /// restored text on success.
    @discardableResult
    static func restoreMostRecentBackup(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        guard let backup = mostRecentBackup(for: standardized),
              let data = try? Data(contentsOf: backup) else { return nil }
        let restored = String(decoding: data, as: UTF8.self)
        try? overwrite(restored, at: standardized)
        return restored
    }

    static func hasBackup(for url: URL) -> Bool {
        mostRecentBackup(for: url.standardizedFileURL) != nil
    }

    /// Snapshots the current on-disk contents of `url` into the backup store.
    /// For callers (like byte-level checkbox edits) that do their own atomic
    /// write but still want the change to be undoable.
    static func backUpExisting(at url: URL) {
        let standardized = url.standardizedFileURL
        guard let data = try? Data(contentsOf: standardized) else { return }
        backUp(data, for: standardized)
    }

    // MARK: - Internals

    private static let backupCap = 400

    private static func writeAtomically(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static var backupsDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("com.cribble.reader", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Backup file name: `<unixmillis>__<base64url(path)>.bak` — sortable by time
    /// and reversible back to the original path.
    private static func backUp(_ data: Data, for url: URL) {
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        let token = encodePath(url.path)
        let name = "\(millis)__\(token).bak"
        let dest = backupsDirectory.appendingPathComponent(name)
        try? data.write(to: dest, options: .atomic)
        pruneBackups()
    }

    private static func mostRecentBackup(for url: URL) -> URL? {
        let token = encodePath(url.path)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return entries
            .filter { $0.lastPathComponent.contains("__\(token).bak") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // millis prefix sorts newest first
            .first
    }

    private static func pruneBackups() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        guard entries.count > backupCap else { return }
        let oldestFirst = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in oldestFirst.prefix(entries.count - backupCap) {
            try? fm.removeItem(at: url)
        }
    }

    private static func encodePath(_ path: String) -> String {
        Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
