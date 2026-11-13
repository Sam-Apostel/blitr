// LazyVStack / LazyHStack and the LazyVGrid / LazyHGrid family. Everything is laid out eagerly (a screenshot
// is one frame), with the same geometry SwiftUI produces.

public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

// MARK: - Lazy stacks

/// A stack that, unlike VStack/HStack, fills the proposed size on its cross axis.
final class LazyStackNode: WrapperNode {
    let axis: Axis
    let alignment: Alignment

    init(stack: StackNode, alignment: Alignment) {
        self.axis = stack.axis
        self.alignment = alignment
        super.init(child: stack)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        var size = child.sizeThatFits(proposal)
        if let cross = proposal[axis.cross], cross.isFinite { size[axis.cross] = cross }
        return size
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        // The stack's own cross size is what its content needs; align it inside the room we were given.
        let c = child.sizeThatFits(ProposedViewSize(size))
        placeAligned(child, childSize: c, in: size, alignment: alignment, ctx)
    }

    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        alignmentThroughFrame(key, size: size, alignment: alignment)
    }
}

public struct LazyVStack<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = .vertical })
        let stack = StackNode(axis: .vertical, alignment: alignment.key, spacing: spacing, children: children)
        out.append(LazyStackNode(stack: stack, alignment: Alignment(horizontal: alignment, vertical: .top)))
    }
}

public struct LazyHStack<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = .horizontal })
        let stack = StackNode(axis: .horizontal, alignment: alignment.key, spacing: spacing, children: children)
        out.append(LazyStackNode(stack: stack, alignment: Alignment(horizontal: .leading, vertical: alignment)))
    }
}

// MARK: - GridItem

public struct GridItem: Sendable {
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

// MARK: - Lazy grids

/// One resolved track (column of a vertical grid, row of a horizontal one).
struct GridTrack {
    var size: CGFloat
    var spacingAfter: CGFloat
    var alignment: Alignment?
}

final class LazyGridNode: Node {
    /// The axis along which items flow and tracks are stacked: `.vertical` for LazyVGrid (rows go down).
    let axis: Axis
    let items: [GridItem]
    let lineSpacing: CGFloat
    let alignment: Alignment

    private struct Result {
        var tracks: [GridTrack] = []
        var trackOffsets: [CGFloat] = []
        var lineSizes: [CGFloat] = []
        var lineOffsets: [CGFloat] = []
        var size: CGSize = .zero
        var trackExtent: CGFloat = 0
    }
    private var cache: [ProposedViewSize: Result] = [:]

    init(axis: Axis, items: [GridItem], lineSpacing: CGFloat?, alignment: Alignment, children: [Node]) {
        self.axis = axis
        self.items = items
        self.lineSpacing = lineSpacing ?? defaultStackSpacing
        self.alignment = alignment
        super.init(children: children)
    }

    /// The track axis is the cross axis of the flow: columns lie along `.horizontal` for LazyVGrid.
    private var trackAxis: Axis { axis.cross }

    private func resolveTracks(available: CGFloat?) -> [GridTrack] {
        // Expand adaptive items, then distribute `available` over the flexible ones.
        struct Spec { var min: CGFloat; var max: CGFloat; var spacing: CGFloat; var alignment: Alignment? }
        var specs: [Spec] = []
        let fixedTotal = items.reduce(CGFloat(0)) { if case .fixed(let v) = $1.size { return $0 + v } else { return $0 } }
        let minTotal = items.reduce(CGFloat(0)) { acc, item in
            switch item.size {
            case .fixed: return acc
            case .flexible(let lo, _): return acc + lo
            case .adaptive(let lo, _): return acc + lo
            }
        }
        for item in items {
            let spacing = item.spacing ?? defaultStackSpacing
            switch item.size {
            case .fixed(let v): specs.append(Spec(min: v, max: v, spacing: spacing, alignment: item.alignment))
            case .flexible(let lo, let hi): specs.append(Spec(min: lo, max: hi, spacing: spacing, alignment: item.alignment))
            case .adaptive(let lo, let hi):
                var n = 1
                if let available {
                    // Room left once everything else has its minimum, shared out in one adaptive group.
                    let others = specs.count + items.count - 1
                    let room = available - fixedTotal - (minTotal - lo) - CGFloat(max(0, others)) * spacing
                    n = max(1, Int(((room + spacing) / (lo + spacing)).rounded(.down)))
                }
                for _ in 0..<n { specs.append(Spec(min: lo, max: hi, spacing: spacing, alignment: item.alignment)) }
            }
        }
        let totalSpacing = specs.dropLast().reduce(CGFloat(0)) { $0 + $1.spacing }
        var sizes = specs.map(\.min)
        if let available {
            // Water-filling: flexible tracks share what is left equally, up to their maximum.
            var remaining = available - totalSpacing - specs.reduce(0) { $0 + ($1.min == $1.max ? $1.min : 0) }
            var open = specs.indices.filter { specs[$0].min != specs[$0].max }
            for i in open { sizes[i] = specs[i].min }
            remaining -= open.reduce(0) { $0 + specs[$1].min }
            while remaining > 0.001, !open.isEmpty {
                let share = remaining / CGFloat(open.count)
                var progressed = false
                for i in open {
                    let grow = min(share, specs[i].max - sizes[i])
                    if grow > 0 { sizes[i] += grow; remaining -= grow; progressed = true }
                }
                open.removeAll { specs[$0].max - sizes[$0] <= 0.001 }
                if !progressed { break }
            }
        }
        return specs.enumerated().map { GridTrack(size: sizes[$0.offset], spacingAfter: $0.element.spacing, alignment: $0.element.alignment) }
    }

    private func compute(_ proposal: ProposedViewSize) -> Result {
        if let cached = cache[proposal] { return cached }
        var l = Result()
        let available = proposal[trackAxis].flatMap { $0.isFinite ? $0 : nil }
        l.tracks = resolveTracks(available: available)
        let n = max(1, l.tracks.count)
        var cursor: CGFloat = 0
        for (i, t) in l.tracks.enumerated() {
            l.trackOffsets.append(cursor)
            cursor += t.size + (i < n - 1 ? t.spacingAfter : 0)
        }
        l.trackExtent = cursor
        let hasFlexible = items.contains { if case .fixed = $0.size { return false } else { return true } }
        let crossSize = hasFlexible ? (available ?? cursor) : cursor
        // Lines: consecutive groups of `n` items.
        var lineSizes: [CGFloat] = []
        var index = 0
        while index < children.count {
            var lineMain: CGFloat = 0
            for t in 0..<n where index + t < children.count {
                let track = l.tracks[t]
                let p = ProposedViewSize(axis: trackAxis, main: track.size, cross: nil)
                lineMain = max(lineMain, children[index + t].sizeThatFits(p)[axis])
            }
            lineSizes.append(lineMain)
            index += n
        }
        cursor = 0
        for (i, s) in lineSizes.enumerated() {
            l.lineOffsets.append(cursor)
            cursor += s + (i < lineSizes.count - 1 ? lineSpacing : 0)
        }
        l.lineSizes = lineSizes
        l.size = CGSize(axis: axis, main: cursor, cross: crossSize)
        cache[proposal] = l
        return l
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { compute(proposal).size }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let l = compute(ProposedViewSize(size))
        let n = max(1, l.tracks.count)
        // The tracks sit at the start of the cross extent, shifted by the grid's alignment if there is spare room.
        let spare = size[trackAxis] - l.trackExtent
        let shiftFactor: CGFloat
        if trackAxis == .horizontal {
            shiftFactor = alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5
        } else {
            shiftFactor = alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5
        }
        let shift = max(0, spare) * shiftFactor
        for (i, child) in children.enumerated() {
            let line = i / n, t = i % n
            guard line < l.lineSizes.count else { break }
            let track = l.tracks[t]
            let proposal = ProposedViewSize(axis: trackAxis, main: track.size, cross: nil)
            let childSize = child.sizeThatFits(proposal)
            // Position inside the cell (track x line) by the item's alignment, falling back to the grid's.
            let cellAlignment = track.alignment ?? alignment
            let cell = CGSize(axis: trackAxis, main: track.size, cross: l.lineSizes[line])
            let dims = ViewDimensions(node: nil, size: cell)
            let ax = cellAlignment.horizontal.key.id.defaultValue(in: dims) - child.alignmentValue(cellAlignment.horizontal.key, size: childSize)
            let ay = cellAlignment.vertical.key.id.defaultValue(in: dims) - child.alignmentValue(cellAlignment.vertical.key, size: childSize)
            let origin = CGPoint(axis: trackAxis, main: l.trackOffsets[t] + shift, cross: l.lineOffsets[line])
            child.place(at: CGPoint(x: origin.x + ax, y: origin.y + ay), size: childSize, ctx)
        }
    }
}

public struct LazyVGrid<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = nil })
        out.append(LazyGridNode(axis: .vertical, items: columns.isEmpty ? [GridItem()] : columns, lineSpacing: spacing,
                                alignment: Alignment(horizontal: alignment, vertical: .center), children: children))
    }
}

public struct LazyHGrid<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let rows: [GridItem]
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = nil })
        out.append(LazyGridNode(axis: .horizontal, items: rows.isEmpty ? [GridItem()] : rows, lineSpacing: spacing,
                                alignment: Alignment(horizontal: .center, vertical: alignment), children: children))
    }
}
