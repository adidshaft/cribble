import Foundation

/// One stop on a reading trail: a note you visited, where it sits in the
/// navigation tree, how long you spent there, and how many times you came back.
struct ReadingTrailNode: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    let parentID: UUID?
    let depth: Int
    var seconds: TimeInterval
    var visitCount: Int
    let firstVisited: Date
}

/// Captures the active navigation session as a *tree* (not linear history) so a
/// research rabbit hole — Note A → wiki link → Note B → back → Note C — is
/// preserved with its branches, dwell time, and the highlights made along the
/// way. Session-scoped on purpose: the whole point is to turn the flow into a
/// durable Markdown note before it's lost.
@MainActor
final class ReadingTrailStore: ObservableObject {
    @Published private(set) var nodes: [ReadingTrailNode] = []
    @Published var isPanelVisible = false

    private var currentID: UUID?
    private var lastEnter = Date()

    var isEmpty: Bool { nodes.isEmpty }
    var currentNodeID: UUID? { currentID }

    /// Records arrival at a document. Revisiting any note already on the trail
    /// re-enters that existing node (so going back up the tree, or jumping
    /// around via the panel, never duplicates it). A genuinely new note becomes
    /// a child of wherever you currently are — which is what produces branches
    /// when you backtrack and then strike out in a new direction.
    func recordVisit(url: URL, title: String) {
        let now = Date()
        let standardized = url.standardizedFileURL
        finalizeCurrent(now: now)

        guard let currentID, let current = node(currentID) else {
            appendNode(url: standardized, title: title, parentID: nil, depth: 0, now: now)
            return
        }

        if current.url == standardized {
            lastEnter = now
            return
        }

        if let existing = nodes.first(where: { $0.url == standardized }) {
            revisit(existing.id, now: now)
            return
        }

        appendNode(url: standardized, title: title, parentID: currentID, depth: current.depth + 1, now: now)
    }

    func clear() {
        nodes = []
        currentID = nil
        lastEnter = Date()
    }

    /// Live dwell time, including the in-progress interval for the current node.
    func seconds(for node: ReadingTrailNode) -> TimeInterval {
        node.id == currentID ? node.seconds + Date().timeIntervalSince(lastEnter) : node.seconds
    }

    /// Depth-first preorder, so the panel can render the tree as an indented list.
    var orderedNodes: [ReadingTrailNode] {
        var childrenByParent: [UUID?: [ReadingTrailNode]] = [:]
        for node in nodes {
            childrenByParent[node.parentID, default: []].append(node)
        }

        var result: [ReadingTrailNode] = []
        func visit(_ parent: UUID?) {
            for child in childrenByParent[parent] ?? [] {
                result.append(child)
                visit(child.id)
            }
        }
        visit(nil)
        return result
    }

    var totalSeconds: TimeInterval {
        nodes.reduce(0) { $0 + seconds(for: $1) }
    }

    static func format(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let remainder = total % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    /// Synthesizes the trail into a Markdown note: a nested path of wiki links
    /// back into the graph, plus every highlight and margin note gathered along
    /// the way. Returns nil when the trail is empty.
    func makeTrailNote(annotations: ReadingAnnotationsStore) -> (fileName: String, content: String)? {
        guard !nodes.isEmpty else { return nil }

        let ordered = orderedNodes
        let topic = nodes.first?.title ?? "Reading"
        let fileBase = "Trail - \(topic)"

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = []
        lines.append("# \(fileBase)")
        lines.append("")
        lines.append("> Reading trail captured \(formatter.string(from: Date())) · \(nodes.count) note\(nodes.count == 1 ? "" : "s") · \(Self.format(seconds: totalSeconds)) total")
        lines.append("")

        lines.append("## Path")
        for node in ordered {
            let indent = String(repeating: "  ", count: node.depth)
            let revisited = node.visitCount > 1 ? " · ×\(node.visitCount)" : ""
            lines.append("\(indent)- [[\(node.title)]] · \(Self.format(seconds: seconds(for: node)))\(revisited)")
        }
        lines.append("")

        var highlightSections: [String] = []
        var seen = Set<URL>()
        for node in ordered where seen.insert(node.url).inserted {
            let highlights = annotations.highlights(for: node.url)
            guard !highlights.isEmpty else { continue }

            var section: [String] = ["### \(node.title)"]
            for highlight in highlights {
                let quote = highlight.quote.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = highlight.note.trimmingCharacters(in: .whitespacesAndNewlines)
                section.append("- " + (note.isEmpty ? "“\(quote)”" : "“\(quote)” — \(note)"))
            }
            section.append("")
            highlightSections.append(contentsOf: section)
        }

        if !highlightSections.isEmpty {
            lines.append("## Highlights & Notes")
            lines.append(contentsOf: highlightSections)
        }

        return (fileBase + ".md", lines.joined(separator: "\n"))
    }

    // MARK: - Internals

    private func node(_ id: UUID) -> ReadingTrailNode? { nodes.first { $0.id == id } }
    private func index(_ id: UUID) -> Int? { nodes.firstIndex { $0.id == id } }

    private func finalizeCurrent(now: Date) {
        guard let currentID, let idx = index(currentID) else { return }
        nodes[idx].seconds += now.timeIntervalSince(lastEnter)
    }

    private func appendNode(url: URL, title: String, parentID: UUID?, depth: Int, now: Date) {
        let node = ReadingTrailNode(
            id: UUID(),
            url: url,
            title: title,
            parentID: parentID,
            depth: depth,
            seconds: 0,
            visitCount: 1,
            firstVisited: now
        )
        nodes.append(node)
        currentID = node.id
        lastEnter = now
    }

    private func revisit(_ id: UUID, now: Date) {
        if let idx = index(id) {
            nodes[idx].visitCount += 1
        }
        currentID = id
        lastEnter = now
    }
}
