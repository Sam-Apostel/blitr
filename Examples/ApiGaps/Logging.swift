import SwiftUI
import os.log
import OSLog

// The os module: Logger with OSLogMessage interpolation options, os_log, signposts and unfair locks.
// Log output is dropped; the locks are real.

extension Logger {
    static let appState = Logger(subsystem: "app.example", category: "AppState")
    static let network = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Network")
}

final class Counter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private var legacyLock = os_unfair_lock()
    private var legacyCount = 0

    func increment() -> Int {
        os_unfair_lock_lock(&legacyLock)
        legacyCount += 1
        os_unfair_lock_unlock(&legacyLock)
        return lock.withLock { value in
            value += 1
            return value
        }
    }
}

struct LoggingExample: View {
    private let signposter = OSSignposter(logger: .network)
    private let counter = Counter()
    @State private var count = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Logged \(count) messages").font(.title3)
            Text("Messages are formatted lazily and dropped").font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear {
            let user = "sam"
            let id = signposter.makeSignpostID()
            let state = signposter.beginInterval("load", id: id, "start \(user, privacy: .private)")
            Logger.appState.trace("\(UInt(42), format: .hex(includePrefix: true)) \(3.14159, format: .fixed(precision: 2)) [\("left", align: .left(columns: 6))]")
            Logger.appState.debug("User \(user, privacy: .public) opened the app")
            Logger.appState.info("Count \(count, format: .decimal(minDigits: 3), align: .right(columns: 5))")
            Logger.network.error("Failed: \(URLError(.timedOut).localizedDescription, privacy: .private(mask: .hash))")
            Logger.network.log(level: .fault, "Flag \(true, format: .answer), type \(String.self)")
            Logger().notice("Ratio \(Float(0.5), format: .exponential(precision: 1), privacy: .sensitive)")
            os_log("Legacy %{public}@ %d", log: .default, type: .info, user, 3)
            os_log(.error, log: OSLog(subsystem: "app", category: .pointsOfInterest), "Typed \(user)")
            os_signpost(.event, log: .default, name: "tick")
            signposter.emitEvent("tick")
            signposter.endInterval("load", state)
            count = signposter.withIntervalSignpost("count") { counter.increment() }
        }
    }
}

#Preview("os logging") {
    LoggingExample()
}
