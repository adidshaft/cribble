import Foundation

/// Builds an Obsidian-style connections graph for a folder of notes — nodes are
/// Markdown files, edges are `[[wiki links]]` between them. Deterministic and
/// model-free; reuses `DependencyGraph` so it renders (and becomes clickable) the
/// same way as the code dependency map.
enum NoteConnectionsGraph {

    /// Files are `(relativePath, absoluteURL)` for every Markdown file in the
    /// project. Returns a graph whose node ids are relative paths (so clicks open
    /// the note in the reader).
    static func build(markdownFiles: [(path: String, url: URL)]) -> DependencyGraph {
        // Index notes by lower-cased basename (without extension) for link resolution.
        var byName: [String: String] = [:]   // basename → relative path
        for file in markdownFiles {
            let base = (file.path as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension.lowercased()
            byName[stem] = file.path
        }

        var nodes: [String: String] = [:]
        var edges: Set<DependencyGraph.Edge> = []

        for file in markdownFiles {
            nodes[file.path] = (file.path as NSString).lastPathComponent
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            for target in wikiLinkTargets(in: content) {
                guard let destPath = byName[target.lowercased()], destPath != file.path else { continue }
                nodes[destPath] = (destPath as NSString).lastPathComponent
                edges.insert(DependencyGraph.Edge(from: file.path, to: destPath, label: "links"))
            }
        }
        return DependencyGraph(nodes: nodes, edges: Array(edges).sorted { $0.from + $0.to < $1.from + $1.to })
    }

    /// Extracts wiki-link targets from `[[Target]]`, `[[Target|Alias]]`,
    /// `[[Target#Heading]]`. Returns the bare target name (no alias/heading/ext).
    static func wikiLinkTargets(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let ns = content as NSString
        var targets: [String] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            var inner = ns.substring(with: match.range(at: 1))
            if let pipe = inner.firstIndex(of: "|") { inner = String(inner[..<pipe]) }
            if let hash = inner.firstIndex(of: "#") { inner = String(inner[..<hash]) }
            inner = inner.trimmingCharacters(in: .whitespaces)
            let stem = (inner as NSString).lastPathComponent
            let withoutExt = (stem as NSString).deletingPathExtension
            if !withoutExt.isEmpty { targets.append(withoutExt) }
        }
        return targets
    }
}
