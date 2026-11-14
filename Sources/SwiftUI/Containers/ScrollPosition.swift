// ScrollPosition and `.scrollPosition`: where a scroll view is scrolled to. A frame has no scrolling, but a
// position set in code (an edge, a point, a view id) is where the scroll view sits when the frame is taken,
// so the ScrollView lays its content out at that offset.
import Foundation

public struct ScrollPosition: Equatable, @unchecked Sendable {
    public static func == (a: ScrollPosition, b: ScrollPosition) -> Bool {
        a.id == b.id && a.anchor == b.anchor && a.edge == b.edge && a.x == b.x && a.y == b.y && a.isPositionedByUser == b.isPositionedByUser
    }

    var id: AnyHashable?
    private var sendableID: (any Hashable & Sendable)?
    var anchor: UnitPoint?
    public private(set) var edge: Edge?
    public private(set) var x: CGFloat?
    public private(set) var y: CGFloat?
    /// Set by the system when the person scrolls. Nobody scrolls a still frame.
    public var isPositionedByUser = false

    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self) {}
    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self, edge: Edge) { self.edge = edge }
    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self, point: CGPoint) { x = point.x; y = point.y }
    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self, x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self, x: CGFloat) { self.x = x }
    public init<ID: Hashable & Sendable>(idType: ID.Type = Never.self, y: CGFloat) { self.y = y }
    public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        self.id = AnyHashable(id)
        self.sendableID = id
        self.anchor = anchor
    }

    /// The point scrolled to, when both coordinates were given.
    public var point: CGPoint? {
        guard let x, let y else { return nil }
        return CGPoint(x: x, y: y)
    }
    public var viewID: (any Hashable & Sendable)? { sendableID }
    public func viewID<T: Hashable & Sendable>(type: T.Type) -> T? { id?.base as? T }

    private mutating func reset() {
        id = nil
        sendableID = nil
        anchor = nil
        edge = nil
        x = nil
        y = nil
        isPositionedByUser = false
    }
    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        reset()
        self.id = AnyHashable(id)
        self.sendableID = id
        self.anchor = anchor
    }
    public mutating func scrollTo(edge: Edge) { reset(); self.edge = edge }
    public mutating func scrollTo(point: CGPoint) { reset(); x = point.x; y = point.y }
    public mutating func scrollTo(x: CGFloat, y: CGFloat) { reset(); self.x = x; self.y = y }
    public mutating func scrollTo(x: CGFloat) { reset(); self.x = x }
    public mutating func scrollTo(y: CGFloat) { reset(); self.y = y }
}

/// A scroll position on its way to the scroll view it is applied to.
struct ScrollRequest {
    var position: ScrollPosition
    /// The modifier's anchor: which point of the view with the id goes to which point of the scroll view.
    var defaultAnchor: UnitPoint?

    var needsLayout: Bool { position.id != nil }

    @MainActor
    func offset(content: Node, contentSize: CGSize, visible: CGSize, axes: Axis.Set) -> CGPoint {
        let maxX = axes.contains(.horizontal) ? max(0, contentSize.width - visible.width) : 0
        let maxY = axes.contains(.vertical) ? max(0, contentSize.height - visible.height) : 0
        var target = CGPoint.zero
        if let id = position.id {
            guard let node = Self.find(id, in: content) else {
                Runtime.current?.warn("scrollPosition: no view with id \(id.base) in the scroll view; it stays at the top")
                return .zero
            }
            let frame = CGRect(x: node.absoluteOrigin.x - content.absoluteOrigin.x, y: node.absoluteOrigin.y - content.absoluteOrigin.y,
                               width: node.frame.width, height: node.frame.height)
            if let anchor = position.anchor ?? defaultAnchor {
                target.x = frame.minX + frame.width * anchor.x - visible.width * anchor.x
                target.y = frame.minY + frame.height * anchor.y - visible.height * anchor.y
            } else {
                // No anchor: scroll the least amount that shows the view (from the top, that is its far edge).
                target.x = max(0, frame.maxX - visible.width)
                target.y = max(0, frame.maxY - visible.height)
                if frame.width > visible.width { target.x = frame.minX }
                if frame.height > visible.height { target.y = frame.minY }
            }
        } else if let edge = position.edge {
            switch edge {
            case .top, .leading: break
            case .bottom: target.y = maxY
            case .trailing: target.x = maxX
            }
        } else {
            target = CGPoint(x: position.x ?? 0, y: position.y ?? 0)
        }
        return CGPoint(x: min(max(0, target.x), maxX), y: min(max(0, target.y), maxY))
    }

    @MainActor
    private static func find(_ id: AnyHashable, in node: Node) -> Node? {
        if node.traits[IDTraitKey.self] == id { return node }
        for child in node.children {
            if let found = find(id, in: child) { return found }
        }
        return nil
    }
}

enum ScrollRequestKey: EnvironmentKey { static let defaultValue: ScrollRequest? = nil }
extension EnvironmentValues {
    var scrollRequest: ScrollRequest? {
        get { self[ScrollRequestKey.self] }
        set { self[ScrollRequestKey.self] = newValue }
    }
}

extension View {
    /// The scroll view this is applied to is drawn at the position's offset.
    public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        let value = position.wrappedValue
        return env { $0.scrollRequest = ScrollRequest(position: value, defaultAnchor: anchor) }
    }
    /// With a non-nil id, the scroll view is drawn scrolled to the view with that id.
    public func scrollPosition(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View {
        var position = ScrollPosition()
        if let value = id.wrappedValue {
            position.id = AnyHashable(value)
            position.anchor = anchor
        }
        let request = position.id == nil ? nil : ScrollRequest(position: position, defaultAnchor: anchor)
        return env { $0.scrollRequest = request }
    }
}
