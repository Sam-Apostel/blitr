// Focus information recorded on nodes while a view tree is resolved (the counterpart of `Node.ax`).
//
// Controls (Button, Toggle, Picker, ...) and the public focus modifiers append `FocusRecord`s to the
// nodes they produce (`Node.focusRecords`). A record on a node applies to that node's whole subtree.
// After layout, `FocusEngine` (FocusEngine.swift) walks the laid-out tree, turns the records into the
// focusable elements with global frames, and decides where focus is and where each remote press moves it.

// MARK: - Records

/// What a focusable element is. Recorded by the control that makes it focusable.
struct FocusElementInfo {
    /// Structural identity of the element (the resolve path of the modifier that recorded it).
    var path: IdentityPath
    /// Short role name used for ids and the JSON (`button`, `toggle`, `textField`, ...).
    var role: String
    var isEnabled: Bool
    /// `.focusEffectDisabled()` was in effect for the element.
    var effectDisabled: Bool
}

/// A binding between a region of the tree and a `@FocusState` value (`.focused(_:)`, `.focused(_:equals:)`).
struct FocusBinding {
    /// Identity of the `@FocusState` storage; several regions can share one.
    var storage: ObjectIdentifier
    /// The value the state has while focus is inside this region.
    var target: AnyHashable
    /// The value the state has while focus is elsewhere (false, or nil for an optional state).
    var unfocused: AnyHashable?
    var get: @MainActor () -> AnyHashable
    var set: @MainActor (AnyHashable) -> Void
}

@MainActor
final class FocusRecord {
    enum Kind {
        /// The node (and its siblings carrying the same record) is one focusable element.
        case element(FocusElementInfo)
        /// `.focusable(false)`: nothing in the subtree can take focus.
        case excluded
        /// `.focusSection()`.
        case section
        case scope(Namespace.ID)
        case prefersDefault(Namespace.ID)
        case binding(FocusBinding)
        case defaultFocus(storage: ObjectIdentifier, value: AnyHashable)
        case onMove((MoveCommandDirection) -> Void)
        case onExit(() -> Void)
        case onPlayPause(() -> Void)
    }
    let kind: Kind
    /// Identity of the view the record was made for (section ids are derived from it).
    let path: IdentityPath
    init(_ kind: Kind, path: IdentityPath) {
        self.kind = kind
        self.path = path
    }

    var element: FocusElementInfo? { if case .element(let e) = kind { return e }; return nil }
}

extension Node {
    /// Whether this subtree already holds a focusable element (used by `.focusable()` on a control).
    final func containsFocusElements() -> [FocusElementInfo] {
        var found: [FocusElementInfo] = []
        var seen: Set<ObjectIdentifier> = []
        func walk(_ node: Node) {
            for record in node.focusRecords {
                if case .element(let e) = record.kind {
                    if seen.insert(ObjectIdentifier(record)).inserted { found.append(e) }
                    return
                }
            }
            for child in node.children { walk(child) }
        }
        walk(self)
        return found
    }
}

// MARK: - Activation registry

/// What "activate this element" does for each element of the current pass, keyed by its identity:
/// the Button's action, flipping a Toggle, selecting a tab... Filled at resolve time (and by the focus
/// engine for chrome it synthesizes). Remote `select` uses it; a later `--tap` on iOS can reuse it.
@MainActor
struct ActivationRegistry {
    private var actions: [IdentityPath: @MainActor () -> Void] = [:]
    mutating func register(_ path: IdentityPath, _ action: (@MainActor () -> Void)?) {
        if let action { actions[path] = action }
    }
    func action(for path: IdentityPath) -> (@MainActor () -> Void)? { actions[path] }
    mutating func reset() { actions = [:] }
}

// MARK: - Environment

enum FocusEffectDisabledKey: EnvironmentKey { static let defaultValue = false }
enum NavigationStackIdentityKey: EnvironmentKey { static let defaultValue: IdentityPath? = nil }

extension EnvironmentValues {
    var focusEffectDisabled: Bool {
        get { self[FocusEffectDisabledKey.self] }
        set { self[FocusEffectDisabledKey.self] = newValue }
    }
    /// The enclosing navigation stack, so a NavigationLink can push onto it when activated.
    var navigationStackIdentity: IdentityPath? {
        get { self[NavigationStackIdentityKey.self] }
        set { self[NavigationStackIdentityKey.self] = newValue }
    }
}

// MARK: - Modifiers

/// Makes the content one focusable element: sets `isFocused` for it when it has focus, records the
/// element and its activation, and wraps it in the default focus effect.
struct FocusElementModifier: ViewModifier, PrimitiveModifier {
    let role: String
    let activate: (@MainActor () -> Void)?
    /// `.focusable()` written by the user: a no-op on content that is already a focusable control.
    var isUserFocusable = false

    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let path = ctx.path
        let engine = ctx.runtime.focus
        let focused = engine.focusedPath == path
        let inner = focused ? ctx.with { $0.isFocused = true } : ctx
        var nodes = content.nodes(inner)
        if isUserFocusable {
            let inside = nodes.flatMap { $0.containsFocusElements() }
            if !inside.isEmpty {
                if inside.count > 1 {
                    ctx.runtime.warn(".focusable() on a view that contains \(inside.count) focusable controls is ignored; the controls stay focusable on their own")
                }
                out.append(contentsOf: nodes)
                return
            }
        }
        // A focusable custom view fires its tap gesture when selected (tvOS sends select as a tap).
        var action = activate
        if action == nil, isUserFocusable {
            action = nodes.lazy.compactMap { $0.ax?.info.activate }.first
        }
        ctx.runtime.activations.register(path, action)
        let info = FocusElementInfo(path: path, role: role, isEnabled: ctx.env.isEnabled, effectDisabled: ctx.env.focusEffectDisabled)
        let record = FocusRecord(.element(info), path: path)
        for node in nodes { node.focusRecords.append(record) }
        if focused, info.isEnabled, ctx.env.renderPlatform == .tvOS, !info.effectDisabled {
            nodes = FocusEffect.wrap(nodes, ctx.env)
        }
        out.append(contentsOf: nodes)
    }
}

/// Attaches a non-element record (section, binding, command handler...) to every node of the content.
struct FocusRecordModifier: ViewModifier, PrimitiveModifier {
    let make: @MainActor (ResolveContext) -> FocusRecord.Kind?
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = content.nodes(ctx)
        if let kind = make(ctx) {
            let record = FocusRecord(kind, path: ctx.path)
            for node in nodes { node.focusRecords.append(record) }
        }
        out.append(contentsOf: nodes)
    }
}

extension View {
    /// Internal: the built-in controls use this to become focusable elements.
    func focusElement(role: String, activate: (@MainActor () -> Void)? = nil) -> ModifiedContent<Self, FocusElementModifier> {
        modifier(FocusElementModifier(role: role, activate: activate))
    }
    func focusRecord(_ make: @escaping @MainActor (ResolveContext) -> FocusRecord.Kind?) -> ModifiedContent<Self, FocusRecordModifier> {
        modifier(FocusRecordModifier(make: make))
    }
}

// MARK: - Public API

/// The direction of a move command (a swipe or click on the Siri Remote's touch surface).
public enum MoveCommandDirection: Equatable, Hashable, Sendable {
    case up, down, left, right
}

extension FocusState.Binding {
    @MainActor func focusBinding(target: Value) -> FocusBinding {
        let getter = self.getter, setter = self.setter
        var unfocused: AnyHashable?
        if Value.self == Bool.self { unfocused = AnyHashable(false) }
        else if let nilType = Value.self as? ExpressibleByNilLiteral.Type, let none = nilType.init(nilLiteral: ()) as? Value {
            unfocused = AnyHashable(none)
        }
        return FocusBinding(storage: storageID, target: AnyHashable(target), unfocused: unfocused,
                            get: { AnyHashable(getter()) },
                            set: { value in if let v = value.base as? Value { setter(v) } })
    }
}

extension View {
    public func focusable(_ isFocusable: Bool = true) -> some View {
        modifier(FocusableModifier(isFocusable: isFocusable))
    }
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        modifier(FocusableModifier(isFocusable: isFocusable))
    }

    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        focusRecord { _ in .binding(condition.focusBinding(target: true)) }
    }
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        focusRecord { _ in .binding(binding.focusBinding(target: value)) }
    }

    public func focusEffectDisabled(_ disabled: Bool = true) -> some View { env { $0.focusEffectDisabled = disabled } }
    public func focusSection() -> some View { focusRecord { _ in .section } }
    public func focusScope(_ namespace: Namespace.ID) -> some View { focusRecord { _ in .scope(namespace) } }
    public func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View {
        focusRecord { _ in prefersDefaultFocus ? .prefersDefault(namespace) : nil }
    }
    public func defaultFocus<V: Hashable>(_ binding: FocusState<V>.Binding, _ value: V,
                                          priority: DefaultFocusEvaluationPriority = .automatic) -> some View {
        focusRecord { ctx in
            if priority == .userInitiated {
                ctx.runtime.warn("defaultFocus(priority: .userInitiated) is treated like .automatic: only the initial focus of a screen is modelled")
            }
            return .defaultFocus(storage: binding.storageID, value: AnyHashable(value))
        }
    }

    public func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
        focusRecord { _ in action.map { .onMove($0) } }
    }
    public func onExitCommand(perform action: (() -> Void)?) -> some View {
        focusRecord { _ in action.map { .onExit($0) } }
    }
    public func onPlayPauseCommand(perform action: (() -> Void)?) -> some View {
        focusRecord { _ in action.map { .onPlayPause($0) } }
    }
}

/// `.focusable(true)` makes a custom view an element; `.focusable(false)` removes focusability from
/// everything inside.
struct FocusableModifier: ViewModifier, PrimitiveModifier {
    let isFocusable: Bool
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        if isFocusable {
            FocusElementModifier(role: "focusable", activate: nil, isUserFocusable: true).resolve(content: content, ctx, into: &out)
        } else {
            FocusRecordModifier { _ in .excluded }.resolve(content: content, ctx, into: &out)
        }
    }
}
