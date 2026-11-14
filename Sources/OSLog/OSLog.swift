// `import OSLog`: the os logging API, plus reading the log store (which is empty here).
@_exported import os

public final class OSLogStore: @unchecked Sendable {
    public enum Scope: Sendable { case system, currentProcessIdentifier }
    public static func local() throws -> OSLogStore { OSLogStore() }
    public convenience init(scope: Scope) throws { self.init() }
    public convenience init(url: URL) throws { self.init() }
    init() {}
    public func position(date: Date) -> OSLogPosition { OSLogPosition() }
    public func position(timeIntervalSinceEnd: TimeInterval) -> OSLogPosition { OSLogPosition() }
    public func position(timeIntervalSinceLatestBoot: TimeInterval) -> OSLogPosition { OSLogPosition() }
    public func getEntries(with options: OSLogEnumerator.Options = [], at position: OSLogPosition? = nil,
                           matching predicate: NSPredicate? = nil) throws -> AnySequence<OSLogEntry> { AnySequence([]) }
}
public final class OSLogPosition: @unchecked Sendable {}
public class OSLogEntry: @unchecked Sendable {
    public var composedMessage: String { "" }
    public var date: Date { Date() }
}
public class OSLogEntryLog: OSLogEntry {
    public enum Level: Int, Sendable { case undefined, debug, info, notice, error, fault }
    public var level: Level { .undefined }
    public var subsystem: String { "" }
    public var category: String { "" }
}
public enum OSLogEnumerator {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let reverse = Options(rawValue: 1)
    }
}
