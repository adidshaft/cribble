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

struct LocalGraphView: View {
    let graph: LocalNoteGraph

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
                Canvas { context, _ in
                    drawEdges(context: context, positions: positions)
                    drawNodes(context: context, positions: positions)
                }
            }
            .frame(height: 220)
            .accessibilityHidden(true)
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

    private func drawNodes(context: GraphicsContext, positions: [URL: CGPoint]) {
        for node in graph.nodes {
            guard let point = positions[node.url] else { continue }
            let radius: CGFloat = node.isCurrent ? 13 : 9
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(node.isCurrent ? .accentColor.opacity(0.82) : .secondary.opacity(0.42))
            )
            context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(0.14)), lineWidth: 1)

            let label = Text(node.title)
                .font(.caption2.weight(node.isCurrent ? .semibold : .regular))
                .foregroundStyle(node.isCurrent ? .primary : .secondary)
            context.draw(label, at: CGPoint(x: point.x, y: point.y + radius + 11), anchor: .center)
        }
    }
}
