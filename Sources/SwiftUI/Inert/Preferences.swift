// Preference consumers (onPreferenceChange, overlay/backgroundPreferenceValue), anchor preferences
// and onGeometryChange. Anchors need a layout result, so the rect each anchored view occupied is
// remembered between passes: the first pass resolves with `.zero`, then asks the renderer for
// another pass, which sees the real rect.

// MARK: - Helpers

/// Combines `value` into a node's preference the way a parent combines its children's.
@MainActor
func contributePreference<K: PreferenceKey>(_ key: K.Type, _ value: K.Value, to node: Node) {
    var current = node.preferences.has(key) ? node.preferences[key] : K.defaultValue
    K.reduce(value: &current) { value }
    node.preferences.set(key, current)
}

@MainActor
func mergedPreferences(of nodes: [Node]) -> PreferenceStore {
    var store = PreferenceStore()
    for node in nodes { store.merge(node.preferences) }
    return store
}

final class LastValueBox<T> {
    var value: T?
}

// MARK: - onPreferenceChange

struct PreferenceChangeModifier<K: PreferenceKey>: ViewModifier, PrimitiveModifier where K.Value: Equatable {
    let action: (K.Value) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = content.nodes(ctx)
        let value = mergedPreferences(of: nodes)[K.self]
        var ic = InstallContext(ctx: ctx.child("onPreferenceChange"))
        let box = ic.storage { LastValueBox<K.Value>() }
        if box.value != value {
            box.value = value
            let action = self.action
            ctx.runtime.pendingActions.append { action(value) }
        }
        out.append(contentsOf: nodes)
    }
}

// MARK: - background / overlay PreferenceValue

struct PreferenceSecondaryModifier<K: PreferenceKey, Secondary: View>: ViewModifier, PrimitiveModifier {
    let transform: (K.Value) -> Secondary
    let alignment: Alignment
    let inFront: Bool
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, primary) in content.nodes(ctx).enumerated() {
            let value = primary.preferences[K.self]
            let secondaryContext = ctx.child(inFront ? "overlayPref\(i)" : "backgroundPref\(i)").with { $0.stackAxis = nil }
            let nodes = resolveNodes(transform(value), secondaryContext)
            let node = nodes.count == 1 ? nodes[0] : ZStackNode(alignment: alignment, children: nodes)
            out.append(SecondaryNode(primary: primary, secondary: node, alignment: alignment, inFront: inFront))
        }
    }
}

// MARK: - Anchor preferences

/// Remembers where the anchored view was laid out.
final class AnchorRectBox {
    var rect: CGRect = .zero
    var used: CGRect = .zero
}

final class AnchorRecordingNode: WrapperNode {
    let box: AnchorRectBox
    let runtime: Runtime
    init(child: Node, box: AnchorRectBox, runtime: Runtime) {
        self.box = box
        self.runtime = runtime
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        box.rect = CGRect(origin: ctx.origin, size: size)
        if box.rect != box.used { runtime.needsAnotherPass = true }
        super.layout(size: size, ctx)
    }
}

struct AnchorPreferenceModifier<A, K: PreferenceKey>: ViewModifier, PrimitiveModifier {
    let source: Anchor<A>.Source
    let apply: (inout K.Value, Anchor<A>) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, node) in content.nodes(ctx).enumerated() {
            var ic = InstallContext(ctx: ctx.child("anchorPreference\(i)"))
            let box = ic.storage { AnchorRectBox() }
            box.used = box.rect
            let anchor = Anchor<A>(rect: box.rect, source: source)
            var value = node.preferences.has(K.self) ? node.preferences[K.self] : K.defaultValue
            apply(&value, anchor)
            node.preferences.set(K.self, value)
            out.append(AnchorRecordingNode(child: node, box: box, runtime: ctx.runtime))
        }
    }
}

extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Anchor<Value>, rhs: Anchor<Value>) -> Bool { lhs.value == rhs.value }
}
extension Anchor: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

extension Anchor.Source where Value == CGPoint {
    public static func unitPoint(_ p: UnitPoint) -> Anchor<CGPoint>.Source {
        .init { CGPoint(x: $0.minX + $0.width * p.x, y: $0.minY + $0.height * p.y) }
    }
}
extension Anchor.Source where Value == CGRect {
    public static func unitRect(_ r: CGRect) -> Anchor<CGRect>.Source {
        .init { CGRect(x: $0.minX + $0.width * r.minX, y: $0.minY + $0.height * r.minY,
                       width: $0.width * r.width, height: $0.height * r.height) }
    }
}

// MARK: - onGeometryChange

final class GeometryChangeNode<T: Equatable>: WrapperNode {
    let transform: (GeometryProxy) -> T
    let action: (T?, T) -> Void
    let runtime: Runtime
    let box: LastValueBox<T>
    init(child: Node, runtime: Runtime, box: LastValueBox<T>, transform: @escaping (GeometryProxy) -> T, action: @escaping (T?, T) -> Void) {
        self.transform = transform
        self.action = action
        self.runtime = runtime
        self.box = box
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let bleed = ctx.safeAreaBleed(for: CGRect(origin: ctx.origin, size: size), edges: .all)
        let proxy = GeometryProxy(size: size, safeAreaInsets: bleed, absoluteOrigin: ctx.origin,
                                  namedSpaces: runtime.namedCoordinateSpaces)
        let value = transform(proxy)
        if box.value != value {
            let old = box.value
            box.value = value
            let action = self.action
            runtime.pendingActions.append { action(old, value) }
        }
        super.layout(size: size, ctx)
    }
}

struct GeometryChangeModifier<T: Equatable>: ViewModifier, NodeModifier {
    let transform: (GeometryProxy) -> T
    let action: (T?, T) -> Void
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        var ic = InstallContext(ctx: ctx.child("onGeometryChange"))
        let box = ic.storage { LastValueBox<T>() }
        return GeometryChangeNode(child: child, runtime: ctx.runtime, box: box, transform: transform, action: action)
    }
}

// MARK: - View API

extension View {
    public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self,
                                                     perform action: @escaping (K.Value) -> Void) -> some View where K.Value: Equatable {
        modifier(PreferenceChangeModifier<K>(action: action))
    }

    public func backgroundPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type = K.self, alignment: Alignment = .center,
                                                                     @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        modifier(PreferenceSecondaryModifier<K, V>(transform: transform, alignment: alignment, inFront: false))
    }
    public func overlayPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type = K.self, alignment: Alignment = .center,
                                                                  @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        modifier(PreferenceSecondaryModifier<K, V>(transform: transform, alignment: alignment, inFront: true))
    }

    public func anchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                      transform: @escaping (Anchor<A>) -> K.Value) -> some View {
        modifier(AnchorPreferenceModifier<A, K>(source: value) { current, anchor in
            let contribution = transform(anchor)
            K.reduce(value: &current) { contribution }
        })
    }
    public func transformAnchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                               transform: @escaping (inout K.Value, Anchor<A>) -> Void) -> some View {
        modifier(AnchorPreferenceModifier<A, K>(source: value) { current, anchor in transform(&current, anchor) })
    }

    public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                               action: @escaping (_ newValue: T) -> Void) -> some View {
        modifier(GeometryChangeModifier<T>(transform: transform) { _, new in action(new) })
    }
    public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                               action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        modifier(GeometryChangeModifier<T>(transform: transform) { old, new in action(old ?? new, new) })
    }
}
