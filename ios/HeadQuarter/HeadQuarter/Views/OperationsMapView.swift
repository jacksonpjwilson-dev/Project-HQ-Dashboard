import SwiftUI

struct GraphSelection: Identifiable {
    var id: String
    var isEdge: Bool
}

struct OperationsMapView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var operations: OperationsStore
    let system: SystemDefinition
    var expanded = false
    var domain: FlowDomain = .runtime
    var onSelect: (GraphSelection) -> Void

    private var nodes: [OperationNode] {
        let allowed = Set(system.edges.filter { $0.domain == domain }.flatMap { [$0.from, $0.to] })
        let available = system.nodes.filter { allowed.contains($0.id) }
        if expanded { return available }
        return (0...2).flatMap { lane in Array(available.filter { $0.lane == lane }.prefix(4)) }
    }
    private func point(_ node: OperationNode, width: CGFloat, height: CGFloat) -> CGPoint {
        let lane = nodes.filter { $0.lane == node.lane }
        let index = lane.firstIndex(where: { $0.id == node.id }) ?? 0
        return CGPoint(x: width * (0.16 + CGFloat(node.lane) * 0.34),
                       y: height * CGFloat(index + 1) / CGFloat(lane.count + 1))
    }

    var body: some View {
        let theme = MissionTheme(name: system.theme)
        let height = CGFloat(max(nodes.filter { $0.lane == 0 }.count, nodes.filter { $0.lane == 1 }.count,
                                 nodes.filter { $0.lane == 2 }.count, 2) + 1) * 100
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            GeometryReader { geometry in
                ZStack {
                    ForEach(system.edges.filter { $0.domain == domain }) { edge in
                        if let source = nodes.first(where: { $0.id == edge.from }),
                           let destination = nodes.first(where: { $0.id == edge.to }) {
                            let start = point(source, width: geometry.size.width, height: height)
                            let end = point(destination, width: geometry.size.width, height: height)
                            let state = operations.state(for: edge, system: system, store: store, now: timeline.date)
                            let line = DirectedFlow(start: start, end: end)
                            line.stroke(state.color.opacity(state == .disabled ? 0.35 : 0.85),
                                        style: StrokeStyle(lineWidth: 1.7, dash: state == .missing ? [5, 5] : state == .unknown ? [2, 5] : []))
                                .contentShape(FlowHitArea(start: start, end: end))
                                .onTapGesture { onSelect(.init(id: edge.id, isEdge: true)) }
                                .accessibilityHidden(true)
                            if operations.checking.contains(edge.id) {
                                Image(systemName: "circle.fill").foregroundStyle(.cyan).font(.system(size: 8))
                                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                                    .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                                    .accessibilityLabel("Checking this connection")
                            }
                            Button { onSelect(.init(id: edge.id, isEdge: true)) } label: {
                                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9))
                                    .foregroundStyle(state.color).frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(source.title) to \(destination.title), \(edge.operation), \(state.title), owned by \(edge.owner)")
                                .rotationEffect(.radians(atan2(end.y - start.y, end.x - start.x)))
                                .foregroundStyle(state.color)
                                .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                                .zIndex(1)
                        }
                    }
                    ForEach(nodes) { node in
                        let state = operations.state(for: node, system: system, store: store, now: timeline.date)
                        Button { onSelect(.init(id: node.id, isEdge: false)) } label: {
                            VStack(spacing: 5) {
                                if node.id == system.id + ".app" {
                                    SystemArtwork(system: system, size: 44)
                                } else {
                                    Image(systemName: symbol(node)).font(.system(size: 19))
                                        .foregroundStyle(theme.accent).frame(height: 22)
                                }
                                Text(node.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                                    .multilineTextAlignment(.center).foregroundStyle(theme.ink)
                                HStack(spacing: 3) {
                                    if operations.checking.contains(node.id) { ProgressView().controlSize(.mini) }
                                    Image(systemName: state.symbol)
                                    Text(state.title)
                                }.font(.system(size: 9, weight: .medium)).foregroundStyle(state.color)
                            }.frame(width: min(geometry.size.width * 0.26, 112)).padding(.vertical, 9)
                                .background(theme.isDark ? Color(red: 0.05, green: 0.13, blue: 0.21) : .white.opacity(0.86),
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border))
                                .shadow(color: theme.accent.opacity(0.1), radius: 6, y: 2)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(node.title), \(state.title). Inspect node.")
                            .position(point(node, width: geometry.size.width, height: height))
                    }
                }
            }.frame(height: height)
        }
    }

    private func symbol(_ node: OperationNode) -> String {
        switch node.id.components(separatedBy: ".").last {
        case "calendar": return "calendar"
        case "reminders": return "checklist"
        case "weather": return "cloud.sun.fill"
        case "aviation", "provider", "feed": return "airplane"
        case "email": return "envelope.fill"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "widgets": return "square.stack.3d.up.fill"
        case "notifications", "alerts": return "bell.fill"
        case "watch": return "applewatch"
        case "storage": return "externaldrive.fill"
        default: return node.kind == "processor" ? "gearshape.2.fill" : node.kind == "monitor" ? "waveform.path.ecg" : "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct DirectedFlow: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let middle = (start.x + end.x) / 2
        path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y), control2: CGPoint(x: middle, y: end.y))
        return path
    }
}

private struct FlowHitArea: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        DirectedFlow(start: start, end: end).path(in: rect).strokedPath(StrokeStyle(lineWidth: 24))
    }
}
