import SwiftUI

struct GraphPayload: Codable, Equatable {
    var title: String
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var isPlaceholder: Bool = false

    static var empty: GraphPayload {
        GraphPayload(title: "Graph", nodes: [], edges: [], isPlaceholder: true)
    }
}

struct GraphNode: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var kind: String
    var path: String?
    var weight: Int = 1
}

struct GraphEdge: Codable, Identifiable, Equatable {
    var id: String
    var source: String
    var target: String
    var label: String?
    var kind: String
    var status: String = "accepted"
    var origin: String = "deterministic"
}

@MainActor
struct GraphViewport: View {
    let payload: GraphPayload
    var onOpenSource: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = GraphLayout(payload: payload, size: proxy.size)

            ZStack {
                if payload.nodes.isEmpty {
                    Text("Graph data will appear here after intelligence builds relationships.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Canvas { context, size in
                        drawEdges(layout.edges, nodes: layout.nodeByID, in: &context)
                        drawNodes(layout.nodes, in: &context)
                    }

                    ForEach(layout.nodes.filter { $0.path != nil }) { node in
                        Button {
                            if let path = node.path { onOpenSource(path) }
                        } label: {
                            Circle()
                                .fill(.clear)
                                .frame(width: node.hitSize, height: node.hitSize)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .position(node.point)
                        .help(node.label)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func drawEdges(_ edges: [GraphLayout.PlacedEdge], nodes: [String: GraphLayout.PlacedNode], in context: inout GraphicsContext) {
        for edge in edges {
            guard let source = nodes[edge.source], let target = nodes[edge.target] else { continue }

            let vector = CGVector(dx: target.point.x - source.point.x, dy: target.point.y - source.point.y)
            let length = max(1, hypot(vector.dx, vector.dy))
            let startInset = source.radius + 3
            let endInset = target.radius + 5
            let start = CGPoint(
                x: source.point.x + vector.dx / length * startInset,
                y: source.point.y + vector.dy / length * startInset
            )
            let end = CGPoint(
                x: target.point.x - vector.dx / length * endInset,
                y: target.point.y - vector.dy / length * endInset
            )

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            let color = edge.status == "suggested"
                ? Color(red: 0.49, green: 0.83, blue: 0.99).opacity(0.55)
                : Color.white.opacity(0.28)
            let style = StrokeStyle(lineWidth: edge.status == "suggested" ? 1.4 : 1.0, lineCap: .round, dash: edge.status == "suggested" ? [5, 4] : [])
            context.stroke(path, with: .color(color), style: style)

            let arrowSize: CGFloat = 6
            let angle = atan2(vector.dy, vector.dx)
            var arrow = Path()
            arrow.move(to: end)
            arrow.addLine(to: CGPoint(x: end.x - cos(angle - .pi / 7) * arrowSize, y: end.y - sin(angle - .pi / 7) * arrowSize))
            arrow.addLine(to: CGPoint(x: end.x - cos(angle + .pi / 7) * arrowSize, y: end.y - sin(angle + .pi / 7) * arrowSize))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(color))
        }
    }

    private func drawNodes(_ nodes: [GraphLayout.PlacedNode], in context: inout GraphicsContext) {
        for node in nodes {
            let halo = CGRect(
                x: node.point.x - node.radius - 6,
                y: node.point.y - node.radius - 6,
                width: (node.radius + 6) * 2,
                height: (node.radius + 6) * 2
            )
            context.fill(Path(ellipseIn: halo), with: .color(node.color.opacity(0.14)))

            let rect = CGRect(
                x: node.point.x - node.radius,
                y: node.point.y - node.radius,
                width: node.radius * 2,
                height: node.radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(node.color.opacity(0.92)))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(node.path == nil ? 0.42 : 0.78)), lineWidth: node.path == nil ? 1 : 1.4)

            let label = node.displayLabel
            let labelWidth = min(CGFloat(max(44, label.count * 6 + 14)), 124)
            let labelRect = CGRect(
                x: node.point.x - labelWidth / 2,
                y: node.point.y + node.radius + 6,
                width: labelWidth,
                height: 18
            )
            context.fill(Path(roundedRect: labelRect, cornerRadius: 5), with: .color(.black.opacity(0.42)))
            context.draw(
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9)),
                at: CGPoint(x: labelRect.midX, y: labelRect.midY),
                anchor: .center
            )
        }
    }
}

private struct GraphLayout {
    struct PlacedNode: Identifiable {
        var id: String
        var label: String
        var kind: String
        var path: String?
        var point: CGPoint
        var radius: CGFloat
        var color: Color

        var hitSize: CGFloat { max(44, radius * 2 + 18) }

        var displayLabel: String {
            guard label.count > 24 else { return label }
            return String(label.prefix(21)) + "..."
        }
    }

    struct PlacedEdge: Identifiable {
        var id: String
        var source: String
        var target: String
        var label: String?
        var status: String
    }

    var nodes: [PlacedNode]
    var edges: [PlacedEdge]
    var nodeByID: [String: PlacedNode]

    init(payload: GraphPayload, size: CGSize) {
        let canvas = CGSize(width: max(size.width, 320), height: max(size.height, 260))
        let degrees = payload.edges.reduce(into: [String: Int]()) { result, edge in
            result[edge.source, default: 0] += 1
            result[edge.target, default: 0] += 1
        }
        let sorted = payload.nodes.sorted { lhs, rhs in
            let lhsRank = lhs.weight + degrees[lhs.id, default: 0]
            let rhsRank = rhs.weight + degrees[rhs.id, default: 0]
            if lhs.kind == "project" && rhs.kind != "project" { return true }
            if rhs.kind == "project" && lhs.kind != "project" { return false }
            return lhsRank == rhsRank
                ? lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                : lhsRank > rhsRank
        }

        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2 - 8)
        let positions = Self.positions(count: sorted.count, center: center, size: canvas, hasCenterNode: sorted.first?.kind == "project")

        nodes = zip(sorted.indices, sorted).map { index, node in
            let degree = degrees[node.id, default: 0]
            let radius = CGFloat(min(24, max(12, 12 + node.weight * 2 + degree)))
            return PlacedNode(
                id: node.id,
                label: node.label,
                kind: node.kind,
                path: node.path,
                point: positions[index],
                radius: radius,
                color: Self.color(for: node.kind)
            )
        }
        let visibleIDs = Set(nodes.map(\.id))
        edges = payload.edges
            .filter { visibleIDs.contains($0.source) && visibleIDs.contains($0.target) }
            .map { PlacedEdge(id: $0.id, source: $0.source, target: $0.target, label: $0.label, status: $0.status) }
        nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    private static func positions(count: Int, center: CGPoint, size: CGSize, hasCenterNode: Bool) -> [CGPoint] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [center] }

        let horizontalRadius = max(96, size.width * 0.36)
        let verticalRadius = max(76, size.height * 0.32)

        if hasCenterNode {
            var result = [center]
            result.append(contentsOf: ringPositions(count: count - 1, center: center, horizontalRadius: horizontalRadius, verticalRadius: verticalRadius, phase: -.pi / 2))
            return result
        }

        if count <= 14 {
            return ringPositions(count: count, center: center, horizontalRadius: horizontalRadius, verticalRadius: verticalRadius, phase: -.pi / 2)
        }

        let innerCount = min(10, max(5, count / 3))
        let inner = ringPositions(count: innerCount, center: center, horizontalRadius: horizontalRadius * 0.52, verticalRadius: verticalRadius * 0.52, phase: -.pi / 2)
        let outer = ringPositions(count: count - innerCount, center: center, horizontalRadius: horizontalRadius, verticalRadius: verticalRadius, phase: -.pi / 2 + 0.18)
        return inner + outer
    }

    private static func ringPositions(count: Int, center: CGPoint, horizontalRadius: CGFloat, verticalRadius: CGFloat, phase: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let angle = phase + (CGFloat(index) / CGFloat(count)) * .pi * 2
            return CGPoint(
                x: center.x + cos(angle) * horizontalRadius,
                y: center.y + sin(angle) * verticalRadius
            )
        }
    }

    private static func color(for kind: String) -> Color {
        switch kind {
        case "project": return Color(red: 0.54, green: 0.71, blue: 0.97)
        case "folder": return Color(red: 0.96, green: 0.77, blue: 0.32)
        case "artifact": return Color(red: 0.84, green: 0.68, blue: 0.98)
        case "file": return Color(red: 0.51, green: 0.79, blue: 0.59)
        case "note": return Color(red: 0.49, green: 0.83, blue: 0.99)
        case "module": return Color(red: 0.95, green: 0.55, blue: 0.51)
        default: return Color(red: 0.78, green: 0.78, blue: 0.78)
        }
    }
}
