
// Shared plumbing for the standard controls: control size, glyph shapes, and small helpers.

// MARK: - ControlSize

enum ControlSizeKey: EnvironmentKey { static let defaultValue = ControlSize.regular }

extension EnvironmentValues {
    public var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }
}

extension View {
    public func controlSize(_ controlSize: ControlSize) -> some View { env { $0.controlSize = controlSize } }
}

// MARK: - Embedding already-resolved nodes

/// Lets a control that resolved its content into nodes (to inspect tags, pick the selected one, ...)
/// place those nodes inside an ordinary composite view.
struct _NodeView: View, PrimitiveView {
    typealias Body = Never
    let node: Node
    init(_ node: Node) { self.node = node }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { out.append(node) }
}

/// Several resolved nodes placed as one transparent view.
struct _NodesView: View, PrimitiveView {
    typealias Body = Never
    let nodes: [Node]
    init(_ nodes: [Node]) { self.nodes = nodes }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { out.append(contentsOf: nodes) }
}

// MARK: - Glyph shapes (drawn rather than taken from SF Symbols so controls look right without symbol art)

enum ChevronDirection { case right, left, up, down }

/// A chevron ">" pointing in the given direction, filling its rect.
struct ChevronShape: Shape {
    var direction: ChevronDirection = .right
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .right:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .left:
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .down:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .up:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return p
    }
}

/// A chevron glyph view with round caps.
struct Chevron: View {
    var direction: ChevronDirection = .right
    var width: CGFloat = 7
    var height: CGFloat = 12
    var weight: CGFloat = 2
    var color: AnyShapeStyle = AnyShapeStyle(ForegroundStyle())
    var body: some View {
        ChevronShape(direction: direction)
            .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
            .frame(width: direction == .up || direction == .down ? height : width,
                   height: direction == .up || direction == .down ? width : height)
    }
}

/// The up/down chevron pair used by menu pickers.
struct UpDownChevron: View {
    var color: AnyShapeStyle = AnyShapeStyle(ForegroundStyle())
    var body: some View {
        VStack(spacing: 2.5) {
            ChevronShape(direction: .up).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 7, height: 4)
            ChevronShape(direction: .down).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 7, height: 4)
        }
    }
}

struct CheckmarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

struct Checkmark: View {
    var color: AnyShapeStyle = AnyShapeStyle(TintShapeStyle())
    var body: some View {
        CheckmarkShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .frame(width: 14, height: 11)
    }
}

// MARK: - Helpers

extension View {
    /// Soft two-layer shadow used by switch knobs, slider thumbs and the selected segment.
    func knobShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.15), radius: 2.5, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.12), radius: 0.5, x: 0, y: 0.5)
    }
}
