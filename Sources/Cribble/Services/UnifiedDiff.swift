import Foundation

struct UnifiedDiff: Equatable {
    var files: [DiffFile]

    var isEmpty: Bool {
        files.isEmpty
    }
}

struct DiffFile: Identifiable, Equatable {
    var id: String { newPath }
    let oldPath: String
    let newPath: String
    var hunks: [DiffHunk]
}

struct DiffHunk: Identifiable, Equatable {
    let id = UUID()
    let header: String
    var lines: [DiffLine]
}

struct DiffLine: Equatable {
    enum Kind: String {
        case context
        case addition
        case removal
    }

    let kind: Kind
    let text: String
}

enum UnifiedDiffParser {
    static func extractDiffText(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let firstDiffIndex = lines.firstIndex(where: { line in
            line.hasPrefix("diff --git ") || line.hasPrefix("--- a/") || line.hasPrefix("--- b/") || line.hasPrefix("--- /")
        }) else {
            return text
        }
        return lines[firstDiffIndex...].joined(separator: "\n")
    }

    static func parse(_ text: String) -> UnifiedDiff {
        var files: [DiffFile] = []
        var current: DiffFile?
        var currentHunk: DiffHunk?

        func flushHunk() {
            if let hunk = currentHunk {
                current?.hunks.append(hunk)
                currentHunk = nil
            }
        }

        func flushFile() {
            flushHunk()
            if let file = current, !file.hunks.isEmpty {
                files.append(file)
            }
            current = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.hasPrefix("diff --git ") {
                flushFile()
                continue
            }

            if rawLine.hasPrefix("--- ") {
                flushFile()
                let oldPath = cleanPath(String(rawLine.dropFirst(4)))
                current = DiffFile(oldPath: oldPath, newPath: oldPath, hunks: [])
                continue
            }

            if rawLine.hasPrefix("+++ ") {
                let newPath = cleanPath(String(rawLine.dropFirst(4)))
                if let file = current {
                    current = DiffFile(oldPath: file.oldPath, newPath: newPath, hunks: file.hunks)
                } else {
                    current = DiffFile(oldPath: newPath, newPath: newPath, hunks: [])
                }
                continue
            }

            if rawLine.hasPrefix("@@") {
                flushHunk()
                currentHunk = DiffHunk(header: rawLine, lines: [])
                continue
            }

            guard currentHunk != nil else { continue }
            if rawLine.hasPrefix("+"), !rawLine.hasPrefix("+++") {
                currentHunk?.lines.append(DiffLine(kind: .addition, text: String(rawLine.dropFirst())))
            } else if rawLine.hasPrefix("-"), !rawLine.hasPrefix("---") {
                currentHunk?.lines.append(DiffLine(kind: .removal, text: String(rawLine.dropFirst())))
            } else if rawLine.hasPrefix(" ") {
                currentHunk?.lines.append(DiffLine(kind: .context, text: String(rawLine.dropFirst())))
            }
        }

        flushFile()
        return UnifiedDiff(files: files)
    }

    private static func cleanPath(_ path: String) -> String {
        let withoutTimestamp = path.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? path
        let trimmed = withoutTimestamp
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }
}

enum DiffApplyError: LocalizedError {
    case fileNotFound(String)
    case hunkMismatch(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "Could not find \(path)."
        case .hunkMismatch(let path):
            "The file changed before the patch could be applied: \(path)."
        }
    }
}

struct DiffApplier {
    func apply(_ diff: UnifiedDiff, rootURL: URL) throws {
        for file in diff.files {
            try apply(file, rootURL: rootURL)
        }
    }

    private func apply(_ file: DiffFile, rootURL: URL) throws {
        let relativePath = file.newPath == "/dev/null" ? file.oldPath : file.newPath
        let fileURL = rootURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiffApplyError.fileNotFound(relativePath)
        }

        let original = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = original.components(separatedBy: "\n")

        for hunk in file.hunks {
            let expected = hunk.lines.compactMap { line -> String? in
                line.kind == .addition ? nil : line.text
            }
            let replacement = hunk.lines.compactMap { line -> String? in
                line.kind == .removal ? nil : line.text
            }

            guard let start = findSubsequence(expected, in: lines) else {
                throw DiffApplyError.hunkMismatch(relativePath)
            }

            lines.replaceSubrange(start..<(start + expected.count), with: replacement)
        }

        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func findSubsequence(_ needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return nil
        }

        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }
}
