// Small property wrappers: @FocusState (made live by Focus/), @AccessibilityFocusState, @Namespace, @GestureState, @ScaledMetric.
// The modifiers that consume them (`.focused`, `.matchedGeometryEffect`, gestures) live elsewhere.

// MARK: - FocusState

@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty, InstallableProperty {
    final class Storage { var value: Value; init(_ v: Value) { value = v } }
    final class Box { var storage: Storage; init(_ s: Storage) { storage = s } }
    let box: Box

    @propertyWrapper
    public struct Binding {
        let getter: () -> Value
        let setter: (Value) -> Void
        /// Identity of the state's storage, so the focus engine can tell bindings of one state apart.
        let storageID: ObjectIdentifier
        init(get: @escaping () -> Value, set: @escaping (Value) -> Void, storageID: ObjectIdentifier) {
            getter = get; setter = set; self.storageID = storageID
        }
        public var wrappedValue: Value {
            get { getter() }
            nonmutating set { setter(newValue) }
        }
        public var projectedValue: FocusState<Value>.Binding { self }
    }

    init(initial: Value) { box = Box(Storage(initial)) }
    public init() where Value == Bool { self.init(initial: false) }
    public init(wrappedValue: Value) where Value == Bool { self.init(initial: wrappedValue) }
    public init<T: Hashable>() where Value == T? { self.init(initial: nil) }
    public init<T: Hashable>(wrappedValue: Value) where Value == T? { self.init(initial: wrappedValue) }

    public var wrappedValue: Value {
        get { box.storage.value }
        nonmutating set { box.storage.value = newValue; CompatStore.markChanged() }
    }
    public var projectedValue: FocusState<Value>.Binding {
        let box = self.box
        return Binding(get: { box.storage.value }, set: { box.storage.value = $0; CompatStore.markChanged() },
                       storageID: ObjectIdentifier(box.storage))
    }

    @MainActor func install(_ ic: inout InstallContext) {
        let initial = box.storage
        box.storage = ic.storage { initial }
    }
}


// MARK: - Namespace

@propertyWrapper
public struct Namespace: DynamicProperty, InstallableProperty {
    public struct ID: Hashable, Sendable {
        let raw: Int
    }
    final class Box { var id: ID; init(_ id: ID) { self.id = id } }
    nonisolated(unsafe) static var counter = 0
    let box: Box

    public init() {
        Namespace.counter += 1
        box = Box(ID(raw: Namespace.counter))
    }
    public var wrappedValue: Namespace.ID { box.id }

    @MainActor func install(_ ic: inout InstallContext) {
        let initial = box.id
        final class IDHolder { let id: Namespace.ID; init(_ id: Namespace.ID) { self.id = id } }
        box.id = ic.storage { IDHolder(initial) }.id
    }
}

// MARK: - GestureState

@propertyWrapper
public struct GestureState<Value>: DynamicProperty, InstallableProperty {
    final class Storage { var value: Value; init(_ v: Value) { value = v } }
    final class Box { var storage: Storage; init(_ s: Storage) { storage = s } }
    let box: Box

    public init(wrappedValue: Value) { box = Box(Storage(wrappedValue)) }
    public init(initialValue: Value) { box = Box(Storage(initialValue)) }
    public init(wrappedValue: Value, resetTransaction: Transaction) { box = Box(Storage(wrappedValue)) }
    public init(initialValue: Value, resetTransaction: Transaction) { box = Box(Storage(initialValue)) }
    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) { box = Box(Storage(wrappedValue)) }
    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) { box = Box(Storage(initialValue)) }

    /// Gesture state is read-only for the view; it always shows its initial value in a still frame.
    public var wrappedValue: Value { box.storage.value }
    public var projectedValue: GestureState<Value> { self }

    @MainActor func install(_ ic: inout InstallContext) {
        let initial = box.storage
        box.storage = ic.storage { initial }
    }
}

// MARK: - ScaledMetric

@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty, InstallableProperty {
    final class Box { var env: EnvironmentValues? }
    let base: Value
    let textStyle: Font.TextStyle
    let box = Box()

    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
        base = wrappedValue
        self.textStyle = textStyle
    }
    public init(wrappedValue: Value) {
        base = wrappedValue
        textStyle = .body
    }

    public var wrappedValue: Value {
        let size = box.env?.dynamicTypeSize ?? .large
        return base * Value(size.scale(for: textStyle))
    }

    @MainActor func install(_ ic: inout InstallContext) { box.env = ic.ctx.env }
}
