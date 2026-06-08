import Foundation

struct FolderScanner {
    func scan(rootURL: URL) throws -> [MarkdownNode] {
        if autoCreateReadmes {
            try createReadmeIfNeeded(in: rootURL)
        }
        var state = ScanState()
        return try scanChildren(in: rootURL, depth: 0, state: &state)
    }

    private func scanChildren(in folderURL: URL, depth: Int, state: inout ScanState) throws -> [MarkdownNode] {
        guard depth <= maxDepth, state.visitedFolderCount < maxFolders else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .localizedNameKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]
        let folderValues = try folderURL.resourceValues(forKeys: resourceKeys)
        if let resourceIdentifier = folderValues.fileResourceIdentifier,
           !state.visitedResourceIDs.insert(String(describing: resourceIdentifier)).inserted {
            return []
        }
        state.visitedFolderCount += 1

        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var folders: [MarkdownNode] = []
        var files: [MarkdownNode] = []

        for url in urls {
            let values = try url.resourceValues(forKeys: resourceKeys)
            let name = values.localizedName ?? url.lastPathComponent

            guard values.isHidden != true, !name.hasPrefix(".") else {
                continue
            }

            if values.isDirectory == true {
                guard shouldScanDirectory(name: name, values: values) else {
                    continue
                }
                guard depth < maxDepth, state.visitedFolderCount < maxFolders else {
                    continue
                }
                if autoCreateReadmes {
                    try createReadmeIfNeeded(in: url)
                }
                let children = try scanChildren(in: url, depth: depth + 1, state: &state)
                folders.append(
                    MarkdownNode(
                        id: url.standardizedFileURL,
                        name: name,
                        url: url,
                        kind: .folder,
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate,
                        readmeURL: autoCreateReadmes ? readmeURL(in: url) : existingReadmeURL(in: url),
                        children: children
                    )
                )
            } else if url.pathExtension.lowercased() == "md" {
                files.append(
                    MarkdownNode(
                        id: url.standardizedFileURL,
                        name: url.deletingPathExtension().lastPathComponent,
                        url: url,
                        kind: .markdown,
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate,
                        readmeURL: nil,
                        children: []
                    )
                )
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort(by: fileComparator)
        return folders + files
    }

    private let fileSortMode: FileSortMode
    private let maxFolders: Int
    private let maxDepth: Int
    private let autoCreateReadmes: Bool

    init(fileSortMode: FileSortMode = .name, maxFolders: Int = 4_000, maxDepth: Int = 32, autoCreateReadmes: Bool = true) {
        self.fileSortMode = fileSortMode
        self.maxFolders = maxFolders
        self.maxDepth = maxDepth
        self.autoCreateReadmes = autoCreateReadmes
    }

    private func fileComparator(_ lhs: MarkdownNode, _ rhs: MarkdownNode) -> Bool {
        switch fileSortMode {
        case .name:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .created:
            compare(lhs.createdAt, rhs.createdAt, fallback: lhs.name, rhs.name)
        case .modified:
            compare(lhs.modifiedAt, rhs.modifiedAt, fallback: lhs.name, rhs.name)
        }
    }

    private func compare(_ lhs: Date?, _ rhs: Date?, fallback lhsName: String, _ rhsName: String) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            lhs > rhs
        default:
            lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    // ensured readmes are created in-pass during directory scanning

    private func createReadmeIfNeeded(in folderURL: URL) throws {
        let readmeURL = readmeURL(in: folderURL)
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else {
            return
        }

        let title = folderURL.lastPathComponent
        try "# \(title)\n".write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private func readmeURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("README.md")
    }

    private func existingReadmeURL(in folderURL: URL) -> URL? {
        let url = readmeURL(in: folderURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func shouldScanDirectory(name: String, values: URLResourceValues) -> Bool {
        guard values.isSymbolicLink != true, values.isPackage != true else {
            return false
        }
        return !Self.ignoredDirectoryNames.contains(name)
            && !Self.ignoredDirectoryNames.contains(name.lowercased())
    }

    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".cache",
        ".cribble",
        ".git",
        ".gradle",
        ".next",
        ".pytest_cache",
        ".swiftpm",
        ".terraform",
        ".turbo",
        ".venv",
        "__pycache__",
        "build",
        "coverage",
        "DerivedData",
        "dist",
        "node_modules",
        "Pods",
        "target",
        "vendor",
        "venv"
    ]

    private struct ScanState {
        var visitedFolderCount = 0
        var visitedResourceIDs = Set<String>()
    }
}
