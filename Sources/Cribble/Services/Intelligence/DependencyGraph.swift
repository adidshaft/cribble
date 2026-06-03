import Foundation

/// A deterministic dependency graph derived from parsed symbols. This is the
/// "static analysis ground truth" the research doc insists on (§1.1/§6): the SLM
/// narrates *this* graph rather than inventing structure, and drift is computed
/// as a diff against it — not a vibe.
///
/// Phase-1 edges are coarse: a file → module edge per `import`, and a file →
/// file edge when one file declares a type whose name another file references in
/// a declaration signature. Imprecise, but verifiable and hallucination-free,
/// which is the whole point.
struct DependencyGraph: Sendable, Equatable {
    /// node id (file path or module name) → display label
    var nodes: [String: String]
    /// directed edges (from, to, label)
    var edges: [Edge]

    struct Edge: Sendable, Equatable, Hashable, Codable {
        let from: String
        let to: String
        let label: String
    }

    /// Builds the graph from a project's symbols.
    static func build(from symbols: [SymbolRecord]) -> DependencyGraph {
        var nodes: [String: String] = [:]
        var edges: Set<Edge> = []

        // Map of type name → declaring file, so we can resolve references.
        var typeOwners: [String: String] = [:]
        for s in symbols where s.kind == SwiftSymbol.Kind.type.rawValue || s.kind == SwiftSymbol.Kind.protocolType.rawValue {
            typeOwners[s.name] = s.filePath
        }

        for s in symbols {
            let fileNode = s.filePath
            nodes[fileNode] = (fileNode as NSString).lastPathComponent

            switch s.kind {
            case SwiftSymbol.Kind.importDecl.rawValue:
                let moduleNode = "module:\(s.name)"
                nodes[moduleNode] = s.name
                edges.insert(Edge(from: fileNode, to: moduleNode, label: "import"))
            default:
                // If this declaration's signature references a known type owned by
                // another file, record a file→file dependency edge.
                guard let signature = s.signature else { continue }
                for (typeName, ownerPath) in typeOwners where ownerPath != fileNode {
                    if signatureReferences(signature, typeName: typeName) {
                        nodes[ownerPath] = (ownerPath as NSString).lastPathComponent
                        edges.insert(Edge(from: fileNode, to: ownerPath, label: "uses"))
                    }
                }
            }
        }
        return DependencyGraph(nodes: nodes, edges: Array(edges).sorted { $0.from + $0.to < $1.from + $1.to })
    }

    /// Whether `signature` references `typeName` as a whole word.
    private static func signatureReferences(_ signature: String, typeName: String) -> Bool {
        guard let range = signature.range(of: typeName) else { return false }
        let before = range.lowerBound == signature.startIndex ? nil : signature[signature.index(before: range.lowerBound)]
        let after = range.upperBound == signature.endIndex ? nil : signature[range.upperBound]
        func isWordChar(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isLetter || c.isNumber || c == "_"
        }
        return !isWordChar(before) && !isWordChar(after)
    }

    /// Renders a Mermaid `graph LR`. Node ids are sanitized; labels keep the
    /// original name. Capped to keep diagrams legible (research §2: never render
    /// the whole repo at once).
    func mermaid(maxNodes: Int = 40, clickable: Bool = false) -> String {
        // Keep the most-connected nodes when over budget.
        var degree: [String: Int] = [:]
        for e in edges { degree[e.from, default: 0] += 1; degree[e.to, default: 0] += 1 }
        let kept = Set(nodes.keys.sorted { (degree[$0] ?? 0) > (degree[$1] ?? 0) }.prefix(maxNodes))

        var lines = ["graph LR"]
        for id in kept.sorted() {
            lines.append("    \(sanitize(id))[\"\(escape(nodes[id] ?? id))\"]")
        }
        for e in edges where kept.contains(e.from) && kept.contains(e.to) {
            lines.append("    \(sanitize(e.from)) -->|\(e.label)| \(sanitize(e.to))")
        }
        // Make file nodes navigable: a `cribble://open/<path>` link the HUD's
        // diagram view intercepts to open the source file (design plan §13 Phase 2).
        if clickable {
            for id in kept.sorted() where !id.hasPrefix("module:") {
                let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
                lines.append("    click \(sanitize(id)) \"cribble://open/\(encoded)\" \"Open \(escape(nodes[id] ?? id))\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func sanitize(_ id: String) -> String {
        let mapped = id.map { ($0.isLetter || $0.isNumber) ? $0 : "_" }
        return "n_" + String(mapped)
    }

    private func escape(_ label: String) -> String {
        label.replacingOccurrences(of: "\"", with: "'")
    }

    // MARK: - Drift

    /// A drift finding: an edge present in the documented diagram but missing in
    /// the code graph, or vice-versa.
    struct Drift: Sendable, Equatable {
        enum Kind: String, Sendable { case missingInCode, missingInDiagram }
        let kind: Kind
        let edge: Edge
    }

    /// Compares a previously-documented set of edges against the current code
    /// graph and reports differences. This is the killer signal from the research
    /// doc (§4.1): a graph diff, validated against static analysis.
    func drift(comparedToDocumented documented: [Edge]) -> [Drift] {
        let codeSet = Set(edges)
        let docSet = Set(documented)
        var result: [Drift] = []
        for e in docSet.subtracting(codeSet) { result.append(Drift(kind: .missingInCode, edge: e)) }
        for e in codeSet.subtracting(docSet) { result.append(Drift(kind: .missingInDiagram, edge: e)) }
        return result.sorted { $0.edge.from + $0.edge.to < $1.edge.from + $1.edge.to }
    }
}
