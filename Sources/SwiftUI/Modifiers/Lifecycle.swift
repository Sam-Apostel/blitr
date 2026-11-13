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
        content.resolve(ctx, into: &out)
    }
}


extension View {
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        modifier(LifecycleModifier(key: "onAppear") { _ in action?() })
    }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }

    /// Async work is started and given a short time budget (see `RenderConfiguration.taskBudget`);
    /// whatever state it has produced by then is what gets rendered.
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(LifecycleModifier(key: "task") { runtime in runtime.start(action) })
    }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(LifecycleModifier(key: "task") { runtime in runtime.start(action) })
    }

    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(LifecycleModifier(key: "onChange") { _ in if initial { action(value, value) } })
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
        modifier(LifecycleModifier(key: "onChange") { _ in if initial { action() } })
    }
    @_disfavoredOverload
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View { self }
}

extension Runtime {
    func start(_ action: @escaping @Sendable () async -> Void) {
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
