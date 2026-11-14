import Foundation

// MARK: - os_unfair_lock (C API)

/// `os_unfair_lock` values are used through pointers to them; each address gets a real mutex.
public struct os_unfair_lock_s: @unchecked Sendable {
    public var _os_unfair_lock_opaque: UInt32
    public init() { _os_unfair_lock_opaque = 0 }
    public init(_os_unfair_lock_opaque: UInt32) { self._os_unfair_lock_opaque = _os_unfair_lock_opaque }
}
public typealias os_unfair_lock = os_unfair_lock_s
public typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock_s>

private final class UnfairLockTable: @unchecked Sendable {
    static let shared = UnfairLockTable()
    private let guardLock = NSLock()
    private var locks: [UnsafeMutableRawPointer: NSLock] = [:]
    func lock(for pointer: UnsafeMutableRawPointer) -> NSLock {
        guardLock.lock()
        defer { guardLock.unlock() }
        if let lock = locks[pointer] { return lock }
        let lock = NSLock()
        locks[pointer] = lock
        return lock
    }
}

public func os_unfair_lock_lock(_ lock: os_unfair_lock_t) { UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).lock() }
public func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) { UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).unlock() }
public func os_unfair_lock_trylock(_ lock: os_unfair_lock_t) -> Bool { UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).try() }
public func os_unfair_lock_assert_owner(_ lock: os_unfair_lock_t) {}
public func os_unfair_lock_assert_not_owner(_ lock: os_unfair_lock_t) {}

// MARK: - OSAllocatedUnfairLock

public struct OSAllocatedUnfairLock<State>: @unchecked Sendable {
    public enum Ownership: Hashable, Sendable { case owner, notOwner }

    private final class Storage {
        let lock = NSLock()
        var state: State
        init(_ state: State) { self.state = state }
    }
    private let storage: Storage

    public init(uncheckedState initialState: State) { storage = Storage(initialState) }
    public init(initialState: State) { storage = Storage(initialState) }

    public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return try body(&storage.state)
    }
    public func withLock<R>(_ body: @Sendable (inout State) throws -> R) rethrows -> R where R: Sendable {
        try withLockUnchecked(body)
    }
    public func withLockIfAvailableUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R? {
        guard storage.lock.try() else { return nil }
        defer { storage.lock.unlock() }
        return try body(&storage.state)
    }
    public func withLockIfAvailable<R>(_ body: @Sendable (inout State) throws -> R) rethrows -> R? where R: Sendable {
        try withLockIfAvailableUnchecked(body)
    }
    public func precondition(_ condition: Ownership) {}
}

extension OSAllocatedUnfairLock where State == () {
    public init() { self.init(uncheckedState: ()) }
    public func lock() { storage.lock.lock() }
    public func unlock() { storage.lock.unlock() }
    public func lockIfAvailable() -> Bool { storage.lock.try() }
    public func withLockUnchecked<R>(_ body: () throws -> R) rethrows -> R {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return try body()
    }
    public func withLock<R>(_ body: @Sendable () throws -> R) rethrows -> R where R: Sendable { try withLockUnchecked(body) }
}
