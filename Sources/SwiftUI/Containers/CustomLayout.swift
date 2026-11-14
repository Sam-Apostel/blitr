// The public `Layout` protocol: custom containers that measure and place their subviews.

// MARK: - LayoutValueKey

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

enum LayoutValueTrait<K: LayoutValueKey>: TraitKey { typealias Value = K.Value }

extension View {
    public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        trait(LayoutValueTrait<K>.self, value)
    }
}

// MARK: - ViewSpacing

public struct ViewSpacing: Sendable {
    /// top, leading, bottom, trailing; `nil` means "the system default".
    var edges: [CGFloat?]
    public init() { edges = [nil, nil, nil, nil] }
    init(edges: [CGFloat?]) { self.edges = edges }
    public static let zero = ViewSpacing(edges: [0, 0, 0, 0])

    func value(for edge: Edge) -> CGFloat? { edges[Int(edge.rawValue)] }

    public mutating func formUnion(_ other: ViewSpacing, edges set: Edge.Set = .all) {
        for edge in Edge.allCases where set.contains(Edge.Set(edge)) {
            let i = Int(edge.rawValue)
            switch (edges[i], other.edges[i]) {
            case (nil, nil): break
            case (let a, let b): edges[i] = max(a ?? defaultStackSpacing, b ?? defaultStackSpacing)
            }
        }
    }
    public func union(_ other: ViewSpacing, edges set: Edge.Set = .all) -> ViewSpacing {
        var copy = self
        copy.formUnion(other, edges: set)
        return copy
    }
    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        let (a, b) = axis == .horizontal ? (value(for: .trailing), next.value(for: .leading)) : (value(for: .bottom), next.value(for: .top))
        if a == 0 || b == 0 { return 0 }
        return max(a ?? defaultStackSpacing, b ?? defaultStackSpacing)
    }
}

// MARK: - Subviews

@MainActor
final class SubviewSlot {
    let node: Node
    var placement: (position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize)?
    /// Placed by a built-in layout directly (HStackLayout & co.), not through `place(at:)`.
    var placedNatively = false
    init(node: Node) { self.node = node }
}

public struct LayoutSubview: Equatable, @unchecked Sendable {
    let slot: SubviewSlot

    public static func == (l: LayoutSubview, r: LayoutSubview) -> Bool { l.slot === r.slot }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        MainActor.assumeIsolated { slot.node.sizeThatFits(proposal) }
    }
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        MainActor.assumeIsolated { ViewDimensions(node: slot.node, size: slot.node.sizeThatFits(proposal)) }
    }
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        MainActor.assumeIsolated { slot.placement = (position, anchor, proposal) }
    }
    public var priority: Double { MainActor.assumeIsolated { slot.node.layoutPriority } }
    public var spacing: ViewSpacing {
        MainActor.assumeIsolated {
            ViewSpacing(edges: Edge.allCases.map { slot.node.spacing($0) })
        }
    }
    public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        MainActor.assumeIsolated { slot.node.traits[LayoutValueTrait<K>.self] ?? K.defaultValue }
    }
    var node: Node { MainActor.assumeIsolated { slot.node } }
}

public struct LayoutSubviews: Equatable, RandomAccessCollection, @unchecked Sendable {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias SubSequence = LayoutSubviews
    public typealias Indices = Range<Int>
    let all: [LayoutSubview]
    let range: Range<Int>

    init(_ subviews: [LayoutSubview]) { all = subviews; range = 0..<subviews.count }
    private init(all: [LayoutSubview], range: Range<Int>) { self.all = all; self.range = range }

    public var startIndex: Int { range.lowerBound }
    public var endIndex: Int { range.upperBound }
    public subscript(index: Int) -> LayoutSubview { all[index] }
    public subscript(bounds: Range<Int>) -> LayoutSubviews { LayoutSubviews(all: all, range: bounds) }
    public subscript<S: RangeExpression>(indices: S) -> LayoutSubviews where S.Bound == Int {
        LayoutSubviews(all: all, range: indices.relative(to: range))
    }
    public static func == (l: LayoutSubviews, r: LayoutSubviews) -> Bool { l.range == r.range && l.all == r.all }

    var nodes: [Node] { map(\.node) }
}

// MARK: - Layout

public struct LayoutProperties: Sendable {
    public var stackOrientation: Axis?
    public init() { stackOrientation = nil }
}

@MainActor @preconcurrency
public protocol Layout: Animatable {
    typealias Subviews = LayoutSubviews
    associatedtype Cache = Void

    static var layoutProperties: LayoutProperties { get }
    func makeCache(subviews: Subviews) -> Cache
    func updateCache(_ cache: inout Cache, subviews: Subviews)
    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat?
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat?
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}

extension Layout {
    public static var layoutProperties: LayoutProperties { LayoutProperties() }
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }
    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        var result = ViewSpacing()
        for s in subviews { result.formUnion(s.spacing) }
        return result
    }
    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        LayoutContainerView(layout: self, content: content())
    }
}
extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) -> Cache { () }
}

/// The placement context of the custom layout currently placing its subviews (for built-in layouts that place nodes directly).
@MainActor var currentLayoutPlaceContext: PlaceContext?

final class CustomLayoutNode<L: Layout>: Node {
    let layout: L
    var cache: L.Cache
    let subviews: LayoutSubviews

    init(layout: L, children: [Node]) {
        let subs = LayoutSubviews(children.map { LayoutSubview(slot: SubviewSlot(node: $0)) })
        self.layout = layout
        self.subviews = subs
        self.cache = layout.makeCache(subviews: subs)
        super.init(children: children)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let s = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        return CGSize(width: s.width.isFinite ? max(0, s.width) : 0, height: s.height.isFinite ? max(0, s.height) : 0)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        for s in subviews { s.slot.placement = nil; s.slot.placedNatively = false }
        let saved = currentLayoutPlaceContext
        currentLayoutPlaceContext = ctx
        // Bounds are expressed in the parent's coordinate space, as in SwiftUI.
        let bounds = CGRect(origin: frame.origin, size: size)
        layout.placeSubviews(in: bounds, proposal: proposal(forSize: size), subviews: subviews, cache: &cache)
        currentLayoutPlaceContext = saved
        for s in subviews {
            let slot = s.slot
            if slot.placedNatively { continue }
            if let p = slot.placement {
                var childSize = slot.node.sizeThatFits(p.proposal)
                if !childSize.width.isFinite { childSize.width = 0 }
                if !childSize.height.isFinite { childSize.height = 0 }
                let origin = CGPoint(x: p.position.x - p.anchor.x * childSize.width - frame.origin.x,
                                     y: p.position.y - p.anchor.y * childSize.height - frame.origin.y)
                slot.node.place(at: origin, size: childSize, ctx)
            } else {
                // Subviews a layout never placed sit centred in the container.
                let childSize = slot.node.sizeThatFits(.unspecified)
                slot.node.place(at: CGPoint(x: (size.width - childSize.width) / 2, y: (size.height - childSize.height) / 2),
                                size: childSize, ctx)
            }
        }
    }

    override func spacing(_ edge: Edge) -> CGFloat? {
        layout.spacing(subviews: subviews, cache: &cache).value(for: edge)
    }

    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        let bounds = CGRect(origin: .zero, size: size)
        if key.axis == .horizontal {
            return layout.explicitAlignment(of: HorizontalAlignment(key.id), in: bounds, proposal: proposal(forSize: size), subviews: subviews, cache: &cache)
        }
        return layout.explicitAlignment(of: VerticalAlignment(key.id), in: bounds, proposal: proposal(forSize: size), subviews: subviews, cache: &cache)
    }
}

struct LayoutContainerView<L: Layout, Content: View>: View, PrimitiveView {
    typealias Body = Never
    let layout: L
    let content: Content
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = L.layoutProperties.stackOrientation })
        out.append(CustomLayoutNode(layout: layout, children: children))
    }
}

// MARK: - AnyLayout

@MainActor
protocol AnyLayoutBox {
    func makeCache(subviews: LayoutSubviews) -> Any
    func spacing(subviews: LayoutSubviews, cache: inout Any) -> ViewSpacing
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Any) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Any)
    func explicitAlignment(horizontal: HorizontalAlignment?, vertical: VerticalAlignment?, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: LayoutSubviews, cache: inout Any) -> CGFloat?
}

@MainActor
final class LayoutBox<L: Layout>: AnyLayoutBox {
    let layout: L
    init(_ layout: L) { self.layout = layout }
    func makeCache(subviews: LayoutSubviews) -> Any { layout.makeCache(subviews: subviews) }
    private func with<R>(_ cache: inout Any, _ body: (inout L.Cache) -> R) -> R {
        var typed = cache as! L.Cache
        defer { cache = typed }
        return body(&typed)
    }
    func spacing(subviews: LayoutSubviews, cache: inout Any) -> ViewSpacing {
        with(&cache) { layout.spacing(subviews: subviews, cache: &$0) }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Any) -> CGSize {
        with(&cache) { layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &$0) }
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Any) {
        with(&cache) { layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &$0) }
    }
    func explicitAlignment(horizontal: HorizontalAlignment?, vertical: VerticalAlignment?, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: LayoutSubviews, cache: inout Any) -> CGFloat? {
        with(&cache) { c in
            if let horizontal { return layout.explicitAlignment(of: horizontal, in: bounds, proposal: proposal, subviews: subviews, cache: &c) }
            if let vertical { return layout.explicitAlignment(of: vertical, in: bounds, proposal: proposal, subviews: subviews, cache: &c) }
            return nil
        }
    }
}

public struct AnyLayout: Layout {
    public struct Cache { var value: Any }
    let box: AnyLayoutBox
    let properties: LayoutProperties
    public init<L: Layout>(_ layout: L) {
        box = LayoutBox(layout)
        properties = L.layoutProperties
    }
    public func makeCache(subviews: LayoutSubviews) -> Cache { Cache(value: box.makeCache(subviews: subviews)) }
    public func updateCache(_ cache: inout Cache, subviews: LayoutSubviews) {}
    public func spacing(subviews: LayoutSubviews, cache: inout Cache) -> ViewSpacing { box.spacing(subviews: subviews, cache: &cache.value) }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache) -> CGSize {
        box.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache.value)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache) {
        box.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache.value)
    }
    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: LayoutSubviews, cache: inout Cache) -> CGFloat? {
        box.explicitAlignment(horizontal: guide, vertical: nil, in: bounds, proposal: proposal, subviews: subviews, cache: &cache.value)
    }
    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: LayoutSubviews, cache: inout Cache) -> CGFloat? {
        box.explicitAlignment(horizontal: nil, vertical: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache.value)
    }
}

// MARK: - Built-in layouts

/// The built-in layouts delegate to the engine's own container nodes, wrapped around the subviews' nodes.
public struct NativeLayoutCache {
    var node: Node
}

@MainActor
private func nativeSize(_ cache: NativeLayoutCache, _ proposal: ProposedViewSize) -> CGSize { cache.node.sizeThatFits(proposal) }

@MainActor
private func nativePlace(_ cache: NativeLayoutCache, _ bounds: CGRect, _ subviews: LayoutSubviews) {
    guard let ctx = currentLayoutPlaceContext else { return }
    for s in subviews { s.slot.placedNatively = true }
    cache.node.layout(size: bounds.size, ctx)
}

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
    public static var layoutProperties: LayoutProperties { var p = LayoutProperties(); p.stackOrientation = .horizontal; return p }
    public func makeCache(subviews: LayoutSubviews) -> NativeLayoutCache {
        NativeLayoutCache(node: StackNode(axis: .horizontal, alignment: alignment.key, spacing: spacing, children: subviews.nodes))
    }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) -> CGSize { nativeSize(cache, proposal) }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) {
        nativePlace(cache, bounds, subviews)
    }
}

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
    public static var layoutProperties: LayoutProperties { var p = LayoutProperties(); p.stackOrientation = .vertical; return p }
    public func makeCache(subviews: LayoutSubviews) -> NativeLayoutCache {
        NativeLayoutCache(node: StackNode(axis: .vertical, alignment: alignment.key, spacing: spacing, children: subviews.nodes))
    }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) -> CGSize { nativeSize(cache, proposal) }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) {
        nativePlace(cache, bounds, subviews)
    }
}

public struct ZStackLayout: Layout {
    public var alignment: Alignment
    public init(alignment: Alignment = .center) { self.alignment = alignment }
    public func makeCache(subviews: LayoutSubviews) -> NativeLayoutCache {
        NativeLayoutCache(node: ZStackNode(alignment: alignment, children: subviews.nodes))
    }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) -> CGSize { nativeSize(cache, proposal) }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) {
        nativePlace(cache, bounds, subviews)
    }
}

public struct GridLayout: Layout {
    public var alignment: Alignment
    public var horizontalSpacing: CGFloat?
    public var verticalSpacing: CGFloat?
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
        self.alignment = alignment; self.horizontalSpacing = horizontalSpacing; self.verticalSpacing = verticalSpacing
    }
    public func makeCache(subviews: LayoutSubviews) -> NativeLayoutCache {
        NativeLayoutCache(node: GridNode(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing, children: subviews.nodes))
    }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) -> CGSize { nativeSize(cache, proposal) }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout NativeLayoutCache) {
        nativePlace(cache, bounds, subviews)
    }
}
