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
        get { storedValue(CompatStore.shared.defaults[key], defaultValue) }
        nonmutating set {
            CompatStore.shared.defaults[key] = newValue
            CompatStore.markChanged()
        }
    }
    public var projectedValue: Binding<Value> {
        let key = self.key, fallback = defaultValue
        return Binding(get: { storedValue(CompatStore.shared.defaults[key], fallback) },
                       set: { CompatStore.shared.defaults[key] = $0; CompatStore.markChanged() })
    }
}

/// A stored value as `Value`. Values from the launch arguments are strings, read as UserDefaults reads them:
/// "YES"/"true"/"1" for a Bool, numbers for Int and Double, a URL string for URL.
func storedValue<Value>(_ raw: Any?, _ fallback: Value) -> Value {
    if let value = raw as? Value { return value }
    guard let text = raw as? String else { return fallback }
    let converted: Any?
    switch fallback {
    case is Bool, is Bool?: converted = ["yes", "true", "1"].contains(text.lowercased())
    case is Int, is Int?: converted = Int(text)
    case is Double, is Double?: converted = Double(text)
    case is URL, is URL?: converted = URL(string: text)
    default: converted = nil
    }
    return (converted as? Value) ?? fallback
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
