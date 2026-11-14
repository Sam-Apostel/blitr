import Foundation

// Signposts mark intervals for Instruments; there is no trace to record into, so they do nothing
// (the work an interval wraps still runs).

public struct OSSignpostID: Comparable, Hashable, Sendable {
    public let rawValue: UInt64
    public init(_ value: UInt64) { rawValue = value }
    public init(log: OSLog) { rawValue = OSSignpostID.next() }
    public init(log: OSLog, object: AnyObject) { rawValue = UInt64(UInt(bitPattern: ObjectIdentifier(object).hashValue)) }
    public static let exclusive = OSSignpostID(0xEEEE_B0B5_B2B2_EEEE)
    public static let invalid = OSSignpostID(~0)
    public static let null = OSSignpostID(0)
    public static func < (a: OSSignpostID, b: OSSignpostID) -> Bool { a.rawValue < b.rawValue }

    private static let counter = Counter()
    private final class Counter: @unchecked Sendable {
        let lock = NSLock()
        var value: UInt64 = 1
    }
    static func next() -> UInt64 {
        counter.lock.lock()
        defer { counter.lock.unlock() }
        counter.value += 1
        return counter.value
    }
}

public struct OSSignpostType: Equatable, RawRepresentable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let event = OSSignpostType(rawValue: 0)
    public static let begin = OSSignpostType(rawValue: 1)
    public static let end = OSSignpostType(rawValue: 2)
}

public struct OSSignpostIntervalState: Codable, Sendable {
    public let signpostID: OSSignpostID.RawValue
    init(_ id: OSSignpostID) { signpostID = id.rawValue }
    public static func beginState(id: OSSignpostID) -> OSSignpostIntervalState { OSSignpostIntervalState(id) }
}
extension OSSignpostID { public typealias RawValue = UInt64 }

public struct OSSignposter: @unchecked Sendable {
    let log: OSLog
    public init() { log = .disabled }
    public init(subsystem: String, category: String) { log = OSLog(subsystem: subsystem, category: category) }
    public init(subsystem: String, category: OSLog.Category) { log = OSLog(subsystem: subsystem, category: category) }
    public init(logger: Logger) { log = OSLog(subsystem: logger.subsystem, category: logger.category) }
    public init(logHandle: OSLog) { log = logHandle }
    public static let disabled = OSSignposter(logHandle: .disabled)

    public var isEnabled: Bool { false }
    public func makeSignpostID() -> OSSignpostID { OSSignpostID(log: log) }
    public func makeSignpostID(from object: AnyObject) -> OSSignpostID { OSSignpostID(log: log, object: object) }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {}
    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) {}
    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState { .beginState(id: id) }
    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) -> OSSignpostIntervalState { .beginState(id: id) }
    public func beginAnimationInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState { .beginState(id: id) }
    public func beginAnimationInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) -> OSSignpostIntervalState { .beginState(id: id) }
    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {}
    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: OSLogMessage) {}
    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive, around task: () throws -> T) rethrows -> T { try task() }
    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage,
                                        around task: () throws -> T) rethrows -> T { try task() }
}

public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer? = nil, log: OSLog, name: StaticString, signpostID: OSSignpostID = .exclusive) {}
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer? = nil, log: OSLog, name: StaticString, signpostID: OSSignpostID = .exclusive,
                        _ format: StaticString, _ arguments: CVarArg...) {}
