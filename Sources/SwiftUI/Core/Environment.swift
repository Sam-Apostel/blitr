import Observation

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues: CustomStringConvertible {
    private var storage: [ObjectIdentifier: Any] = [:]
    private var objects: [ObjectIdentifier: AnyObject] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    public subscript<T: AnyObject & Observable>(type: T.Type) -> T? {
        get { objects[ObjectIdentifier(type)] as? T }
        set { objects[ObjectIdentifier(type)] = newValue }
    }

    subscript(object type: Any.Type) -> AnyObject? {
        get { objects[ObjectIdentifier(type)] }
        set { objects[ObjectIdentifier(type)] = newValue }
    }

    public var description: String { "EnvironmentValues(\(storage.count) values)" }
}

@propertyWrapper
public struct Environment<Value>: DynamicProperty, InstallableProperty {
    enum Source {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case lookup((EnvironmentValues) -> Value)
    }
    final class Box { var env: EnvironmentValues? }
    let source: Source
    let box = Box()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { source = .keyPath(keyPath) }

    public init(_ objectType: Value.Type) where Value: AnyObject & Observable {
        source = .lookup { env in
            guard let object = env[objectType] else {
                fatalError("No Observable object of type \(objectType) found. A View.environment(_:) for \(objectType) may be missing as an ancestor of this view.")
            }
            return object
        }
    }

    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        source = .lookup { $0[objectType] }
    }

    public var wrappedValue: Value {
        let env = box.env ?? EnvironmentValues()
        switch source {
        case .keyPath(let keyPath): return env[keyPath: keyPath]
        case .lookup(let lookup): return lookup(env)
        }
    }

    func install(_ ic: inout InstallContext) { box.env = ic.ctx.env }
}

// MARK: - Environment modifiers

struct EnvironmentWritingModifier: ViewModifier, PrimitiveModifier {
    let write: (inout EnvironmentValues) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        content.resolve(ctx.with(write), into: &out)
    }
}

extension View {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        modifier(EnvironmentWritingModifier { $0[keyPath: keyPath] = value })
    }
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        modifier(EnvironmentWritingModifier { $0[T.self] = object })
    }
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        modifier(EnvironmentWritingModifier { transform(&$0[keyPath: keyPath]) })
    }
    /// Internal shorthand used by the many modifiers that only write the environment.
    func env(_ write: @escaping (inout EnvironmentValues) -> Void) -> ModifiedContent<Self, EnvironmentWritingModifier> {
        modifier(EnvironmentWritingModifier(write: write))
    }
}
