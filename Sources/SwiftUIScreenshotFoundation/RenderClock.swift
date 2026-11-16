import Foundation

// Time and network for code that runs while a frame is rendered.
//
// A render takes one frame of a screen that has just appeared. `.task` and `onAppear` work runs first,
// under a short real-time budget, so delays written with `Task.sleep` would either eat that budget or
// never finish. Here `Task.sleep` runs on a virtual clock instead: while a render drives the clock, a
// sleep that ends within the settle time (`--settle-time`, default 2 seconds) returns as soon as every
// other task is waiting too, with the clock moved on to its deadline; a sleep that ends later waits
// past the frame, as it would on a device when the screenshot is taken. Outside a render (a widget
// timeline, a plain program) the real clock is used.
//
// These `Task.sleep` overloads shadow the standard library's: this module imports Swift, and every
// module compiled against the SDK imports this one.

/// The virtual clock a render drives. Engine-facing; `@MainActor`-free so any task may sleep on it.
public final class _RenderClock: @unchecked Sendable {
    /// This module's code is in two libraries (its own, and libSwiftUIScreenshotEngine, which SwiftPM links it
    /// into), so each would have its own `static let`. The one instance is found by symbol instead: every copy
    /// asks the dynamic linker, which answers with the first library's.
    public static let shared: _RenderClock = {
        typealias Getter = @convention(c) () -> UnsafeMutableRawPointer
        // Every loaded image, in load order: a null handle on Linux, RTLD_DEFAULT ((void *)-2) on Darwin.
        #if canImport(Darwin)
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2)
        #else
        let everywhere: UnsafeMutableRawPointer? = nil
        #endif
        if let symbol = dlsym(everywhere, "swiftui_screenshot_render_clock") {
            return Unmanaged<_RenderClock>.fromOpaque(unsafeBitCast(symbol, to: Getter.self)()).takeUnretainedValue()
        }
        return localInstance
    }()
    fileprivate static let localInstance = _RenderClock()

    private struct Sleeper {
        let id: Int
        let deadline: Double
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var sleepers: [Sleeper] = []
    private var nextID = 0
    private var _isDriven = false
    private var _now: Double = 0
    private var _horizon: Double = 2

    /// True while a render drives the clock (between `begin` and `end`).
    public var isDriven: Bool { lock.withLock { _isDriven } }
    /// Virtual seconds since the render began.
    public var now: Double { lock.withLock { _now } }
    /// Sleeps that end at or before this virtual time return before the frame is taken.
    public var horizon: Double {
        get { lock.withLock { _horizon } }
        set { lock.withLock { _horizon = newValue } }
    }
    /// Number of tasks parked in a virtual sleep.
    public var sleeping: Int { lock.withLock { sleepers.count } }

    public func begin(settleTime: Double) {
        lock.withLock {
            _isDriven = true
            _now = 0
            _horizon = settleTime
        }
    }

    /// Stops driving the clock; parked sleepers are cancelled so their tasks can end.
    public func end() {
        let parked = lock.withLock { () -> [Sleeper] in
            _isDriven = false
            defer { sleepers = [] }
            return sleepers
        }
        for sleeper in parked { sleeper.continuation.resume(throwing: CancellationError()) }
    }

    /// Moves the clock to the earliest deadline within the horizon and wakes the sleepers due then.
    /// Returns false when no sleeper is due.
    public func advance() -> Bool {
        let due = lock.withLock { () -> [Sleeper] in
            guard let next = sleepers.map(\.deadline).min(), next <= _horizon else { return [] }
            _now = max(_now, next)
            let ready = sleepers.filter { $0.deadline <= _now }
            sleepers.removeAll { $0.deadline <= _now }
            return ready
        }
        for sleeper in due { sleeper.continuation.resume() }
        return !due.isEmpty
    }

    func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        guard isDriven else {
            let clock = ContinuousClock()
            // With `tolerance:` this is the standard library's sleep, not the overload below.
            try await clock.sleep(until: clock.now + .nanoseconds(Int64(max(0, seconds) * 1e9)), tolerance: nil)
            return
        }
        let id = lock.withLock { () -> Int in nextID += 1; return nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    sleepers.append(Sleeper(id: id, deadline: _now + max(0, seconds), continuation: continuation))
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }
}

@_cdecl("swiftui_screenshot_render_clock")
public func _renderClockInstance() -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(_RenderClock.localInstance).toOpaque()
}

private func seconds(_ duration: Duration) -> Double {
    let c = duration.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

extension Task where Success == Never, Failure == Never {
    public static func sleep(nanoseconds duration: UInt64) async throws {
        try await _RenderClock.shared.sleep(seconds: Double(duration) / 1e9)
    }
    public static func sleep(for duration: Duration, tolerance: Duration? = nil) async throws {
        try await _RenderClock.shared.sleep(seconds: seconds(duration))
    }
    public static func sleep<C: Clock>(for duration: C.Instant.Duration, tolerance: C.Instant.Duration? = nil,
                                       clock: C) async throws {
        if let d = duration as? Duration {
            try await _RenderClock.shared.sleep(seconds: seconds(d))
        } else {
            try await clock.sleep(for: duration, tolerance: tolerance)
        }
    }
    public static func sleep<C: Clock>(until deadline: C.Instant, tolerance: C.Instant.Duration? = nil,
                                       clock: C = ContinuousClock()) async throws {
        if let d = clock.now.duration(to: deadline) as? Duration {
            try await _RenderClock.shared.sleep(seconds: seconds(d))
        } else {
            try await clock.sleep(until: deadline, tolerance: tolerance)
        }
    }
}

// `clock.sleep(for:)` and `clock.sleep(until:)` called on a clock directly. The standard library's take a
// defaulted `tolerance:`, so these, which take none, are chosen for calls that pass none; a call that passes
// a tolerance, or a sleep through a generic `Clock`, keeps real time.
extension ContinuousClock {
    public func sleep(for duration: Duration) async throws {
        try await _RenderClock.shared.sleep(seconds: seconds(duration))
    }
    public func sleep(until deadline: Instant) async throws {
        try await _RenderClock.shared.sleep(seconds: seconds(now.duration(to: deadline)))
    }
}
extension SuspendingClock {
    public func sleep(for duration: Duration) async throws {
        try await _RenderClock.shared.sleep(seconds: seconds(duration))
    }
    public func sleep(until deadline: Instant) async throws {
        try await _RenderClock.shared.sleep(seconds: seconds(now.duration(to: deadline)))
    }
}

// MARK: - Network

/// Renders run offline. A `.task` that loads from a server would otherwise wait on the network (or on a
/// server that is not running here) until the task timeout, and the frame would show a half-loaded
/// screen; offline, the request fails at once and the screen shows its offline or error state, as on a
/// device without a connection. `--allow-network` turns this off.
public enum _RenderNetwork {
    public static func goOffline() {
        // `URLSession.shared` (and sessions whose configuration lists registered protocols) fail with
        // `URLError(.notConnectedToInternet)`.
        URLProtocol.registerClass(OfflineURLProtocol.self)
        #if canImport(Darwin)
        // On Darwin a session with its own configuration consults only that configuration's protocols, and
        // ignores the proxy variables: every `.default` and `.ephemeral` configuration gets the offline
        // protocol first.
        OfflineConfigurations.install()
        #endif
        // On Linux, sessions with their own configuration go through libcurl, which honours the proxy
        // variables: a proxy on a closed local port refuses every connection at once.
        let refused = "http://127.0.0.1:9"
        for name in ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            setenv(name, refused, 1)
        }
        unsetenv("no_proxy")
        unsetenv("NO_PROXY")
    }
}

final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return ["http", "https", "ws", "wss"].contains(scheme)
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline.",
        ]))
    }
    override func stopLoading() {}
}

#if canImport(Darwin)
import ObjectiveC

enum OfflineConfigurations {
    nonisolated(unsafe) private static var swizzled = false
    /// Protocols put first in every `.default` and `.ephemeral` configuration, in order.
    nonisolated(unsafe) private static var classes: [AnyClass] = []

    /// Puts `protocolClass` ahead of the others in every new default and ephemeral configuration.
    static func install(first protocolClass: AnyClass = OfflineURLProtocol.self) {
        if !classes.contains(where: { $0 == protocolClass }) {
            // The image cache answers before the offline protocol refuses.
            if protocolClass == OfflineURLProtocol.self { classes.append(protocolClass) } else { classes.insert(protocolClass, at: 0) }
        }
        guard !swizzled else { return }
        swizzled = true
        for name in ["defaultSessionConfiguration", "ephemeralSessionConfiguration"] {
            let selector = NSSelectorFromString(name)
            guard let method = class_getClassMethod(URLSessionConfiguration.self, selector) else { continue }
            typealias Getter = @convention(c) (AnyClass, Selector) -> URLSessionConfiguration
            let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            let replacement: @convention(block) (AnyClass) -> URLSessionConfiguration = { cls in
                let configuration = original(cls, selector)
                configuration.protocolClasses = OfflineConfigurations.classes + (configuration.protocolClasses ?? [])
                return configuration
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
    }
}
#endif
