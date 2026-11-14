@_exported import Foundation

// The slice of the Objective-C runtime that Swift app code touches: selectors (the preprocessor
// turns `#selector(...)` into `Selector("...")` and drops `@objc`), associated objects over a side
// table, and the method-swizzling entry points as functions that report "nothing there".

public struct Selector: Hashable, ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { name = value }
    public var description: String { name }
}

public func NSSelectorFromString(_ name: String) -> Selector { Selector(name) }
public func NSStringFromSelector(_ selector: Selector) -> String { selector.name }

extension NSObject {
    /// Nothing is dispatched by selector here, so nothing responds to one.
    public func responds(to selector: Selector?) -> Bool { false }
    public func perform(_ selector: Selector?) {}
    public func perform(_ selector: Selector?, with object: Any?) {}
    public func perform(_ selector: Selector, with object: Any?, afterDelay delay: TimeInterval) {}
    public func performSelector(onMainThread selector: Selector, with object: Any?, waitUntilDone: Bool) {}
    public func method(for selector: Selector?) -> IMP? { nil }
    public class func instancesRespond(to selector: Selector?) -> Bool { false }
    public class func cancelPreviousPerformRequests(withTarget target: Any) {}
    public class func cancelPreviousPerformRequests(withTarget target: Any, selector: Selector, object: Any?) {}
}

// MARK: - Associated objects

public enum objc_AssociationPolicy: UInt, Sendable {
    case OBJC_ASSOCIATION_ASSIGN = 0
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    case OBJC_ASSOCIATION_RETAIN = 769
    case OBJC_ASSOCIATION_COPY = 771
}

private final class AssociationTable: @unchecked Sendable {
    static let shared = AssociationTable()
    private let lock = NSLock()
    private struct Key: Hashable { var object: ObjectIdentifier; var key: UnsafeRawPointer }
    private final class Entry {
        weak var owner: AnyObject?
        var value: Any?
        weak var weakValue: AnyObject?
        init(owner: AnyObject) { self.owner = owner }
    }
    private var entries: [Key: Entry] = [:]

    func set(_ object: AnyObject, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy) {
        lock.lock(); defer { lock.unlock() }
        // Owners are not observed when they die, so drop what they left behind as we go.
        if entries.count > 256 { entries = entries.filter { $0.value.owner != nil } }
        let k = Key(object: ObjectIdentifier(object), key: key)
        guard let value else { entries[k] = nil; return }
        let entry = Entry(owner: object)
        if policy == .OBJC_ASSOCIATION_ASSIGN { entry.weakValue = value as AnyObject } else { entry.value = value }
        entries[k] = entry
    }
    func get(_ object: AnyObject, _ key: UnsafeRawPointer) -> Any? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[Key(object: ObjectIdentifier(object), key: key)], entry.owner === object else { return nil }
        return entry.value ?? entry.weakValue
    }
    func removeAll(_ object: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        entries = entries.filter { $0.key.object != ObjectIdentifier(object) }
    }
}

public func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy) {
    AssociationTable.shared.set(object as AnyObject, key, value, policy)
}
public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? {
    AssociationTable.shared.get(object as AnyObject, key)
}
public func objc_removeAssociatedObjects(_ object: Any) { AssociationTable.shared.removeAll(object as AnyObject) }

// MARK: - Classes and methods (nothing to swizzle)

public typealias IMP = OpaquePointer
public typealias Method = OpaquePointer

public func object_getClass(_ object: Any?) -> AnyClass? { object.map { type(of: $0 as AnyObject) } }
public func class_getInstanceMethod(_ cls: AnyClass?, _ name: Selector) -> Method? { nil }
public func class_getClassMethod(_ cls: AnyClass?, _ name: Selector) -> Method? { nil }
public func method_getImplementation(_ m: Method) -> IMP { m }
public func method_getTypeEncoding(_ m: Method) -> UnsafePointer<CChar>? { nil }
public func method_exchangeImplementations(_ m1: Method, _ m2: Method) {}
@discardableResult public func method_setImplementation(_ m: Method, _ imp: IMP) -> IMP { imp }
@discardableResult public func class_addMethod(_ cls: AnyClass?, _ name: Selector, _ imp: IMP, _ types: UnsafePointer<CChar>?) -> Bool { false }
@discardableResult public func class_replaceMethod(_ cls: AnyClass?, _ name: Selector, _ imp: IMP, _ types: UnsafePointer<CChar>?) -> IMP? { nil }
public func class_getName(_ cls: AnyClass?) -> UnsafePointer<CChar> { UnsafePointer(strdup(cls.map { String(reflecting: $0) } ?? "nil")) }
public func class_getSuperclass(_ cls: AnyClass?) -> AnyClass? { nil }
public func object_setClass(_ object: Any?, _ cls: AnyClass) -> AnyClass? { nil }
public func objc_getClass(_ name: UnsafePointer<CChar>) -> Any? { nil }
/// Blocks are plain closures here; the result is an opaque token no method can be given.
public func imp_implementationWithBlock(_ block: Any) -> IMP { OpaquePointer(bitPattern: 1)! }
@discardableResult public func imp_removeBlock(_ imp: IMP) -> Bool { false }

/// `autoreleasepool` exists for source compatibility: there is no autorelease pool to drain.
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result { try body() }
