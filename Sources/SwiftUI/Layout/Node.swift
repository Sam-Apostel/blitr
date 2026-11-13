// The render tree. Each node measures itself for a proposed size, places its children,
// and draws. This mirrors SwiftUI's own layout protocol (propose -> size -> place).

struct PlaceContext {
    /// Absolute position of the coordinate space the node's `frame` is expressed in.
    var origin: CGPoint
    /// The full container (the screen) in absolute coordinates.
    var container: CGRect
    /// The part of the container not covered by bars / device insets, in absolute coordinates.
    var safeRect: CGRect
    /// Pixels per point; frames are snapped to this grid.
    var scale: CGFloat

    func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
}

@MainActor
class Node {
    final var children: [Node]
    /// Position and size in the parent's coordinate space (valid after `place`).
    final var frame: CGRect = .zero
    final var absoluteOrigin: CGPoint = .zero
    final var traits = Traits()
    final var preferences = PreferenceStore()
    private var sizeCache: [ProposedViewSize: CGSize] = [:]

    init(children: [Node] = []) {
        self.children = children
        for child in children { preferences.merge(child.preferences) }
    }

    // MARK: Layout

    final func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let cached = sizeCache[proposal] { return cached }
        var size = measure(proposal)
        if size.width.isNaN { size.width = 0 }
        if size.height.isNaN { size.height = 0 }
        sizeCache[proposal] = size
        return size
    }

    /// Override: the size this node wants for the proposal.
    func measure(_ proposal: ProposedViewSize) -> CGSize { .zero }

    /// Positions the node at `origin` (parent coordinates) with a final `size`.
    final func place(at origin: CGPoint, size: CGSize, _ ctx: PlaceContext) {
        let absolute = CGPoint(x: ctx.snap(ctx.origin.x + origin.x), y: ctx.snap(ctx.origin.y + origin.y))
        frame = CGRect(x: absolute.x - ctx.origin.x, y: absolute.y - ctx.origin.y, width: size.width, height: size.height)
        absoluteOrigin = absolute
        var childContext = ctx
        childContext.origin = absolute
        layout(size: size, childContext)
    }

    /// Override: place children inside `size`. `ctx.origin` is this node's absolute origin.
    func layout(size: CGSize, _ ctx: PlaceContext) {}

    var layoutPriority: Double { traits[LayoutPriorityTraitKey.self] ?? 0 }
    var zIndex: Double { traits[ZIndexTraitKey.self] ?? 0 }

    /// Preferred distance to a neighbour in a stack. `nil` means the system default.
    func spacing(_ edge: Edge) -> CGFloat? { nil }

    /// Override to provide an explicit alignment guide (text baselines, `.alignmentGuide`).
    func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? { nil }

    final func alignmentValue(_ key: AlignmentKey, size: CGSize) -> CGFloat {
        explicitAlignment(key, size: size) ?? key.id.defaultValue(in: ViewDimensions(node: self, size: size))
    }

    // MARK: Drawing

    func draw(_ p: Painter) {
        p.save()
        p.translate(frame.origin.x, frame.origin.y)
        drawContent(p)
        p.restore()
    }

    /// Override: draw in the node's own coordinate space. Default draws the children.
    func drawContent(_ p: Painter) { drawChildren(p) }

    final func drawChildren(_ p: Painter) {
        if children.contains(where: { $0.zIndex != 0 }) {
            let ordered = children.enumerated().sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
            for (_, child) in ordered { child.draw(p) }
        } else {
            for child in children { child.draw(p) }
        }
    }
}

/// A node with exactly one child that it sizes and positions identically to itself.
/// Most effect modifiers subclass this and only override `drawContent`.
class WrapperNode: Node {
    final var child: Node { children[0] }

    init(child: Node) {
        super.init(children: [child])
        traits = child.traits
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { child.sizeThatFits(proposal) }
    override func layout(size: CGSize, _ ctx: PlaceContext) { child.place(at: .zero, size: size, ctx) }
    override func spacing(_ edge: Edge) -> CGFloat? { child.spacing(edge) }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        child.explicitAlignment(key, size: size)
    }
}

// MARK: - Alignment

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}

struct AlignmentKey: Hashable {
    let id: AlignmentID.Type
    let axis: Axis
    static func == (l: AlignmentKey, r: AlignmentKey) -> Bool { ObjectIdentifier(l.id) == ObjectIdentifier(r.id) }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(id)) }
}

public struct ViewDimensions {
    let node: Node?
    let size: CGSize
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public subscript(guide: HorizontalAlignment) -> CGFloat {
        MainActor.assumeIsolated { node?.alignmentValue(guide.key, size: size) ?? guide.key.id.defaultValue(in: self) }
    }
    public subscript(guide: VerticalAlignment) -> CGFloat {
        MainActor.assumeIsolated { node?.alignmentValue(guide.key, size: size) ?? guide.key.id.defaultValue(in: self) }
    }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? {
        MainActor.assumeIsolated { node?.explicitAlignment(guide.key, size: size) }
    }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? {
        MainActor.assumeIsolated { node?.explicitAlignment(guide.key, size: size) }
    }
}

public struct HorizontalAlignment: Equatable, Sendable {
    let key: AlignmentKey
    public init(_ id: AlignmentID.Type) { key = AlignmentKey(id: id, axis: .horizontal) }
    public static func == (l: Self, r: Self) -> Bool { l.key == r.key }

    enum Leading: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 } }
    enum Center: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width / 2 } }
    enum Trailing: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width } }
    public static let leading = HorizontalAlignment(Leading.self)
    public static let center = HorizontalAlignment(Center.self)
    public static let trailing = HorizontalAlignment(Trailing.self)
    public static let listRowSeparatorLeading = HorizontalAlignment(Leading.self)
    public static let listRowSeparatorTrailing = HorizontalAlignment(Trailing.self)
}

public struct VerticalAlignment: Equatable, Sendable {
    let key: AlignmentKey
    public init(_ id: AlignmentID.Type) { key = AlignmentKey(id: id, axis: .vertical) }
    public static func == (l: Self, r: Self) -> Bool { l.key == r.key }

    enum Top: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 } }
    enum Center: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height / 2 } }
    enum Bottom: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height } }
    enum FirstTextBaseline: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height } }
    enum LastTextBaseline: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height } }
    public static let top = VerticalAlignment(Top.self)
    public static let center = VerticalAlignment(Center.self)
    public static let bottom = VerticalAlignment(Bottom.self)
    public static let firstTextBaseline = VerticalAlignment(FirstTextBaseline.self)
    public static let lastTextBaseline = VerticalAlignment(LastTextBaseline.self)
}

public struct Alignment: Equatable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
    public static let centerFirstTextBaseline = Alignment(horizontal: .center, vertical: .firstTextBaseline)
    public static let centerLastTextBaseline = Alignment(horizontal: .center, vertical: .lastTextBaseline)
    public static let leadingFirstTextBaseline = Alignment(horizontal: .leading, vertical: .firstTextBaseline)
    public static let leadingLastTextBaseline = Alignment(horizontal: .leading, vertical: .lastTextBaseline)
    public static let trailingFirstTextBaseline = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    public static let trailingLastTextBaseline = Alignment(horizontal: .trailing, vertical: .lastTextBaseline)
}

extension Node {
    /// Places `child` (already measured to `childSize`) inside `size` so the two share `alignment`.
    final func placeAligned(_ child: Node, childSize: CGSize, in size: CGSize, alignment: Alignment, _ ctx: PlaceContext) {
        let parent = ViewDimensions(node: nil, size: size)
        let x = alignment.horizontal.key.id.defaultValue(in: parent) - child.alignmentValue(alignment.horizontal.key, size: childSize)
        let y = alignment.vertical.key.id.defaultValue(in: parent) - child.alignmentValue(alignment.vertical.key, size: childSize)
        child.place(at: CGPoint(x: x, y: y), size: childSize, ctx)
    }
}
