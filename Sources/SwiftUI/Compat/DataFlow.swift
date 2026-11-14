// ObservableObject-based data flow: @StateObject, @ObservedObject, @EnvironmentObject, onReceive.

/// Process-wide scratch space for the compatibility wrappers (in-memory "persistent" storage,
/// subscriptions that must outlive the resolve pass that created them).
final class CompatStore {
    nonisolated(unsafe) static let shared = CompatStore()
    var defaults: [String: Any] = [:]
    var retained: [AnyObject] = []
    var hookInstalled = false

    /// Any change published by an ObservableObject means state may have moved after layout.
    func installObservationHook() {
        guard !hookInstalled else { return }
        hookInstalled = true
        ObservableObjectPublisher._didChange = { CompatStore.markChanged() }
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

    @MainActor func install(_ ic: inout InstallContext) { CompatStore.shared.installObservationHook() }
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
        CompatStore.shared.installObservationHook()
        let box = self.box
        let holder = ic.storage { Holder(box.resolve()) }
        box.object = holder.object
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
        CompatStore.shared.installObservationHook()
        box.env = ic.ctx.env
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
