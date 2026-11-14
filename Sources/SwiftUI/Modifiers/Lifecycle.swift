// onAppear / task / onChange. A screenshot is one frame, but views commonly set up their
// state in these hooks, so they run once and the tree is resolved again afterwards.

struct LifecycleModifier: ViewModifier, PrimitiveModifier {
    let key: String
    let action: @MainActor (Runtime) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let identity = ctx.path.appending(key)
        if ctx.runtime.performedActions.insert(identity).inserted {
            let runtime = ctx.runtime
            let action = self.action
            runtime.pendingActions.append { action(runtime) }
        }
        // Content resolves under this modifier's key so stacked lifecycle modifiers get distinct identities.
        content.resolve(ctx.child(key), into: &out)
    }
}


extension View {
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        modifier(LifecycleModifier(key: "onAppear") { _ in action?() })
    }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }

    /// Async work is started and given a short time budget (see `RenderConfiguration.taskBudget`);
    /// whatever state it has produced by then is what gets rendered.
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @isolated(any) @Sendable () async -> Void) -> some View {
        modifier(LifecycleModifier(key: "task") { runtime in runtime.start(action) })
    }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated, _ action: @escaping @isolated(any) @Sendable () async -> Void) -> some View {
        modifier(LifecycleModifier(key: "task") { runtime in runtime.start(action) })
    }

    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(OnChangeModifier(value: value, initial: initial, action: action))
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
        modifier(OnChangeModifier(value: value, initial: initial) { _, _ in action() })
    }
    @_disfavoredOverload
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        modifier(OnChangeModifier(value: value, initial: false, runsInitially: false) { _, new in action(new) })
    }
}

/// `onChange`: the `initial` call runs once like `onAppear`. A value that differs from the previous pass
/// (state set in `onAppear` or `.task`, focus moving, a simulated press) calls the action with old and new.
final class OnChangeBox<V> {
    var value: V
    init(_ value: V) { self.value = value }
}

struct OnChangeModifier<V: Equatable>: ViewModifier, PrimitiveModifier {
    let value: V
    let initial: Bool
    var runsInitially = true
    let action: (V, V) -> Void

    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let identity = ctx.path.appending("onChange")
        let runtime = ctx.runtime
        let value = self.value, action = self.action, initial = self.initial
        if runsInitially, runtime.performedActions.insert(identity).inserted {
            runtime.pendingActions.append { if initial { action(value, value) } }
        }
        if let box = runtime.changeValues[identity] as? OnChangeBox<V> {
            if box.value != value {
                let old = box.value
                box.value = value
                runtime.pendingActions.append { action(old, value) }
            }
        } else {
            runtime.changeValues[identity] = OnChangeBox(value)
        }
        content.resolve(ctx.child("onChange"), into: &out)
    }
}

extension Runtime {
    func start(_ action: @escaping @isolated(any) @Sendable () async -> Void) {
        runningTasks += 1
        Task { @MainActor in
            await action()
            self.runningTasks -= 1
            self.needsAnotherPass = true
        }
    }

    /// Lets started tasks run on the main actor until they finish or the budget is spent.
    func drainTasks() {
        guard runningTasks > 0 else { return }
        let deadline = Date().addingTimeInterval(config.taskBudget)
        while runningTasks > 0, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        if runningTasks > 0 {
            warn("A .task did not finish within \(config.taskBudget)s; rendering the state reached so far")
        }
    }
}

// MARK: - Enabled state (shared by every control)

enum IsEnabledKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

extension View {
    public func disabled(_ disabled: Bool) -> some View { env { if disabled { $0.isEnabled = false } } }
}
