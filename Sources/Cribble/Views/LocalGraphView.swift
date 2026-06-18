import SwiftUI

enum LocalGraphLayout {
    static func positions(for graph: LocalNoteGraph, in size: CGSize) -> [URL: CGPoint] {
        guard size.width > 0, size.height > 0 else { return [:] }
        let centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        let radiusBase = min(size.width, size.height)
        let grouped = Dictionary(grouping: graph.nodes, by: \.distance)
        var positions: [URL: CGPoint] = [:]

        for node in grouped[0] ?? [] {
            positions[node.url] = centerPoint
        }

        for distance in grouped.keys.sorted() where distance > 0 {
            let nodes = (grouped[distance] ?? []).sorted {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
            }
            let radius = radiusBase * min(0.44, 0.22 + (Double(distance) * 0.12))
            for (index, node) in nodes.enumerated() {
                let angle = (-Double.pi / 2) + (2 * Double.pi * Double(index) / Double(max(1, nodes.count)))
                positions[node.url] = CGPoint(
                    x: centerPoint.x + CGFloat(cos(angle) * radius),
                    y: centerPoint.y + CGFloat(sin(angle) * radius)
                )
            }
        }

        return positions
    }
}

enum LocalGraphAccessibility {
    static func label(for node: LocalNoteGraph.Node) -> String {
        if node.isCurrent {
            return "\(node.title), current note"
        }
        let hopLabel = node.distance == 1 ? "1 hop away" : "\(node.distance) hops away"
        return "\(node.title), \(hopLabel)"
    }
}

struct LocalGraphView: View {
    let graph: LocalNoteGraph
    let onSelect: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)

                Text("Local Graph")
                    .font(.subheadline.weight(.semibold))

                Text("\(graph.nodes.count)")
                    .font(.caption2.monospaced())
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
                    }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Local Graph, \(graph.nodes.count) notes and \(graph.edges.count) links")

            GeometryReader { proxy in
                let positions = LocalGraphLayout.positions(for: graph, in: proxy.size)
                ZStack {
                    Canvas { context, _ in
                        drawEdges(context: context, positions: positions)
                    }
                    .accessibilityHidden(true)

                    ForEach(graph.nodes) { node in
                        if let point = positions[node.url] {
                            LocalGraphNodeButton(node: node) {
                                guard !node.isCurrent else { return }
                                onSelect(node.url)
                            }
                            .position(point)
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .contain)
            .accessibilityHint(reduceMotion ? "Static graph layout" : "Graph layout is static and does not animate")
        }
        .padding(12)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 10))
    }

    private func drawEdges(context: GraphicsContext, positions: [URL: CGPoint]) {
        for edge in graph.edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            context.stroke(path, with: .color(.secondary.opacity(0.26)), lineWidth: 1)
        }
    }
}

private struct LocalGraphNodeButton: View {
    let node: LocalNoteGraph.Node
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Circle()
                    .fill(node.isCurrent ? Color.accentColor.opacity(0.82) : Color.secondary.opacity(0.42))
                    .overlay {
                        Circle().strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    }
                    .frame(width: node.isCurrent ? 26 : 20, height: node.isCurrent ? 26 : 20)

                Text(node.title)
                    .font(.caption2.weight(node.isCurrent ? .semibold : .regular))
                    .foregroundStyle(node.isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
        .disabled(node.isCurrent)
        .accessibilityLabel(LocalGraphAccessibility.label(for: node))
        .accessibilityHint(node.isCurrent ? "This is the open note" : "Opens this note")
        .help(node.isCurrent ? "Current note" : "Open \(node.title)")
    }
}
