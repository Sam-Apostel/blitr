import Foundation
// URLSession, URLRequest and friends are in a separate module on Linux; code written for Apple
// platforms expects them from `import Foundation`.
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
@_exported import Observation
#endif

// Foundation's localization API (`String(localized:)`, `String.LocalizationValue`,
// `LocalizedStringResource`) is missing from Foundation on Linux. This module supplies it. The SwiftUI
// module re-exports it, and project mode imports it implicitly into every module it compiles, so
// Foundation-only packages that call `String(localized:)` build too.
//
// Strings resolve through one table (key -> localized value) that the tool flattens from the project's
// string catalogs and `.strings` files for the chosen locale and names in BLITR_STRINGS.
// Without a table, a key is its own value, as on a device without a translation.
//
// Unlike the gap-fillers in FoundationGaps.swift, this file is not compiled out on Darwin, although Apple's
// Foundation has the same API: strings must resolve through the tool's table on every host, and the engine
// reads members Apple's types do not have (`resolved`, `defaultValue` as a String).
//
// On Darwin the types are Apple's: two `String.LocalizationValue` member types are ambiguous rather than one
// shadowing the other, and so are two identical initializers. DarwinLocalizationOverloads.swift declares
// `String(localized:)` and `AttributedString(localized:)` once per combination of optional arguments, which
// overload resolution prefers to Apple's defaulted ones, so calls resolve through the tool's table there too.

public enum ScreenshotStrings {
    public static let table: [String: String] = {
        guard let path = ProcessInfo.processInfo.environment["BLITR_STRINGS"],
              let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return object
    }()

    public static func lookup(_ key: String) -> String? { table[key] }

    /// Separates a key from a plural category in the table ("%lld trees\u{1}one").
    public static let pluralSeparator = "\u{1}"

    /// The template for a key and its arguments: for a key with plural variants, the variant for the
    /// first integer argument (`zero`, `one`, `two` when the catalog has them and the number is exactly
    /// 0, 1 or 2; `other` otherwise). Languages whose rules need `few`/`many` get `other`.
    public static func template(_ key: String, arguments: [String]) -> String? {
        guard let base = table[key] else { return nil }
        guard table[key + pluralSeparator + "other"] != nil else { return base }
        let integerArgument = placeholders(key).first { placeholder in
            let specifier = String(Array(key)[placeholder.range])
            return specifier.hasSuffix("d") || specifier.hasSuffix("u") || specifier.hasSuffix("i")
        }?.argument ?? 0
        guard integerArgument < arguments.count, let count = Int(arguments[integerArgument].filter { $0.isNumber || $0 == "-" }) else { return base }
        let category = count == 0 ? "zero" : count == 1 ? "one" : count == 2 ? "two" : "other"
        return table[key + pluralSeparator + category] ?? base
    }

    /// A format placeholder in a localized template: its argument index and its text range.
    public struct Placeholder {
        public var argument: Int
        public var range: Range<Int>
    }

    /// Finds `%@`, `%lld`, `%1$@`, ... in a template (characters, not bytes). `%%` is not a placeholder.
    public static func placeholders(_ template: String) -> [Placeholder] {
        let chars = Array(template)
        var result: [Placeholder] = []
        var next = 0
        var i = 0
        while i < chars.count {
            guard chars[i] == "%", i + 1 < chars.count else { i += 1; continue }
            if chars[i + 1] == "%" { i += 2; continue }
            var j = i + 1
            var digits = ""
            while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
            var position: Int?
            if j < chars.count, chars[j] == "$", let p = Int(digits) { position = p - 1; j += 1 } else { j = i + 1 }
            while j < chars.count, "0123456789.-+ #lhqLzjt".contains(chars[j]) { j += 1 }
            if j < chars.count, "@dDiuUxXoOfFeEgGcCsSp".contains(chars[j]) {
                let index = position ?? next
                if position == nil { next += 1 }
                result.append(Placeholder(argument: index, range: i..<(j + 1)))
                i = j + 1
            } else {
                i += 1
            }
        }
        return result
    }

    /// The template with its placeholders replaced by `arguments`, and `%%` by `%`.
    public static func format(_ template: String, _ arguments: [String]) -> String {
        let chars = Array(template)
        var out = ""
        var i = 0
        for placeholder in placeholders(template) {
            out += String(chars[i..<placeholder.range.lowerBound]).replacingOccurrences(of: "%%", with: "%")
            out += placeholder.argument < arguments.count ? arguments[placeholder.argument] : ""
            i = placeholder.range.upperBound
        }
        out += String(chars[i...]).replacingOccurrences(of: "%%", with: "%")
        return out
    }

    /// The format specifier Xcode puts in a key for an interpolated value of this type.
    public static func specifier(for value: Any) -> String {
        if value is any BinaryInteger { return "%lld" }
        if value is any BinaryFloatingPoint { return "%lf" }
        return "%@"
    }
}

#if !canImport(Darwin)
extension String {
    /// A localizable string with its interpolations, keyed as Xcode keys it ("Hello %@").
    public struct LocalizationValue: ExpressibleByStringInterpolation, Equatable, Hashable, Sendable {
        public var key: String
        public var arguments: [String]

        public init(_ value: String) { key = value.replacingOccurrences(of: "%", with: "%%"); arguments = [] }
        public init(stringLiteral value: String) { self.init(value) }
        public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }

        public struct StringInterpolation: StringInterpolationProtocol, Sendable {
            var key = ""
            var arguments: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
            public mutating func appendInterpolation(_ value: String) { key += "%@"; arguments.append(value) }
            public mutating func appendInterpolation<T: BinaryInteger>(_ value: T) { key += "%lld"; arguments.append("\(value)") }
            public mutating func appendInterpolation<T: BinaryFloatingPoint>(_ value: T) { key += "%lf"; arguments.append("\(value)") }
            public mutating func appendInterpolation<F: FormatStyle>(_ value: F.FormatInput, format: F) where F.FormatOutput == String {
                key += "%@"; arguments.append(format.format(value))
            }
            public mutating func appendInterpolation(_ value: LocalizedStringResource) { key += "%@"; arguments.append(String(localized: value)) }
            @_disfavoredOverload
            public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append("\(value)") }
        }

        /// The value from the string table, or the key itself, with the arguments filled in.
        public var resolved: String { ScreenshotStrings.format(ScreenshotStrings.template(key, arguments: arguments) ?? key, arguments) }
    }

    public init(localized value: LocalizationValue, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current,
                comment: StaticString? = nil) {
        self = value.resolved
    }

    public init(localized key: StaticString, defaultValue: LocalizationValue, table: String? = nil, bundle: Bundle? = nil,
                locale: Locale = .current, comment: StaticString? = nil) {
        let name = "\(key)"
        self = ScreenshotStrings.template(name, arguments: defaultValue.arguments).map { ScreenshotStrings.format($0, defaultValue.arguments) } ?? defaultValue.resolved
    }

    public init(localized resource: LocalizedStringResource) { self = resource.value.resolved }
}

/// A reference to a localizable string, resolved when displayed (app intents, widgets, `Text`).
public struct LocalizedStringResource: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringInterpolation {
    public typealias StringInterpolation = String.LocalizationValue.StringInterpolation
    public var value: String.LocalizationValue
    public var key: String { value.key }
    public var table: String?
    public var locale: Locale = .current
    /// The resolved text: the table's value for the key, or the key with its arguments.
    public var defaultValue: String { value.resolved }

    public init(_ value: String.LocalizationValue, table: String? = nil, locale: Locale = .current,
                bundle: BundleDescription = .main, comment: StaticString? = nil) {
        self.value = value
        self.table = table
        self.locale = locale
    }
    public init(_ key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current,
                bundle: BundleDescription = .main, comment: StaticString? = nil) {
        let name = "\(key)"
        if ScreenshotStrings.lookup(name) != nil {
            value = String.LocalizationValue(stringLiteral: name)
            value.arguments = defaultValue.arguments
        } else {
            value = defaultValue
        }
        self.table = table
        self.locale = locale
    }
    public init(stringLiteral value: String) { self.value = .init(value) }
    public init(stringInterpolation: String.LocalizationValue.StringInterpolation) { value = .init(stringInterpolation: stringInterpolation) }
    /// For types whose own literals use the default interpolation: the interpolated text is the key.
    public init(stringInterpolation: DefaultStringInterpolation) { value = .init(String(stringInterpolation: stringInterpolation)) }
    public var description: String { value.resolved }

    enum CodingKeys: String, CodingKey { case key, arguments, table }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = String.LocalizationValue(stringLiteral: "")
        value.key = try container.decode(String.self, forKey: .key)
        value.arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        table = try container.decodeIfPresent(String.self, forKey: .table)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.key, forKey: .key)
        try container.encode(value.arguments, forKey: .arguments)
        try container.encodeIfPresent(table, forKey: .table)
    }
    public static func == (a: LocalizedStringResource, b: LocalizedStringResource) -> Bool { a.value == b.value && a.table == b.table }
    public func hash(into hasher: inout Hasher) { hasher.combine(value); hasher.combine(table) }

    public enum BundleDescription: Sendable, Hashable {
        case main
        case atURL(URL)
    }
}

extension LocalizedStringResource {
    /// The resolved text (the engine's name for it on every host).
    package var _resolvedText: String { value.resolved }
    /// A resource whose key is already-interpolated text.
    package init(_verbatimKey text: String) { self.init(stringLiteral: text) }
}
#endif
