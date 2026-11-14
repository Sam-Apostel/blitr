// ScrollView (rendered at scroll offset zero unless the focus engine scrolled it to show the focused
// element), ScrollViewReader, and the scroll-related modifiers.
// A screenshot is a single frame, so scrolling itself is inert: the content is laid out as it appears
// before the user touches it, and clipped to the scroll view (extended under bars and the home indicator).

// MARK: - Environment

enum ScrollClipDisabledKey: EnvironmentKey { static let defaultValue = false }
enum ScrollContentMarginsKey: EnvironmentKey { static let defaultValue = EdgeInsets() }
enum IsScrollEnabledKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var scrollClipDisabled: Bool {
        get { self[ScrollClipDisabledKey.self] }
        set { self[ScrollClipDisabledKey.self] = newValue }
    }
    /// Padding added around scroll content by `contentMargins`. Scrollable containers (ScrollView, List, Form)
    /// read and consume it.
    var scrollContentMargins: EdgeInsets {
        get { self[ScrollContentMarginsKey.self] }
        set { self[ScrollContentMarginsKey.self] = newValue }
    }
    public var isScrollEnabled: Bool {
        get { self[IsScrollEnabledKey.self] }
        set { self[IsScrollEnabledKey.self] = newValue }
    }
}

// MARK: - Node

final class ScrollNode: Node {
    let axes: Axis.Set
    let margins: EdgeInsets
    let clips: Bool
    var content: Node { children[0] }
    private(set) var clipRect = CGRect.zero
    /// Structural identity, so the focus engine can keep a scroll offset for this scroll view.
    var identity: IdentityPath?

    init(content: Node, axes: Axis.Set, margins: EdgeInsets, clips: Bool) {
        self.axes = axes
        self.margins = margins
        self.clips = clips
        super.init(children: [content])
    }

    private var scrollsH: Bool { axes.contains(.horizontal) }
    private var scrollsV: Bool { axes.contains(.vertical) }

    private func contentProposal(for size: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: scrollsH ? nil : size.width.flatMap { $0.isFinite ? max(0, $0 - margins.horizontal) : nil },
            height: scrollsV ? nil : size.height.flatMap { $0.isFinite ? max(0, $0 - margins.vertical) : nil })
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        // The scroll view is greedy; without a finite proposal the content decides.
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil }, h = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        let c = content.sizeThatFits(contentProposal(for: ProposedViewSize(width: w, height: h)))
        return CGSize(width: w ?? (c.width + margins.horizontal), height: h ?? (c.height + margins.vertical))
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = content.sizeThatFits(contentProposal(for: proposal(forSize: size)))
        let availW = size.width - margins.horizontal, availH = size.height - margins.vertical
        // Top (vertical) / leading (horizontal) on the scroll axis, centred across.
        let x = scrollsH ? margins.leading : margins.leading + (availW - c.width) / 2
        let y = scrollsV ? margins.top : margins.top + (availH - c.height) / 2
        // Scrolled by the focus engine (tvOS: the focused element is kept on screen); zero otherwise.
        let offset = identity.flatMap { Runtime.current?.focus.scrollOffsets[$0] } ?? .zero
        content.place(at: CGPoint(x: x - offset.x, y: y - offset.y), size: c, ctx)
        let bounds = CGRect(origin: .zero, size: size)
        clipRect = bounds.outset(by: ctx.safeAreaBleed(for: CGRect(origin: ctx.origin, size: size), edges: .all))
    }

    override func drawContent(_ p: Painter) {
        guard clips else { drawChildren(p); return }
        p.save()
        p.clip(clipRect)
        drawChildren(p)
        p.restore()
    }
}

// MARK: - Views

public struct ScrollView<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public var axes: Axis.Set
    public var showsIndicators: Bool
    public var content: Content

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    public init(_ axes: Axis.Set = .vertical, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = true
        self.content = content()
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let margins = ctx.env.scrollContentMargins
        let inner = ctx.with { $0.stackAxis = nil; $0.scrollContentMargins = EdgeInsets(); $0.scrollClipDisabled = false }
        let node = resolveSingle(content, inner.child("scrollContent"))
        let scroll = ScrollNode(content: node, axes: axes, margins: margins, clips: !ctx.env.scrollClipDisabled)
        scroll.identity = ctx.path
        out.append(scroll)
    }
}

/// Scrolls programmatically in an interactive app; inert in a still frame.
public struct ScrollViewProxy {
    init() {}
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {}
}

public struct ScrollViewReader<Content: View>: View {
    public var content: (ScrollViewProxy) -> Content
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }
    public var body: some View { content(ScrollViewProxy()) }
}

// MARK: - Supporting types

public struct ScrollIndicatorVisibility: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollIndicatorVisibility(raw: 0)
    public static let visible = ScrollIndicatorVisibility(raw: 1)
    public static let hidden = ScrollIndicatorVisibility(raw: 2)
    public static let never = ScrollIndicatorVisibility(raw: 3)
}

public struct ScrollBounceBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollBounceBehavior(raw: 0)
    public static let always = ScrollBounceBehavior(raw: 1)
    public static let basedOnSize = ScrollBounceBehavior(raw: 2)
}

public struct ScrollDismissesKeyboardMode: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollDismissesKeyboardMode(raw: 0)
    public static let immediately = ScrollDismissesKeyboardMode(raw: 1)
    public static let interactively = ScrollDismissesKeyboardMode(raw: 2)
    public static let never = ScrollDismissesKeyboardMode(raw: 3)
}

public struct ScrollInputKind: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollInputKind(raw: 0)
    public static let direct = ScrollInputKind(raw: 1)
    public static let pointer = ScrollInputKind(raw: 2)
}

public struct ScrollInputBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollInputBehavior(raw: 0)
    public static let enabled = ScrollInputBehavior(raw: 1)
    public static let disabled = ScrollInputBehavior(raw: 2)
}

public struct ScrollEdgeEffectStyle: Hashable, Sendable {
    let raw: Int
    public static let automatic = ScrollEdgeEffectStyle(raw: 0)
    public static let soft = ScrollEdgeEffectStyle(raw: 1)
    public static let hard = ScrollEdgeEffectStyle(raw: 2)
}

public struct ScrollPhase: Hashable, Sendable {
    let raw: Int
    public static let idle = ScrollPhase(raw: 0)
    public static let tracking = ScrollPhase(raw: 1)
    public static let interacting = ScrollPhase(raw: 2)
    public static let decelerating = ScrollPhase(raw: 3)
    public static let animating = ScrollPhase(raw: 4)
    public var isScrolling: Bool { self != .idle }
}

public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize
    public var bounds: CGRect { CGRect(origin: contentOffset, size: containerSize) }
    public var visibleRect: CGRect { bounds }
    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets, containerSize: CGSize) {
        self.contentOffset = contentOffset; self.contentSize = contentSize
        self.contentInsets = contentInsets; self.containerSize = containerSize
    }
}

public struct ScrollTargetBehaviorContext: Sendable {
    public var axes: Axis.Set
    public var originalTarget: ScrollTarget
    public var velocity: CGVector
    public var contentSize: CGSize
    public var containerSize: CGSize
}
public struct ScrollTarget: Sendable {
    public var rect: CGRect
    public var anchor: UnitPoint?
}

public protocol ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: ScrollTargetBehaviorContext)
}
extension ScrollTargetBehavior {
    public func updateTarget(_ target: inout ScrollTarget, context: ScrollTargetBehaviorContext) {}
}

public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    public struct LimitBehavior: Hashable, Sendable {
        let raw: Int
        public static let automatic = LimitBehavior(raw: 0)
        public static let always = LimitBehavior(raw: 1)
        public static let alwaysByFew = LimitBehavior(raw: 2)
        public static let alwaysByOne = LimitBehavior(raw: 3)
        public static let never = LimitBehavior(raw: 4)
    }
    public init(limitBehavior: LimitBehavior = .automatic) {}
}
public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {}
}
extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    public static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }
    public static func viewAligned(limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior) -> ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }
}
extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

public struct ScrollPosition: Equatable, Sendable {
    var id: AnyHashable?
    public private(set) var point: CGPoint?
    public private(set) var edge: Edge?
    public init() {}
    public init(id: some Hashable, anchor: UnitPoint? = nil) { self.id = AnyHashable(id) }
    public init(x: CGFloat, y: CGFloat) { point = CGPoint(x: x, y: y) }
    public init(point: CGPoint) { self.point = point }
    public init(edge: Edge) { self.edge = edge }
    public var viewID: (any Hashable)? { id?.base as? any Hashable }
    public func viewID<T: Hashable>(type: T.Type) -> T? { id?.base as? T }
    public var x: CGFloat? { point?.x }
    public var y: CGFloat? { point?.y }
    public var isPositionedByUser: Bool { false }
    public mutating func scrollTo(id: some Hashable, anchor: UnitPoint? = nil) { self.id = AnyHashable(id) }
    public mutating func scrollTo(x: CGFloat) { point = CGPoint(x: x, y: point?.y ?? 0) }
    public mutating func scrollTo(y: CGFloat) { point = CGPoint(x: point?.x ?? 0, y: y) }
    public mutating func scrollTo(point: CGPoint) { self.point = point }
    public mutating func scrollTo(edge: Edge) { self.edge = edge }
}

public struct ContentMarginPlacement: Hashable, Sendable {
    let raw: Int
    public static let automatic = ContentMarginPlacement(raw: 0)
    public static let scrollContent = ContentMarginPlacement(raw: 1)
    public static let scrollIndicators = ContentMarginPlacement(raw: 2)
}

// MARK: - Modifiers

extension View {
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View { self }
    public func scrollIndicatorsFlash(onAppear: Bool) -> some View { self }
    public func scrollIndicatorsFlash<T: Equatable>(trigger value: T) -> some View { self }
    public func scrollDisabled(_ disabled: Bool) -> some View { env { $0.isScrollEnabled = !disabled } }
    public func scrollTargetBehavior<T: ScrollTargetBehavior>(_ behavior: T) -> some View { self }
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View { self }
    public func scrollPosition(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View { self }
    public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View { self }
    public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical, .horizontal]) -> some View { self }
    public func scrollClipDisabled(_ disabled: Bool = true) -> some View { env { $0.scrollClipDisabled = disabled } }
    public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View { self }
    public func scrollInputBehavior(_ behavior: ScrollInputBehavior, for input: ScrollInputKind) -> some View { self }
    /// Read by the Liquid Glass bars of the enclosing navigation stack (top and bottom edges).
    public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View {
        navigationChrome { chrome, _ in
            if edges.contains(.top) { chrome.topEdgeEffectStyle = style ?? .automatic }
            if edges.contains(.bottom) { chrome.bottomEdgeEffectStyle = style ?? .automatic }
        }
    }
    public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View {
        navigationChrome { chrome, _ in
            if edges.contains(.top) { chrome.topEdgeEffectHidden = hidden }
            if edges.contains(.bottom) { chrome.bottomEdgeEffectHidden = hidden }
        }
    }
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View { self }
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View { self }
    public func scrollContentBackground(_ visibility: Visibility) -> some View { env { $0.scrollContentBackground = visibility } }
    public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T,
                                                      action: @escaping (T, T) -> Void) -> some View { self }
    public func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View { self }
    public func onScrollVisibilityChange(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) -> some View { self }

    public func contentMargins(_ length: CGFloat, for placement: ContentMarginPlacement = .automatic) -> some View {
        contentMargins(.all, length, for: placement)
    }
    public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for placement: ContentMarginPlacement = .automatic) -> some View {
        contentMargins(edges, EdgeInsets(edges, length ?? 0), for: placement)
    }
    public func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for placement: ContentMarginPlacement = .automatic) -> some View {
        env { env in
            guard placement != .scrollIndicators else { return }
            var m = env.scrollContentMargins
            if edges.contains(.top) { m.top = insets.top }
            if edges.contains(.leading) { m.leading = insets.leading }
            if edges.contains(.bottom) { m.bottom = insets.bottom }
            if edges.contains(.trailing) { m.trailing = insets.trailing }
            env.scrollContentMargins = m
        }
    }
}

public struct ScrollAnchorRole: Hashable, Sendable {
    let raw: Int
    public static let initialOffset = ScrollAnchorRole(raw: 0)
    public static let sizeChanges = ScrollAnchorRole(raw: 1)
    public static let alignment = ScrollAnchorRole(raw: 2)
}
