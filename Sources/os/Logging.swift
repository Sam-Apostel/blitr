import Foundation

// MARK: - Levels and handles

public struct OSLogType: Equatable, RawRepresentable, Sendable {
    public let rawValue: UInt8
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let `default` = OSLogType(0x00)
    public static let info = OSLogType(0x01)
    public static let debug = OSLogType(0x02)
    public static let error = OSLogType(0x10)
    public static let fault = OSLogType(0x11)
}

public final class OSLog: @unchecked Sendable {
    public struct Category: Sendable {
        let name: String
        public init(rawValue: String) { name = rawValue }
        public static let pointsOfInterest = Category(rawValue: "PointsOfInterest")
        public static let dynamicTracing = Category(rawValue: "DynamicTracing")
        public static let dynamicStackTracing = Category(rawValue: "DynamicStackTracing")
    }
    public let subsystem: String
    public let category: String
    let enabled: Bool

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        enabled = true
    }
    public convenience init(subsystem: String, category: OSLog.Category) { self.init(subsystem: subsystem, category: category.name) }
    private init(disabled: Void) { subsystem = ""; category = ""; enabled = false }

    public static let `default` = OSLog(subsystem: "", category: "")
    public static let disabled = OSLog(disabled: ())
    public func isEnabled(type: OSLogType) -> Bool { enabled }
    public var signpostsEnabled: Bool { false }
}

// MARK: - Messages

public struct OSLogPrivacy: Equatable, Sendable {
    public enum Mask: Equatable, Sendable { case hash, none }
    let kind: Int
    let mask: Mask
    public static let `public` = OSLogPrivacy(kind: 0, mask: .none)
    public static let `private` = OSLogPrivacy(kind: 1, mask: .none)
    public static let sensitive = OSLogPrivacy(kind: 2, mask: .none)
    public static let auto = OSLogPrivacy(kind: 3, mask: .none)
    public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 1, mask: mask) }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 2, mask: mask) }
    public static func auto(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 3, mask: mask) }
}

public struct OSLogStringAlignment: Sendable {
    let columns: Int
    public static let none = OSLogStringAlignment(columns: 0)
    public static func left(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment(columns: -columns()) }
    public static func right(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment(columns: columns()) }

    func apply(_ s: String) -> String {
        let pad = String(repeating: " ", count: max(0, abs(columns) - s.count))
        return columns < 0 ? s + pad : pad + s
    }
}

public struct OSLogIntegerFormatting: Sendable {
    let radix: Int
    let explicitPositiveSign: Bool
    let includePrefix: Bool
    let uppercase: Bool
    let minDigits: Int
    public static let decimal = OSLogIntegerFormatting(radix: 10, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)
    public static let hex = OSLogIntegerFormatting(radix: 16, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)
    public static let octal = OSLogIntegerFormatting(radix: 8, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)
    public static func decimal(explicitPositiveSign: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 10, explicitPositiveSign: explicitPositiveSign, includePrefix: false, uppercase: false, minDigits: minDigits())
    }
    public static func decimal(explicitPositiveSign: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 10, explicitPositiveSign: explicitPositiveSign, includePrefix: false, uppercase: false, minDigits: 0)
    }
    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false,
                           minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 16, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits())
    }
    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 16, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: 0)
    }
    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false,
                             minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 8, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits())
    }
    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 8, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: 0)
    }

    func format<T: BinaryInteger>(_ value: T) -> String {
        var digits = String(value.magnitude, radix: radix, uppercase: uppercase)
        if digits.count < minDigits { digits = String(repeating: "0", count: minDigits - digits.count) + digits }
        if includePrefix { digits = (radix == 16 ? "0x" : radix == 8 ? "0o" : "") + digits }
        let sign = value < 0 ? "-" : explicitPositiveSign ? "+" : ""
        return sign + digits
    }
}

public struct OSLogFloatFormatting: Sendable {
    enum Kind: Sendable { case fixed, hex, exponential, hybrid }
    let kind: Kind
    let precision: Int?
    let explicitPositiveSign: Bool
    let uppercase: Bool
    public static let fixed = OSLogFloatFormatting(kind: .fixed, precision: nil, explicitPositiveSign: false, uppercase: false)
    public static let hex = OSLogFloatFormatting(kind: .hex, precision: nil, explicitPositiveSign: false, uppercase: false)
    public static let exponential = OSLogFloatFormatting(kind: .exponential, precision: nil, explicitPositiveSign: false, uppercase: false)
    public static let hybrid = OSLogFloatFormatting(kind: .hybrid, precision: nil, explicitPositiveSign: false, uppercase: false)
    public static func fixed(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .fixed, precision: precision(), explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func fixed(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .fixed, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func hex(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .hex, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func exponential(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .exponential, precision: precision(), explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func exponential(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .exponential, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func hybrid(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .hybrid, precision: precision(), explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func hybrid(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(kind: .hybrid, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }

    func format(_ value: Double) -> String {
        let spec: String
        switch kind {
        case .fixed: spec = "f"
        case .hex: spec = "a"
        case .exponential: spec = "e"
        case .hybrid: spec = "g"
        }
        let p = precision.map { ".\($0)" } ?? ""
        let s = String(format: "%\(explicitPositiveSign ? "+" : "")\(p)\(uppercase ? spec.uppercased() : spec)", value)
        return s
    }
}

public enum OSLogBoolFormat: Sendable { case truth, answer }
public enum OSLogPointerFormat: Sendable { case none, ipv6Address, sockaddr }
public enum OSLogInt32ExtendedFormat: Sendable { case ipv4Address, secondsSince1970, darwinErrno, darwinMode, darwinSignal, bitrate, bitrateIEC, byteCount, byteCountIEC, truncatedByteCount, truncatedByteCountIEC }
public enum OSLogInt64DisplayFormat: Sendable { case ipv4Address, secondsSince1970, darwinErrno, darwinMode, darwinSignal, bitrate, bitrateIEC, byteCount, byteCountIEC, truncatedByteCount, truncatedByteCountIEC }

/// A log message. Arguments are only evaluated when the message is formatted, as with the real logger.
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol, @unchecked Sendable {
        var parts: [() -> String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { parts.reserveCapacity(interpolationCount * 2 + 1) }
        public mutating func appendLiteral(_ literal: String) { parts.append { literal } }

        public mutating func appendInterpolation<T: BinaryInteger>(_ number: @autoclosure @escaping () -> T, format: OSLogIntegerFormatting = .decimal,
                                                                  align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(format.format(number())) }
        }
        public mutating func appendInterpolation<T: BinaryInteger>(_ number: @autoclosure @escaping () -> T, format: OSLogInt32ExtendedFormat,
                                                                  privacy: OSLogPrivacy = .auto) {
            parts.append { "\(number())" }
        }
        public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed,
                                                 align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(format.format(number())) }
        }
        public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed,
                                                 align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(format.format(Double(number()))) }
        }
        public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> CGFloat, format: OSLogFloatFormatting = .fixed,
                                                 align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(format.format(Double(number()))) }
        }
        public mutating func appendInterpolation(_ boolean: @autoclosure @escaping () -> Bool, format: OSLogBoolFormat = .truth,
                                                 privacy: OSLogPrivacy = .auto) {
            parts.append { let b = boolean(); return format == .answer ? (b ? "YES" : "NO") : (b ? "true" : "false") }
        }
        public mutating func appendInterpolation(_ argumentString: @autoclosure @escaping () -> String, align: OSLogStringAlignment = .none,
                                                 privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(argumentString()) }
        }
        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: @autoclosure @escaping () -> T, align: OSLogStringAlignment = .none,
                                                                            privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(value().description) }
        }
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> NSObject, privacy: OSLogPrivacy = .auto) {
            parts.append { value().description }
        }
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Any.Type, align: OSLogStringAlignment = .none,
                                                 privacy: OSLogPrivacy = .auto) {
            parts.append { align.apply(String(describing: value())) }
        }
        public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawPointer, format: OSLogPointerFormat = .none,
                                                 privacy: OSLogPrivacy = .auto) {
            parts.append { "\(pointer())" }
        }
    }

    let interpolation: StringInterpolation
    public init(stringInterpolation: StringInterpolation) { interpolation = stringInterpolation }
    public init(stringLiteral value: String) {
        var i = StringInterpolation(literalCapacity: value.count, interpolationCount: 0)
        i.appendLiteral(value)
        interpolation = i
    }

    /// The text the message would log.
    var formatted: String { interpolation.parts.map { $0() }.joined() }
}

// MARK: - Logger

public struct Logger: @unchecked Sendable {
    public let subsystem: String
    public let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
    public init() { self.init(subsystem: "", category: "") }
    public init(_ logObj: OSLog) { self.init(subsystem: logObj.subsystem, category: logObj.category) }

    /// The message is dropped; nothing is evaluated (as for a level that is not being collected).
    public func log(_ message: OSLogMessage) {}
    public func log(level: OSLogType, _ message: OSLogMessage) {}
    public func trace(_ message: OSLogMessage) {}
    public func debug(_ message: OSLogMessage) {}
    public func info(_ message: OSLogMessage) {}
    public func notice(_ message: OSLogMessage) {}
    public func warning(_ message: OSLogMessage) {}
    public func error(_ message: OSLogMessage) {}
    public func critical(_ message: OSLogMessage) {}
    public func fault(_ message: OSLogMessage) {}
}

// MARK: - os_log

public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = nil, log: OSLog = .default, type: OSLogType = .default, _ args: CVarArg...) {}
public func os_log(_ type: OSLogType, dso: UnsafeRawPointer? = nil, log: OSLog = .default, _ message: StaticString, _ args: CVarArg...) {}
@_disfavoredOverload
public func os_log(_ type: OSLogType, log: OSLog = .default, _ message: OSLogMessage) {}
@_disfavoredOverload
public func os_log(log: OSLog = .default, _ message: OSLogMessage) {}
