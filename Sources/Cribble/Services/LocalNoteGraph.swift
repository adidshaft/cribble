import Foundation

struct LocalNoteGraph: Equatable {
    struct Node: Identifiable, Hashable {
        let url: URL
        let title: String
        let distance: Int
        let isCurrent: Bool

        var id: URL { url }
    }

    struct Edge: Hashable {
        let source: URL
        let target: URL
    }

    let center: URL
    let nodes: [Node]
    let edges: [Edge]

    static func neighborhood(
        of center: URL,
        documents: [MarkdownDocumentMeta],
        rootURL: URL,
        hops: Int,
        maxNodes: Int = 40
    ) -> LocalNoteGraph {
        let centerURL = center.standardizedFileURL
        let cappedHops = max(0, hops)
        let cappedNodes = max(1, maxNodes)
        let documentsByPath = Dictionary(uniqueKeysWithValues: documents.map { ($0.url.standardizedFileURL.path, $0) })
        let linkIndex = LinkIndex(documentMetas: documents, rootURL: rootURL)
        var directedEdges = Set<Edge>()

        for document in documents {
            let source = document.url.standardizedFileURL
            for link in document.outboundLinks {
                guard let target = linkIndex.resolve(link).targetURL?.standardizedFileURL,
                      target != source,
                      documentsByPath[target.path] != nil
                else { continue }
                directedEdges.insert(Edge(source: source, target: target))
            }
        }

        let outgoing = Dictionary(grouping: directedEdges, by: \.source)
        let incoming = Dictionary(grouping: directedEdges, by: \.target)
        var distances: [URL: Int] = [centerURL: 0]
        var frontier: [URL] = [centerURL]

        if cappedHops > 0 {
            for distance in 1...cappedHops {
                let next = frontier
                    .flatMap { url -> [URL] in
                        let out = outgoing[url, default: []].map(\.target)
                        let back = incoming[url, default: []].map(\.source)
                        return out + back
                    }
                    .filter { distances[$0] == nil }
                    .sorted(by: compareURLs)

                guard !next.isEmpty else { break }
                for url in next where distances.count < cappedNodes {
                    distances[url] = distance
                }
                frontier = next.filter { distances[$0] == distance }
                if distances.count >= cappedNodes { break }
            }
        }

        let nodes = distances.compactMap { url, distance -> Node? in
            guard let document = documentsByPath[url.standardizedFileURL.path] else { return nil }
            return Node(url: url, title: document.title, distance: distance, isCurrent: url == centerURL)
        }
        .sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return compareURLs($0.url, $1.url)
        }

        let kept = Set(nodes.map(\.url))
        let edges = directedEdges
            .filter { kept.contains($0.source) && kept.contains($0.target) }
            .sorted {
                let sourceOrder = $0.source.path.localizedCaseInsensitiveCompare($1.source.path)
                if sourceOrder != .orderedSame { return sourceOrder == .orderedAscending }
                return compareURLs($0.target, $1.target)
            }

        return LocalNoteGraph(center: centerURL, nodes: nodes, edges: edges)
    }

    private static func compareURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}
