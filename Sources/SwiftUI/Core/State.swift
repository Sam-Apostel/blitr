import Observation

// MARK: - State

@propertyWrapper
public struct State<Value>: DynamicProperty, InstallableProperty {
    final class Storage { var value: Value; init(_ v: Value) { value = v } }
    /// Indirection so a freshly created view struct can be pointed at the persistent storage.
    final class Box { var storage: Storage; init(_ s: Storage) { storage = s } }
    let box: Box

    public init(wrappedValue value: Value) { box = Box(Storage(value)) }
    public init(initialValue value: Value) { box = Box(Storage(value)) }

    public var wrappedValue: Value {
        get { box.storage.value }
        nonmutating set {
            box.storage.value = newValue
            // SwiftUI tolerates updates from a background task (it logs a runtime warning); do the same.
            if Thread.isMainThread {
                MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true } }
            }
        }
    }

    public var projectedValue: Binding<Value> {
        let box = self.box
        return Binding(get: { box.storage.value }, set: { newValue in
            box.storage.value = newValue
            // SwiftUI tolerates updates from a background task (it logs a runtime warning); do the same.
            if Thread.isMainThread {
                MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true } }
            }
        })
    }

    func install(_ ic: inout InstallContext) {
        let initial = box.storage
        box.storage = ic.storage { initial }
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() { self.init(wrappedValue: nil) }
}

// MARK: - Binding

@propertyWrapper @dynamicMemberLookup
public struct Binding<Value>: DynamicProperty {
    let getter: () -> Value
    let setter: (Value) -> Void
    public var transaction = Transaction()

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        getter = get
        setter = { set($0, Transaction()) }
    }
    public init(projectedValue: Binding<Value>) { self = projectedValue }
    public init<V>(_ base: Binding<V>) where Value == V? {
        self.init(get: { base.wrappedValue }, set: { if let v = $0 { base.wrappedValue = v } })
    }
    public init?(_ base: Binding<Value?>) {
        guard let value = base.wrappedValue else { return nil }
        self.init(get: { base.wrappedValue ?? value }, set: { base.wrappedValue = $0 })
    }
    public init<V: Hashable>(_ base: Binding<V>) where Value == AnyHashable {
        self.init(get: { AnyHashable(base.wrappedValue) }, set: { if let v = $0.base as? V { base.wrappedValue = v } })
    }

    public static func constant(_ value: Value) -> Binding<Value> { Binding(get: { value }, set: { _ in }) }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(get: { self.wrappedValue[keyPath: keyPath] },
                         set: { self.wrappedValue[keyPath: keyPath] = $0 })
    }

}

extension Binding: @unchecked Sendable where Value: Sendable {}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Binding: Sequence where Value: MutableCollection {
    public typealias Element = Binding<Value.Element>
    public typealias Iterator = IndexingIterator<Binding<Value>>
    public typealias SubSequence = Slice<Binding<Value>>
}

extension Binding: Collection where Value: MutableCollection {
    public typealias Index = Value.Index
    public typealias Indices = Value.Indices
    public var startIndex: Value.Index { wrappedValue.startIndex }
    public var endIndex: Value.Index { wrappedValue.endIndex }
    public var indices: Value.Indices { wrappedValue.indices }
    public func index(after i: Value.Index) -> Value.Index { wrappedValue.index(after: i) }
    public func formIndex(after i: inout Value.Index) { wrappedValue.formIndex(after: &i) }
    public subscript(position: Value.Index) -> Binding<Value.Element> {
        Binding<Value.Element>(get: { self.wrappedValue[position] }, set: { self.wrappedValue[position] = $0 })
    }
}

extension Binding: BidirectionalCollection where Value: BidirectionalCollection & MutableCollection {
    public func index(before i: Value.Index) -> Value.Index { wrappedValue.index(before: i) }
    public func formIndex(before i: inout Value.Index) { wrappedValue.formIndex(before: &i) }
}

extension Binding: RandomAccessCollection where Value: MutableCollection & RandomAccessCollection {}

// MARK: - Observation-based wrappers

@propertyWrapper @dynamicMemberLookup
public struct Bindable<Value>: DynamicProperty {
    public var wrappedValue: Value
    public init(wrappedValue: Value) where Value: AnyObject & Observable { self.wrappedValue = wrappedValue }
    public init(_ wrappedValue: Value) where Value: AnyObject & Observable { self.wrappedValue = wrappedValue }
    public init(projectedValue: Bindable<Value>) where Value: AnyObject & Observable { self = projectedValue }
    public var projectedValue: Bindable<Value> { self }
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> where Value: AnyObject {
        let object = wrappedValue
        return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}

extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

// Transaction, Animation, withAnimation and withTransaction live in Animation/Animation.swift.
