// HStack / VStack / ZStack and Spacer, implementing SwiftUI's stack algorithm:
// children are offered the remaining space in order of increasing flexibility,
// grouped by layout priority.

let defaultStackSpacing: CGFloat = 8

final class StackNode: Node {
    let axis: Axis
    let crossAlignment: AlignmentKey
    let spacing: CGFloat?
    /// Two texts above one another are put the lower one's leading apart instead of the default 8pt
    /// (SwiftUI's text-to-text spacing, the same in every release since iOS 13). measured: iOS 27.0 and
    /// 26.5 simulators: body over body and subheadline over caption are 2pt apart (leading 22 - 20.3 and
    /// 16 - 14.3, rounded up to a pixel); the texts of every 26.5 screen sit where 27.0 puts them.
    var textToTextSpacing = false

    struct Result {
        var sizes: [CGSize] = []
        var mainOffsets: [CGFloat] = []
        var crossOffsets: [CGFloat] = []
        var size: CGSize = .zero
        var alignedLine: CGFloat = 0
    }
    private var results: [ProposedViewSize: Result] = [:]

    init(axis: Axis, alignment: AlignmentKey, spacing: CGFloat?, children: [Node]) {
        self.axis = axis
        self.crossAlignment = alignment
        self.spacing = spacing
        super.init(children: children)
    }

    convenience init(axis: Axis, alignment: Alignment, spacing: CGFloat?, children: [Node]) {
        self.init(axis: axis, alignment: axis == .horizontal ? alignment.vertical.key : alignment.horizontal.key,
                  spacing: spacing, children: children)
    }

    private func gap(_ a: Node, _ b: Node) -> CGFloat {
        if let spacing { return spacing }
        let (trailing, leading): (Edge, Edge) = axis == .horizontal ? (.trailing, .leading) : (.bottom, .top)
        let sa = a.spacing(trailing), sb = b.spacing(leading)
        if sa == 0 || sb == 0 { return 0 }
        if textToTextSpacing, axis == .vertical, sa == nil, sb == nil, a.textLeading(.bottom) != nil,
           let leading = b.textLeading(.top) {
            return leading
        }
        return max(sa ?? defaultStackSpacing, sb ?? defaultStackSpacing)
    }

    func compute(_ proposal: ProposedViewSize) -> Result {
        if let cached = results[proposal] { return cached }
        var r = Result()
        let n = children.count
        guard n > 0 else { return r }
        let cross = proposal[axis.cross]
        var gaps = [CGFloat](repeating: 0, count: n)
        for i in 0..<(n - 1) { gaps[i] = gap(children[i], children[i + 1]) }
        let totalGaps = gaps.reduce(0, +)
        r.sizes = [CGSize](repeating: .zero, count: n)

        func fit(_ i: Int, _ main: CGFloat?) -> CGSize {
            children[i].sizeThatFits(ProposedViewSize(axis: axis, main: main, cross: cross))
        }

        if let main = proposal[axis] {
            var remaining = main - totalGaps
            let priorities = Set(children.map(\.layoutPriority)).sorted(by: >)
            let minima: [CGFloat] = priorities.count > 1 ? (0..<n).map { fit($0, 0)[axis] } : []
            for priority in priorities {
                let group = (0..<n).filter { children[$0].layoutPriority == priority }
                let lowerMin = priorities.count > 1
                    ? (0..<n).filter { children[$0].layoutPriority < priority }.reduce(0) { $0 + minima[$1] } : 0
                var available = remaining - lowerMin
                let flexibility = group.map { i -> CGFloat in
                    let lo = fit(i, 0)[axis], hi = fit(i, .infinity)[axis]
                    return hi - lo
                }
                let order = group.indices.sorted { (flexibility[$0], $0) < (flexibility[$1], $1) }
                var left = group.count
                for k in order {
                    let i = group[k]
                    let share = max(0, available / CGFloat(left))
                    r.sizes[i] = fit(i, share)
                    available -= r.sizes[i][axis]
                    left -= 1
                }
                remaining = available + lowerMin
            }
        } else {
            for i in 0..<n { r.sizes[i] = fit(i, nil) }
        }

        var above: CGFloat = 0, below: CGFloat = 0
        var guides = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let crossSize = r.sizes[i][axis.cross]
            guard crossSize.isFinite else { guides[i] = 0; above = max(above, 0); below = max(below, crossSize); continue }
            guides[i] = children[i].alignmentValue(crossAlignment, size: r.sizes[i])
            above = max(above, guides[i])
            below = max(below, crossSize - guides[i])
        }
        r.alignedLine = above
        r.crossOffsets = guides.map { above - $0 }
        var cursor: CGFloat = 0
        r.mainOffsets = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            r.mainOffsets[i] = cursor
            cursor += r.sizes[i][axis] + gaps[i]
        }
        r.size = CGSize(axis: axis, main: cursor, cross: above + below)
        results[proposal] = r
        return r
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { compute(proposal).size }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        var p = proposal(forSize: size)
        // A stack wider than it was offered (a rigid child overflowing it) places its children
        // across its real width, as SwiftUI does: the other children then stretch to it too
        // (measured: iOS 27.0 simulator, 09_MusicPlayer: a 402pt transport row widens the sliders).
        if let offered = p[axis.cross], size[axis.cross] > offered + 0.01 {
            p = ProposedViewSize(axis: axis, main: p[axis], cross: size[axis.cross])
        }
        let r = compute(p)
        // If the stack was given more cross-axis room than it needs, keep children aligned within it.
        for (i, child) in children.enumerated() {
            child.place(at: CGPoint(axis: axis, main: r.mainOffsets[i], cross: r.crossOffsets[i]), size: r.sizes[i], ctx)
        }
    }

    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        let r = compute(proposal(forSize: size))
        guard !children.isEmpty else { return nil }
        if key.axis == axis.cross {
            if key == crossAlignment {
                let anyExplicit = children.indices.contains { children[$0].explicitAlignment(key, size: r.sizes[$0]) != nil }
                return anyExplicit ? r.alignedLine : nil
            }
            for i in children.indices {
                if let v = children[i].explicitAlignment(key, size: r.sizes[i]) { return r.crossOffsets[i] + v }
            }
            return nil
        }
        let indices = ObjectIdentifier(key.id) == ObjectIdentifier(VerticalAlignment.LastTextBaseline.self)
            ? Array(children.indices.reversed()) : Array(children.indices)
        for i in indices {
            if let v = children[i].explicitAlignment(key, size: r.sizes[i]) { return r.mainOffsets[i] + v }
        }
        return nil
    }
}

final class ZStackNode: Node {
    let alignment: Alignment
    init(alignment: Alignment, children: [Node]) {
        self.alignment = alignment
        super.init(children: children)
    }

    private func arrange(_ proposal: ProposedViewSize) -> (sizes: [CGSize], offsets: [CGPoint], size: CGSize) {
        let sizes = children.map { $0.sizeThatFits(proposal) }
        var left: CGFloat = 0, right: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0
        var guides: [CGPoint] = []
        for (child, size) in zip(children, sizes) {
            let gx = size.width.isFinite ? child.alignmentValue(alignment.horizontal.key, size: size) : 0
            let gy = size.height.isFinite ? child.alignmentValue(alignment.vertical.key, size: size) : 0
            guides.append(CGPoint(x: gx, y: gy))
            left = max(left, gx); right = max(right, size.width - gx)
            top = max(top, gy); bottom = max(bottom, size.height - gy)
        }
        return (sizes, guides.map { CGPoint(x: left - $0.x, y: top - $0.y) }, CGSize(width: left + right, height: top + bottom))
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { arrange(proposal).size }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let a = arrange(proposal(forSize: size))
        // Center the arrangement's own bounds in the space we were actually given.
        let dx = (size.width - a.size.width) * (alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5)
        let dy = (size.height - a.size.height) * (alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5)
        for (i, child) in children.enumerated() {
            child.place(at: CGPoint(x: a.offsets[i].x + dx, y: a.offsets[i].y + dy), size: a.sizes[i], ctx)
        }
    }

    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        let a = arrange(proposal(forSize: size))
        for i in children.indices {
            if let v = children[i].explicitAlignment(key, size: a.sizes[i]) {
                return (key.axis == .horizontal ? a.offsets[i].x : a.offsets[i].y) + v
            }
        }
        return nil
    }
}

// MARK: - Public stack views

/// The axis of the nearest enclosing stack; Spacer and Divider orient themselves by it.
enum StackAxisKey: EnvironmentKey { static let defaultValue: Axis? = nil }
extension EnvironmentValues {
    var stackAxis: Axis? {
        get { self[StackAxisKey.self] }
        set { self[StackAxisKey.self] = newValue }
    }
}

public struct HStack<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = .horizontal })
        out.append(StackNode(axis: .horizontal, alignment: alignment.key, spacing: spacing, children: children))
    }
}

public struct VStack<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = .vertical })
        let node = StackNode(axis: .vertical, alignment: alignment.key, spacing: spacing, children: children)
        node.textToTextSpacing = ctx.env.renderPlatform == .iOS
        out.append(node)
    }
}

public struct ZStack<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: Alignment
    let content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = nil })
        out.append(ZStackNode(alignment: alignment, children: children))
    }
}

// MARK: - Spacer

final class SpacerNode: Node {
    let axis: Axis?
    let minLength: CGFloat
    init(axis: Axis?, minLength: CGFloat) {
        self.axis = axis
        self.minLength = minLength
        super.init()
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let w = max(minLength, proposal.width ?? minLength), h = max(minLength, proposal.height ?? minLength)
        switch axis {
        case .horizontal: return CGSize(width: w, height: 0)
        case .vertical: return CGSize(width: 0, height: h)
        case nil: return CGSize(width: w, height: h)
        }
    }
    override func spacing(_ edge: Edge) -> CGFloat? { 0 }
    /// A spacer only gets what its siblings leave over.
    override var layoutPriority: Double { traits[LayoutPriorityTraitKey.self] ?? -.infinity }
}

public struct Spacer: View, PrimitiveView {
    public typealias Body = Never
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) { self.minLength = minLength }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        out.append(SpacerNode(axis: ctx.env.stackAxis, minLength: minLength ?? defaultStackSpacing))
    }
}
