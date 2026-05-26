import Foundation

struct FolderScanner {
    func scan(rootURL: URL) throws -> [MarkdownNode] {
        try createReadmeIfNeeded(in: rootURL)
        return try scanChildren(in: rootURL)
    }

    private func scanChildren(in folderURL: URL) throws -> [MarkdownNode] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .localizedNameKey, .creationDateKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
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
                try createReadmeIfNeeded(in: url)
                let children = try scanChildren(in: url)
                folders.append(
                    MarkdownNode(
                        id: url.standardizedFileURL,
                        name: name,
                        url: url,
                        kind: .folder,
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate,
                        readmeURL: readmeURL(in: url),
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

    init(fileSortMode: FileSortMode = .name) {
        self.fileSortMode = fileSortMode
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
}
