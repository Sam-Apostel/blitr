// Turning a View value into a tree of render nodes.

/// Structural identity of a view: the path of builder positions / ForEach ids that leads to it.
struct IdentityPath: Hashable {
    var components: [AnyHashable] = []
    func appending(_ c: AnyHashable) -> IdentityPath {
        var copy = self
        copy.components.append(c)
        return copy
    }
}

struct ResolveContext {
    var env: EnvironmentValues
    var path: IdentityPath
    let runtime: Runtime

    func child(_ component: AnyHashable) -> ResolveContext {
        ResolveContext(env: env, path: path.appending(component), runtime: runtime)
    }
    func with(_ modify: (inout EnvironmentValues) -> Void) -> ResolveContext {
        var copy = self
        modify(&copy.env)
        return copy
    }
}

/// Per-render mutable state that outlives a single resolve pass.
@MainActor
final class Runtime {
    /// Storage for @State/@StateObject, keyed by view identity so it survives re-resolving.
    var stateStore: [IdentityPath: [AnyObject]] = [:]
    /// onAppear-style actions that have already run (each runs once per identity).
    var performedActions: Set<IdentityPath> = []
    var pendingActions: [() -> Void] = []
    /// Run after layout in each pass, when geometry-dependent values (preferences set inside a
    /// GeometryReader, measured sizes) are known.
    var postLayoutActions: [() -> Void] = []
    /// Set when state changes after the tree was resolved, so the renderer does another pass.
    var needsAnotherPass = false
    var runningTasks = 0
    private(set) var warnings: [String] = []
    private var warningSet: Set<String> = []
    var config: RenderConfiguration
    /// Absolute origins of `.coordinateSpace(name:)` views, recorded during layout.
    var namedCoordinateSpaces: [AnyHashable: CGPoint] = [:]
    /// Which element has focus, scroll offsets, navigation pushes: state that survives passes (Focus/).
    let focus = FocusEngine()
    /// What activating each element does, rebuilt every pass (Focus/FocusModel.swift).
    var activations = ActivationRegistry()
    /// The value each `onChange` saw in the previous pass (tvOS: see Modifiers/Lifecycle.swift).
    var changeValues: [IdentityPath: AnyObject] = [:]

    static var current: Runtime?

    init(config: RenderConfiguration) { self.config = config }

    func warn(_ message: String) {
        if warningSet.insert(message).inserted { warnings.append(message) }
    }
}

@MainActor
func resolveView<V: View>(_ view: V, _ ctx: ResolveContext, into out: inout [Node]) {
    if let primitive = view as? PrimitiveView {
        primitive.resolve(ctx, into: &out)
        return
    }
    let ctx = ctx.child(ObjectIdentifier(V.self))
    installDynamicProperties(of: view, ctx)
    resolveView(view.body, ctx, into: &out)
}

@MainActor
func resolveNodes<V: View>(_ view: V, _ ctx: ResolveContext) -> [Node] {
    var out: [Node] = []
    resolveView(view, ctx, into: &out)
    return out
}

/// Resolves a view that must act as exactly one layout child: several views are stacked
/// implicitly (the same thing SwiftUI does for a multi-view `body`).
@MainActor
func resolveSingle<V: View>(_ view: V, _ ctx: ResolveContext) -> Node {
    let nodes = resolveNodes(view, ctx)
    if nodes.count == 1 { return nodes[0] }
    return StackNode(axis: .vertical, alignment: .center, spacing: nil, children: nodes)
}

// MARK: - Dynamic properties

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

/// Property wrappers that need to be connected to the runtime before `body` runs.
protocol InstallableProperty {
    @MainActor func install(_ ic: inout InstallContext)
}

struct InstallContext {
    let ctx: ResolveContext
    var slot = 0

    /// Returns the persistent storage for the next state slot of the current view,
    /// creating it from `initial` the first time this view identity is seen.
    @MainActor mutating func storage<T: AnyObject>(initial: () -> T) -> T {
        defer { slot += 1 }
        var slots = ctx.runtime.stateStore[ctx.path] ?? []
        if slot < slots.count, let existing = slots[slot] as? T { return existing }
        let created = initial()
        if slot < slots.count { slots[slot] = created } else { slots.append(created) }
        ctx.runtime.stateStore[ctx.path] = slots
        return created
    }
}

@MainActor
func installDynamicProperties(of value: Any, _ ctx: ResolveContext) {
    var ic = InstallContext(ctx: ctx)
    installDynamicProperties(of: value, &ic)
}

@MainActor
private func installDynamicProperties(of value: Any, _ ic: inout InstallContext) {
    for child in Mirror(reflecting: value).children {
        if let property = child.value as? InstallableProperty {
            property.install(&ic)
        } else if child.value is any DynamicProperty {
            installDynamicProperties(of: child.value, &ic)
        }
    }
}
