import Foundation

/// Reads git state for a project by shelling out to the `git` binary. Used by the
/// diff/commit intelligence jobs. Degrades gracefully: if the folder isn't a git
/// repo or `git` isn't available (or is blocked by the App Store sandbox), every
/// method returns empty rather than throwing, so intelligence keeps working
/// without git.
struct GitInspector: Sendable {
    let rootURL: URL

    /// Whether `rootURL` is inside a working git repository.
    func isRepository() async -> Bool {
        let out = await run(["rev-parse", "--is-inside-work-tree"])
        return out?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// The unified diff of the working tree (unstaged + staged) vs HEAD.
    func workingTreeDiff() async -> String? {
        await run(["diff", "HEAD"])
    }

    /// Short status (porcelain) — list of changed paths.
    func changedPaths() async -> [String] {
        guard let out = await run(["status", "--porcelain"]) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let trimmed = line.dropFirst(3) // status code + space
            return trimmed.isEmpty ? nil : String(trimmed)
        }
    }

    /// Recent commits as (sha, author, isoDate, subject) tuples, newest first.
    func recentCommits(limit: Int = 30) async -> [(sha: String, author: String, date: String, subject: String)] {
        // Unit-separator delimited fields to survive odd subjects.
        let format = "%H%x1f%an%x1f%aI%x1f%s"
        guard let out = await run(["log", "-n", "\(limit)", "--pretty=format:\(format)"]) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 4 else { return nil }
            return (sha: parts[0], author: parts[1], date: parts[2], subject: parts[3])
        }
    }

    /// The diff introduced by a single commit.
    func diff(forCommit sha: String) async -> String? {
        await run(["show", "--no-color", "--format=%B", sha])
    }

    // MARK: - Process

    private func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runSync(arguments, cwd: rootURL))
            }
        }
    }

    private static func runSync(_ arguments: [String], cwd: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", cwd.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()   // swallow stderr
        do {
            try process.run()
        } catch {
            return nil   // git unavailable / sandbox blocked
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
