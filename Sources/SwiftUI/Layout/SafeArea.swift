// Safe-area handling and GeometryReader.
//
// Model: views are laid out inside `PlaceContext.safeRect`. `container` is the outer rect that
// content may bleed into (under bars, the status bar, the home indicator) when it ignores the safe area.

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = SafeAreaRegions(rawValue: 1)
    public static let keyboard = SafeAreaRegions(rawValue: 2)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

final class IgnoresSafeAreaNode: WrapperNode {
    let edges: Edge.Set
    init(child: Node, edges: Edge.Set) {
        self.edges = edges
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let bleed = ctx.safeAreaBleed(for: CGRect(origin: ctx.origin, size: size), edges: edges)
        let expanded = CGRect(origin: .zero, size: size).outset(by: bleed)
        var inner = ctx
        // The edges we extended over are no longer "unsafe" for our content.
        let absolute = CGRect(x: ctx.origin.x + expanded.minX, y: ctx.origin.y + expanded.minY, width: expanded.width, height: expanded.height)
        inner.safeRect = inner.safeRect.union(absolute).intersection(inner.container)
        let childSize = child.sizeThatFits(ProposedViewSize(expanded.size))
        child.place(at: CGPoint(x: expanded.midX - childSize.width / 2, y: expanded.midY - childSize.height / 2), size: childSize, inner)
    }
}

struct IgnoresSafeAreaModifier: ViewModifier, NodeModifier {
    let edges: Edge.Set
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { IgnoresSafeAreaNode(child: child, edges: edges) }
}

/// Reserves room for `inset` on one edge and treats that room as safe area for `content`.
final class SafeAreaInsetNode: Node {
    let edge: Edge
    let spacing: CGFloat
    let alignment: Alignment
    var content: Node { children[0] }
    var inset: Node { children[1] }

    init(content: Node, inset: Node, edge: Edge, spacing: CGFloat, alignment: Alignment) {
        self.edge = edge
        self.spacing = spacing
        self.alignment = alignment
        super.init(children: [content, inset])
        traits = content.traits
    }

    private var isVertical: Bool { edge == .top || edge == .bottom }

    private func insetSize(_ proposal: ProposedViewSize) -> CGSize {
        inset.sizeThatFits(isVertical ? ProposedViewSize(width: proposal.width, height: nil) : ProposedViewSize(width: nil, height: proposal.height))
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let i = insetSize(proposal)
        let reserved = (isVertical ? i.height : i.width) + spacing
        if isVertical {
            let c = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height.map { max(0, $0 - reserved) }))
            return CGSize(width: max(c.width, proposal.width == nil ? i.width : 0), height: c.height + reserved)
        }
        let c = content.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - reserved) }, height: proposal.height))
        return CGSize(width: c.width + reserved, height: max(c.height, proposal.height == nil ? i.height : 0))
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let i = insetSize(proposal(forSize: size))
        let reserved = (isVertical ? i.height : i.width) + spacing
        var contentRect = CGRect(origin: .zero, size: size)
        var insetOrigin = CGPoint.zero
        switch edge {
        case .top:
            contentRect.origin.y += reserved; contentRect.size.height -= reserved
            insetOrigin = CGPoint(x: (size.width - i.width) * xFactor, y: 0)
        case .bottom:
            contentRect.size.height -= reserved
            insetOrigin = CGPoint(x: (size.width - i.width) * xFactor, y: size.height - i.height)
        case .leading:
            contentRect.origin.x += reserved; contentRect.size.width -= reserved
            insetOrigin = CGPoint(x: 0, y: (size.height - i.height) * yFactor)
        case .trailing:
            contentRect.size.width -= reserved
            insetOrigin = CGPoint(x: size.width - i.width, y: (size.height - i.height) * yFactor)
        }
        contentRect.size.width = max(0, contentRect.width); contentRect.size.height = max(0, contentRect.height)
        // Content may bleed under the inset view (and wherever we could already bleed).
        var inner = ctx
        let own = CGRect(origin: ctx.origin, size: size)
        inner.container = own.outset(by: ctx.safeAreaBleed(for: own, edges: .all))
        inner.safeRect = CGRect(x: ctx.origin.x + contentRect.minX, y: ctx.origin.y + contentRect.minY,
                                width: contentRect.width, height: contentRect.height).intersection(ctx.safeRect)
        content.place(at: contentRect.origin, size: contentRect.size, inner)
        inset.place(at: insetOrigin, size: i, ctx)
    }

    private var xFactor: CGFloat { alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5 }
    private var yFactor: CGFloat { alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5 }
}

/// `safeAreaPadding`: insets added to the safe area. Content is laid out inside them as with `padding`, but the
/// insets are safe area, not the view's edge: a child that ignores the safe area extends back over them (a
/// page that keeps its text clear of a side column while its photo runs under it).
final class SafeAreaPaddingNode: WrapperNode {
    let insets: EdgeInsets
    init(child: Node, insets: EdgeInsets) {
        self.insets = insets
        super.init(child: child)
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let h = insets.leading + insets.trailing, v = insets.top + insets.bottom
        let c = child.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - h) }, height: proposal.height.map { max(0, $0 - v) }))
        return CGSize(width: c.width + h, height: c.height + v)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let rect = CGRect(x: insets.leading, y: insets.top, width: max(0, size.width - insets.leading - insets.trailing),
                          height: max(0, size.height - insets.top - insets.bottom))
        var inner = ctx
        let own = CGRect(origin: ctx.origin, size: size)
        // Content may bleed over the padding, and on past it wherever this view could already bleed.
        inner.container = own.outset(by: ctx.safeAreaBleed(for: own, edges: .all))
        // Where the view is under the screen's safe area, that still applies; content scrolled away from it
        // (a pager's other pages) has only its own.
        let padded = rect.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
        let limited = padded.intersection(ctx.safeRect)
        inner.safeRect = limited.isNull || limited.isEmpty ? padded : limited
        child.place(at: rect.origin, size: rect.size, inner)
    }
}

struct SafeAreaPaddingModifier: ViewModifier, NodeModifier {
    let insets: EdgeInsets
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { SafeAreaPaddingNode(child: child, insets: insets) }
}

struct SafeAreaInsetModifier<Inset: View>: ViewModifier, PrimitiveModifier {
    let edge: Edge
    let alignment: Alignment
    let spacing: CGFloat?
    let inset: Inset
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, node) in content.nodes(ctx).enumerated() {
            let insetNode = resolveSingle(inset, ctx.child("safeAreaInset\(i)").with { $0.stackAxis = nil })
            out.append(SafeAreaInsetNode(content: node, inset: insetNode, edge: edge, spacing: spacing ?? 0, alignment: alignment))
        }
    }
}

extension View {
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View {
        modifier(IgnoresSafeAreaModifier(edges: regions.contains(.container) ? edges : []))
    }
    public func edgesIgnoringSafeArea(_ edges: Edge.Set) -> some View { modifier(IgnoresSafeAreaModifier(edges: edges)) }

    public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                       @ViewBuilder content: () -> V) -> some View {
        modifier(SafeAreaInsetModifier(edge: edge == .top ? .top : .bottom, alignment: Alignment(horizontal: alignment, vertical: .center),
                                       spacing: spacing, inset: content()))
    }
    public func safeAreaInset<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                                       @ViewBuilder content: () -> V) -> some View {
        modifier(SafeAreaInsetModifier(edge: edge == .leading ? .leading : .trailing, alignment: Alignment(horizontal: .center, vertical: alignment),
                                       spacing: spacing, inset: content()))
    }
    public func safeAreaPadding(_ insets: EdgeInsets) -> some View { modifier(SafeAreaPaddingModifier(insets: insets)) }
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        modifier(SafeAreaPaddingModifier(insets: EdgeInsets(edges, length ?? defaultPadding)))
    }
    public func safeAreaPadding(_ length: CGFloat) -> some View { modifier(SafeAreaPaddingModifier(insets: EdgeInsets(all: length))) }
}

// MARK: - GeometryReader

public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public enum CoordinateSpace: Hashable, @unchecked Sendable {
    case global
    case local
    case named(AnyHashable)
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .global }
}
public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .local }
}
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    let name: AnyHashable
    public var coordinateSpace: CoordinateSpace { .named(name) }
}
extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace { public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() } }
extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace { public static var local: LocalCoordinateSpace { LocalCoordinateSpace() } }
extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace { NamedCoordinateSpace(name: AnyHashable(name)) }
    public static var scrollView: NamedCoordinateSpace { NamedCoordinateSpace(name: AnyHashable("_scrollView")) }
    public static func scrollView(axis: Axis) -> NamedCoordinateSpace { NamedCoordinateSpace(name: AnyHashable("_scrollView")) }
}

public struct GeometryProxy {
    public let size: CGSize
    public let safeAreaInsets: EdgeInsets
    let absoluteOrigin: CGPoint
    let namedSpaces: [AnyHashable: CGPoint]

    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        switch coordinateSpace {
        case .local: return CGRect(origin: .zero, size: size)
        case .global: return CGRect(origin: absoluteOrigin, size: size)
        case .named(let name):
            let origin = namedSpaces[name] ?? .zero
            return CGRect(x: absoluteOrigin.x - origin.x, y: absoluteOrigin.y - origin.y, width: size.width, height: size.height)
        }
    }
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect { frame(in: coordinateSpace.coordinateSpace) }
    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? { nil }
    /// An anchor is resolved against the rect its view occupied (absolute), expressed in this proxy's space.
    public subscript<T>(anchor: Anchor<T>) -> T {
        anchor.source.make(anchor.rect.offsetBy(dx: -absoluteOrigin.x, dy: -absoluteOrigin.y))
    }
}

public struct Anchor<Value> {
    /// Absolute rect of the anchored view (filled in by `anchorPreference`; `.zero` until its first layout).
    let rect: CGRect
    let source: Source
    var value: Value { source.make(rect) }
    public struct Source {
        let make: (CGRect) -> Value
    }
}
extension Anchor.Source where Value == CGRect {
    public static var bounds: Anchor<CGRect>.Source { .init { $0 } }
    public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source { .init { r.offsetBy(dx: $0.minX, dy: $0.minY) } }
}
extension Anchor.Source where Value == CGPoint {
    public static var center: Anchor<CGPoint>.Source { .init { $0.center } }
    public static var top: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.midX, y: $0.minY) } }
    public static var bottom: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.midX, y: $0.maxY) } }
    public static var leading: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.minX, y: $0.midY) } }
    public static var trailing: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.maxX, y: $0.midY) } }
    public static var topLeading: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.minX, y: $0.minY) } }
    public static var topTrailing: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.maxX, y: $0.minY) } }
    public static var bottomLeading: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.minX, y: $0.maxY) } }
    public static var bottomTrailing: Anchor<CGPoint>.Source { .init { CGPoint(x: $0.maxX, y: $0.maxY) } }
    public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source { .init { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) } }
}

final class GeometryNode: Node {
    let build: (GeometryProxy, ResolveContext) -> [Node]
    let ctx: ResolveContext
    init(ctx: ResolveContext, build: @escaping (GeometryProxy, ResolveContext) -> [Node]) {
        self.ctx = ctx
        self.build = build
        super.init()
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    override func layout(size: CGSize, _ place: PlaceContext) {
        let own = CGRect(origin: place.origin, size: size)
        let bleed = place.safeAreaBleed(for: own, edges: .all)
        let proxy = GeometryProxy(size: size, safeAreaInsets: bleed, absoluteOrigin: place.origin,
                                  namedSpaces: ctx.runtime.namedCoordinateSpaces)
        children = build(proxy, ctx)
        for child in children {
            let s = child.sizeThatFits(ProposedViewSize(size))
            child.place(at: .zero, size: s, place)
        }
    }
}

public struct GeometryReader<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public var content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let content = self.content
        out.append(GeometryNode(ctx: ctx.with { $0.stackAxis = nil }) { proxy, ctx in
            resolveNodes(content(proxy), ctx.child("geometry"))
        })
    }
}

final class CoordinateSpaceNode: WrapperNode {
    let name: AnyHashable
    let runtime: Runtime
    init(child: Node, name: AnyHashable, runtime: Runtime) {
        self.name = name
        self.runtime = runtime
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        runtime.namedCoordinateSpaces[name] = ctx.origin
        super.layout(size: size, ctx)
    }
}

struct CoordinateSpaceModifier: ViewModifier, NodeModifier {
    let name: AnyHashable
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { CoordinateSpaceNode(child: child, name: name, runtime: ctx.runtime) }
}

extension View {
    public func coordinateSpace<T: Hashable>(name: T) -> some View { modifier(CoordinateSpaceModifier(name: AnyHashable(name))) }
    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View { modifier(CoordinateSpaceModifier(name: name.name)) }
}
