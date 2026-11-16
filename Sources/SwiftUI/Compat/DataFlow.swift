// ObservableObject-based data flow: @StateObject, @ObservedObject, @EnvironmentObject, onReceive.

/// Process-wide scratch space for the compatibility wrappers (in-memory "persistent" storage,
/// subscriptions that must outlive the resolve pass that created them).
final class CompatStore {
    nonisolated(unsafe) static let shared = CompatStore()
    /// `@AppStorage` and `@SceneStorage` values. They start empty, never from the host's defaults, so a render
    /// does not depend on the machine it runs on; but the launch arguments' `-key value` pairs are there, as
    /// UserDefaults' argument domain puts them on iOS (`--arg -onboarded --arg YES`).
    var defaults: [String: Any] = CompatStore.argumentDomain(Array(CommandLine.arguments.dropFirst()))

    /// `-key value` pairs, as UserDefaults reads them from the launch arguments.
    static func argumentDomain(_ arguments: [String]) -> [String: Any] {
        var domain: [String: Any] = [:]
        var i = 0
        while i + 1 < arguments.count {
            let key = arguments[i]
            if key.count > 1, key.hasPrefix("-"), !key.hasPrefix("--") {
                domain[String(key.dropFirst())] = arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return domain
    }
    var retained: [AnyObject] = []
    var hookInstalled = false

    /// Any change published by an ObservableObject means state may have moved after layout. Our Combine
    /// (Linux) reports every object's change through one hook; Apple's (Darwin) has none, so each object a
    /// view observes is subscribed to on its own.
    func installObservationHook() {
        #if !canImport(Darwin)
        guard !hookInstalled else { return }
        hookInstalled = true
        ObservableObjectPublisher._didChange = { CompatStore.markChanged() }
        #endif
    }

    #if canImport(Darwin)
    private struct Subscription { weak var object: AnyObject?; var cancellable: AnyCancellable }
    private var subscriptions: [ObjectIdentifier: Subscription] = [:]
    #endif

    func observe<Object: ObservableObject>(_ object: Object) {
        installObservationHook()
        #if canImport(Darwin)
        let id = ObjectIdentifier(object)
        if let existing = subscriptions[id], existing.object === object { return }
        if subscriptions.count > 512 { subscriptions = subscriptions.filter { $0.value.object != nil } }
        subscriptions[id] = Subscription(object: object, cancellable: object.objectWillChange.sink { _ in CompatStore.markChanged() })
        #endif
    }

    static func markChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true } }
            return
        }
        MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true }
    }
}

// MARK: - ObservedObject

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty, InstallableProperty {
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let object = self.object
            return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }

    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public init(initialValue: ObjectType) { wrappedValue = initialValue }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }

    @MainActor func install(_ ic: inout InstallContext) { CompatStore.shared.observe(wrappedValue) }
}

// MARK: - StateObject

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty, InstallableProperty {
    final class Box {
        var thunk: (() -> ObjectType)?
        var object: ObjectType?
        func resolve() -> ObjectType {
            if let object { return object }
            let created = thunk!()
            object = created
            return created
        }
    }
    final class Holder {
        let object: ObjectType
        init(_ object: ObjectType) { self.object = object }
    }
    let box = Box()

    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { box.thunk = thunk }

    public var wrappedValue: ObjectType { box.resolve() }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object: box.resolve()) }

    /// The object is created once per view identity; later passes reuse it and ignore the autoclosure.
    @MainActor func install(_ ic: inout InstallContext) {
        let box = self.box
        let holder = ic.storage { Holder(box.resolve()) }
        box.object = holder.object
        CompatStore.shared.observe(holder.object)
    }
}

// MARK: - EnvironmentObject

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty, InstallableProperty {
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let object = self.object
            return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }
    final class Box { var env: EnvironmentValues? }
    let box = Box()

    public init() {}

    public var wrappedValue: ObjectType {
        guard let object = box.env?[object: ObjectType.self] as? ObjectType else {
            fatalError("No ObservableObject of type \(ObjectType.self) found. A View.environmentObject(_:) for \(ObjectType.self) may be missing as an ancestor of this view.")
        }
        return object
    }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }

    @MainActor func install(_ ic: inout InstallContext) {
        box.env = ic.ctx.env
        if let object = ic.ctx.env[object: ObjectType.self] as? ObjectType { CompatStore.shared.observe(object) } else { CompatStore.shared.installObservationHook() }
    }
}

extension View {
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View {
        env { $0[object: T.self] = object }
    }

    /// Subscribes once when the view first appears; values the publisher produces synchronously
    /// (`Just`, `CurrentValueSubject`, ...) are delivered, timers and network publishers stay silent.
    public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View where P.Failure == Never {
        modifier(LifecycleModifier(key: "onReceive-\(ObjectIdentifier(P.self).hashValue)") { _ in
            CompatStore.shared.retained.append(publisher.sink(receiveValue: action))
        })
    }
}
