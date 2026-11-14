// @AppStorage / @SceneStorage: values live in an in-memory table keyed by the storage key.

@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    let key: String
    let defaultValue: Value

    init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get { (CompatStore.shared.defaults[key] as? Value) ?? defaultValue }
        nonmutating set {
            CompatStore.shared.defaults[key] = newValue
            CompatStore.markChanged()
        }
    }
    public var projectedValue: Binding<Value> {
        let key = self.key, fallback = defaultValue
        return Binding(get: { (CompatStore.shared.defaults[key] as? Value) ?? fallback },
                       set: { CompatStore.shared.defaults[key] = $0; CompatStore.markChanged() })
    }
}

extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Date { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == Int { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String { self.init(key: key, defaultValue: wrappedValue) }

    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Int? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Double? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == String? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == URL? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Data? { self.init(key: key, defaultValue: nil) }
    public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == Int { self.init(key: key, defaultValue: nil) }
    public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == String { self.init(key: key, defaultValue: nil) }
}

@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    let key: String
    let defaultValue: Value

    init(key: String, defaultValue: Value) {
        self.key = "scene:" + key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get { (CompatStore.shared.defaults[key] as? Value) ?? defaultValue }
        nonmutating set {
            CompatStore.shared.defaults[key] = newValue
            CompatStore.markChanged()
        }
    }
    public var projectedValue: Binding<Value> {
        let key = self.key, fallback = defaultValue
        return Binding(get: { (CompatStore.shared.defaults[key] as? Value) ?? fallback },
                       set: { CompatStore.shared.defaults[key] = $0; CompatStore.markChanged() })
    }
}

extension SceneStorage {
    public init(wrappedValue: Value, _ key: String) where Value == Bool { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Int { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Double { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == String { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == URL { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value == Data { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == Int { self.init(key: key, defaultValue: wrappedValue) }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == String { self.init(key: key, defaultValue: wrappedValue) }

    public init(_ key: String) where Value == Bool? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Int? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Double? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == String? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == URL? { self.init(key: key, defaultValue: nil) }
    public init(_ key: String) where Value == Data? { self.init(key: key, defaultValue: nil) }
}
