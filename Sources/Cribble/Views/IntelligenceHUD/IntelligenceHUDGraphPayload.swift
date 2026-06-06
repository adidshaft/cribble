import Foundation

extension GraphPayload {
    func pruned(maxNodes: Int, maxEdges: Int) -> GraphPayload {
        guard nodes.count > maxNodes || edges.count > maxEdges else { return self }

        let limitedEdges = Array(edges.prefix(maxEdges))
        let edgeDegree = limitedEdges.reduce(into: [String: Int]()) { result, edge in
            result[edge.source, default: 0] += 1
            result[edge.target, default: 0] += 1
        }
        let edgeNodeIDs = Set(limitedEdges.flatMap { [$0.source, $0.target] })
        let rankedNodes = nodes
            .filter { edgeNodeIDs.contains($0.id) || $0.weight >= 6 }
            .sorted { lhs, rhs in
                let lhsRank = edgeDegree[lhs.id, default: 0] + lhs.weight
                let rhsRank = edgeDegree[rhs.id, default: 0] + rhs.weight
                return lhsRank == rhsRank
                    ? lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                    : lhsRank > rhsRank
            }
        let visibleNodes = Array(rankedNodes.prefix(maxNodes))
        let visibleIDs = Set(visibleNodes.map(\.id))
        let visibleEdges = limitedEdges.filter { visibleIDs.contains($0.source) && visibleIDs.contains($0.target) }

        return GraphPayload(
            title: title,
            nodes: visibleNodes,
            edges: visibleEdges,
            isPlaceholder: isPlaceholder
        )
    }

    static func intelligence(
        projectName: String?,
        filesIndexed: Int,
        knowledgeNodes: [KnowledgeNode] = [],
        knowledgeEdges: [KnowledgeEdge] = [],
        artifacts: [IntelligenceArtifact],
        content: (IntelligenceArtifact) -> String?
    ) -> GraphPayload {
        if !knowledgeNodes.isEmpty {
            let nodes = knowledgeNodes.map { node in
                GraphNode(
                    id: node.id,
                    label: node.title,
                    kind: node.kind.graphKind,
                    path: node.path,
                    weight: node.kind == .module ? 4 : 3
                )
            }
            let nodeIDs = Set(nodes.map(\.id))
            let edges = knowledgeEdges
                .filter { nodeIDs.contains($0.fromNodeID) && nodeIDs.contains($0.toNodeID) }
                .map { edge in
                    GraphEdge(
                        id: edge.id,
                        source: edge.fromNodeID,
                        target: edge.toNodeID,
                        label: edge.kind.graphLabel,
                        kind: edge.kind.rawValue,
                        status: edge.status.rawValue,
                        origin: edge.origin.rawValue
                    )
                }
            return GraphPayload(
                title: projectName.map { "\($0) Graph" } ?? "Project Graph",
                nodes: nodes,
                edges: edges,
                isPlaceholder: false
            )
        }

        if let graphArtifact = artifacts.first(where: { $0.type == .dependencyDiagram || $0.type == .connectionsGraph }),
           let body = content(graphArtifact),
           let mermaid = Self.firstMermaidBlock(in: body),
           let parsed = Self.parseMermaidGraph(mermaid, title: graphArtifact.title ?? graphArtifact.relativePath) {
            return parsed
        }

        return placeholder(projectName: projectName, filesIndexed: filesIndexed, artifacts: artifacts)
    }

    private static func placeholder(
        projectName: String?,
        filesIndexed: Int,
        artifacts: [IntelligenceArtifact]
    ) -> GraphPayload {
        let projectID = "project"
        let displayName = projectName ?? "Project"
        var nodes: [GraphNode] = [
            GraphNode(id: projectID, label: displayName, kind: "project", weight: 7)
        ]
        var edges: [GraphEdge] = []

        if artifacts.isEmpty {
            nodes.append(GraphNode(id: "scan", label: "\(filesIndexed) indexed files", kind: "topic", weight: 4))
            nodes.append(GraphNode(id: "artifacts", label: "Artifacts pending", kind: "artifact", weight: 3))
            edges.append(GraphEdge(id: "project-scan", source: projectID, target: "scan", label: "scans", kind: "status"))
            edges.append(GraphEdge(id: "scan-artifacts", source: "scan", target: "artifacts", label: "builds", kind: "status"))
            return GraphPayload(title: "Project Graph", nodes: nodes, edges: edges, isPlaceholder: true)
        }

        let grouped = Dictionary(grouping: artifacts) { $0.type.displayGroup }
        for groupName in grouped.keys.sorted() {
            let groupID = "group-\(Self.stableID(groupName))"
            let groupItems = grouped[groupName] ?? []
            nodes.append(GraphNode(id: groupID, label: groupName, kind: "folder", weight: min(7, max(2, groupItems.count))))
            edges.append(GraphEdge(id: "edge-\(projectID)-\(groupID)", source: projectID, target: groupID, label: nil, kind: "contains"))
        }

        for artifact in artifacts.prefix(18) {
            let groupID = "group-\(Self.stableID(artifact.type.displayGroup))"
            let nodeID = "artifact-\(Self.stableID(artifact.id))"
            let path = Self.openablePath(for: artifact)
            nodes.append(
                GraphNode(
                    id: nodeID,
                    label: artifact.title ?? artifact.relativePath,
                    kind: artifact.type == .fileSummary ? "file" : "artifact",
                    path: path,
                    weight: artifact.type == .projectIndex ? 6 : 3
                )
            )
            edges.append(GraphEdge(id: "edge-\(groupID)-\(nodeID)", source: groupID, target: nodeID, label: nil, kind: "contains"))
        }

        return GraphPayload(title: "Project Graph", nodes: nodes, edges: edges, isPlaceholder: true)
    }

    private static func firstMermaidBlock(in markdown: String) -> String? {
        var lines: [String] = []
        var inBlock = false

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inBlock, trimmed.hasPrefix("```mermaid") {
                inBlock = true
                lines = []
            } else if inBlock, trimmed == "```" {
                return lines.joined(separator: "\n")
            } else if inBlock {
                lines.append(line)
            }
        }

        return inBlock && !lines.isEmpty ? lines.joined(separator: "\n") : nil
    }

    private static func parseMermaidGraph(_ source: String, title: String) -> GraphPayload? {
        var nodesByID: [String: GraphNode] = [:]
        var pathsByID: [String: String] = [:]
        var edges: [GraphEdge] = []

        let nodeRegex = try? NSRegularExpression(pattern: #"^\s*([A-Za-z0-9_]+)\["([^"]+)"\]"#)
        let edgeRegex = try? NSRegularExpression(pattern: #"^\s*([A-Za-z0-9_]+)\s*-->\s*(?:\|([^|]+)\|\s*)?([A-Za-z0-9_]+)"#)
        let clickRegex = try? NSRegularExpression(pattern: #"^\s*click\s+([A-Za-z0-9_]+)\s+call\s+cribbleOpen\("([^"]+)"\)"#)

        for line in source.components(separatedBy: "\n") {
            let ns = line as NSString
            let fullRange = NSRange(location: 0, length: ns.length)

            if let match = clickRegex?.firstMatch(in: line, range: fullRange), match.numberOfRanges >= 3 {
                let nodeID = ns.substring(with: match.range(at: 1))
                pathsByID[nodeID] = ns.substring(with: match.range(at: 2))
                continue
            }

            if let match = nodeRegex?.firstMatch(in: line, range: fullRange), match.numberOfRanges >= 3 {
                let nodeID = ns.substring(with: match.range(at: 1))
                let label = ns.substring(with: match.range(at: 2))
                nodesByID[nodeID] = GraphNode(id: nodeID, label: label, kind: Self.kind(for: label, path: nil), weight: 3)
                continue
            }

            if let match = edgeRegex?.firstMatch(in: line, range: fullRange), match.numberOfRanges >= 4 {
                let sourceID = ns.substring(with: match.range(at: 1))
                let targetID = ns.substring(with: match.range(at: 3))
                let labelRange = match.range(at: 2)
                let label = labelRange.location == NSNotFound ? nil : ns.substring(with: labelRange)

                if nodesByID[sourceID] == nil {
                    nodesByID[sourceID] = GraphNode(id: sourceID, label: sourceID, kind: "topic", weight: 2)
                }
                if nodesByID[targetID] == nil {
                    nodesByID[targetID] = GraphNode(id: targetID, label: targetID, kind: "topic", weight: 2)
                }

                edges.append(
                    GraphEdge(
                        id: "edge-\(edges.count)-\(sourceID)-\(targetID)",
                        source: sourceID,
                        target: targetID,
                        label: label,
                        kind: label ?? "relationship"
                    )
                )
            }
        }

        guard !nodesByID.isEmpty else { return nil }

        let degree = edges.reduce(into: [String: Int]()) { result, edge in
            result[edge.source, default: 0] += 1
            result[edge.target, default: 0] += 1
        }

        let nodes = nodesByID.keys.sorted().map { id -> GraphNode in
            var node = nodesByID[id] ?? GraphNode(id: id, label: id, kind: "topic")
            node.path = pathsByID[id]
            node.kind = Self.kind(for: node.label, path: node.path)
            node.weight = min(8, max(2, degree[id, default: 1]))
            return node
        }

        return GraphPayload(title: title, nodes: nodes, edges: edges, isPlaceholder: false)
    }

    private static func kind(for label: String, path: String?) -> String {
        let value = (path ?? label).lowercased()
        if value.hasPrefix("module:") { return "module" }
        if value.hasSuffix(".md") { return "note" }
        if value.contains(".") || value.contains("/") { return "file" }
        return "topic"
    }

    private static func openablePath(for artifact: IntelligenceArtifact) -> String? {
        if artifact.type == .fileSummary {
            return artifact.title
        }
        return artifact.isPublished ? ".cribble/intelligence/\(artifact.relativePath)" : nil
    }

    private static func stableID(_ value: String) -> String {
        let mapped = value.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }
}

private extension KnowledgeNode.Kind {
    var graphKind: String {
        switch self {
        case .file: "file"
        case .artifact: "artifact"
        case .insight: "topic"
        case .module: "module"
        case .topic: "topic"
        }
    }
}

private extension KnowledgeEdge.Kind {
    var graphLabel: String {
        switch self {
        case .wikiLink: "wiki"
        case .dependency: "uses"
        case .semanticSimilarity: "suggested"
        case .researchSupports: "supports"
        case .researchQuestion: "asks"
        }
    }
}

private extension IntelligenceArtifactType {
    var displayGroup: String {
        switch self {
        case .projectIndex:
            return "Overview"
        case .connectionsGraph:
            return "Connections"
        case .architectureDiagram, .dependencyDiagram:
            return "Architecture"
        case .diffSummary, .commitSummary:
            return "Changes"
        case .fallbackAudit, .ioBehavior, .driftReport:
            return "Audits"
        case .fileSummary:
            return "Files"
        case .researchInsight:
            return "Research"
        }
    }
}
