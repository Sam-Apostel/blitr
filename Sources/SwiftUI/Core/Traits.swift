// Per-node metadata: traits flow from a view to its container, preferences flow up the tree.

protocol TraitKey {
    associatedtype Value
}

struct Traits {
    private var storage: [ObjectIdentifier: Any] = [:]
    subscript<K: TraitKey>(key: K.Type) -> K.Value? {
        get { storage[ObjectIdentifier(key)] as? K.Value }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

enum IDTraitKey: TraitKey { typealias Value = AnyHashable }
enum TagTraitKey: TraitKey { typealias Value = AnyHashable }
enum LayoutPriorityTraitKey: TraitKey { typealias Value = Double }
enum ZIndexTraitKey: TraitKey { typealias Value = Double }

/// Sets a trait on every view the modifier is applied to, without adding a node.
struct TraitModifier<K: TraitKey>: ViewModifier, PrimitiveModifier {
    let value: K.Value
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) {
            node.traits[K.self] = value
            out.append(node)
        }
    }
}

extension View {
    func trait<K: TraitKey>(_ key: K.Type, _ value: K.Value) -> ModifiedContent<Self, TraitModifier<K>> {
        modifier(TraitModifier<K>(value: value))
    }
    public func layoutPriority(_ value: Double) -> some View { trait(LayoutPriorityTraitKey.self, value) }
    public func zIndex(_ value: Double) -> some View { trait(ZIndexTraitKey.self, value) }
    public func tag<V: Hashable>(_ tag: V, includeOptional: Bool = true) -> some View { trait(TagTraitKey.self, AnyHashable(tag)) }
    public func id<ID: Hashable>(_ id: ID) -> some View { trait(IDTraitKey.self, AnyHashable(id)) }
}

// MARK: - Preferences

public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey where Value: ExpressibleByNilLiteral {
    public static var defaultValue: Value { nil }
}

struct PreferenceStore {
    struct Entry {
        var value: Any
        let merge: (Any, Any) -> Any
    }
    var entries: [ObjectIdentifier: Entry] = [:]

    subscript<K: PreferenceKey>(key: K.Type) -> K.Value {
        get { (entries[ObjectIdentifier(key)]?.value as? K.Value) ?? K.defaultValue }
    }
    func has<K: PreferenceKey>(_ key: K.Type) -> Bool { entries[ObjectIdentifier(key)] != nil }

    mutating func set<K: PreferenceKey>(_ key: K.Type, _ value: K.Value) {
        entries[ObjectIdentifier(key)] = Entry(value: value, merge: { a, b in
            var result = a as! K.Value
            K.reduce(value: &result) { b as! K.Value }
            return result
        })
    }
    mutating func remove<K: PreferenceKey>(_ key: K.Type) { entries[ObjectIdentifier(key)] = nil }

    /// Combines a later sibling's preferences into this store (document order).
    mutating func merge(_ other: PreferenceStore) {
        for (id, entry) in other.entries {
            if let mine = entries[id] {
                entries[id] = Entry(value: mine.merge(mine.value, entry.value), merge: mine.merge)
            } else {
                entries[id] = entry
            }
        }
    }
}

struct PreferenceWritingModifier<K: PreferenceKey>: ViewModifier, PrimitiveModifier {
    let value: K.Value
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) {
            node.preferences.set(K.self, value)
            out.append(node)
        }
    }
}

struct PreferenceTransformModifier<K: PreferenceKey>: ViewModifier, PrimitiveModifier {
    let transform: (inout K.Value) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) {
            var value = node.preferences[K.self]
            transform(&value)
            node.preferences.set(K.self, value)
            out.append(node)
        }
    }
}

extension View {
    public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        modifier(PreferenceWritingModifier<K>(value: value))
    }
    public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void) -> some View {
        modifier(PreferenceTransformModifier<K>(transform: callback))
    }
}
