#if canImport(Darwin)
import Foundation

// Foundation's localization API on Darwin: Apple's types, resolved through the tool's string table
// (ScreenshotStrings) instead of the runner's main bundle. The initializers that take precedence over Apple's
// are generated into DarwinLocalizationOverloads.swift (see scripts/generate-darwin-localization.py).

extension String.LocalizationValue {
    /// The key Xcode would extract ("Hello %@") and the interpolated arguments as text. Apple's type keeps
    /// both private; its Codable form has them.
    package var _keyAndArguments: (key: String, arguments: [String]) {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["key"] as? String else { return ("\(self)", []) }
        let arguments = (object["arguments"] as? [[String: Any]] ?? []).map { argument -> String in
            guard let (kind, payload) = argument.first else { return "" }
            let value = (payload as? [String: Any])?["_0"] ?? payload
            switch kind {
            case "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64":
                return (value as? NSNumber).map { "\($0.int64Value)" } ?? "\(value)"
            case "double", "float", "cgfloat":
                return (value as? NSNumber).map { "\($0.doubleValue)" } ?? "\(value)"
            default:
                if let string = value as? String { return string }
                if let nested = value as? [String: Any], let text = nested["key"] as? String { return text }
                return "\(value)"
            }
        }
        return (key, arguments)
    }

    /// The value from the string table, or the key itself, with the arguments filled in.
    package var resolved: String {
        let (key, arguments) = _keyAndArguments
        return ScreenshotStrings.format(ScreenshotStrings.template(key, arguments: arguments) ?? key, arguments)
    }
}

extension LocalizedStringResource {
    /// The resolved text: the table's value for the key, or the default value with its arguments.
    public var _resolvedText: String {
        let (defaultKey, arguments) = defaultValue._keyAndArguments
        if let template = ScreenshotStrings.template(key, arguments: arguments) {
            return ScreenshotStrings.format(template, arguments)
        }
        return ScreenshotStrings.format(ScreenshotStrings.template(defaultKey, arguments: arguments) ?? defaultKey, arguments)
    }
    /// A resource whose key is already-interpolated text.
    package init(_verbatimKey text: String) {
        self.init(String.LocalizationValue(text))
    }
}

/// LocalizedStringResource, as the generic parameter of our `String(localized:)`: a generic overload is chosen
/// over Apple's non-generic one only because Apple marks that one `@_disfavoredOverload`, and a generic
/// initializer cannot capture a string literal, so literals still pick the `LocalizationValue` overloads.
public protocol _ScreenshotLocalizedResource {
    var _resolvedText: String { get }
}
extension LocalizedStringResource: _ScreenshotLocalizedResource {}

package func _screenshotResolve(key: String, defaultValue: String.LocalizationValue) -> String {
    let (_, arguments) = defaultValue._keyAndArguments
    return ScreenshotStrings.template(key, arguments: arguments).map { ScreenshotStrings.format($0, arguments) } ?? defaultValue.resolved
}

extension AttributedString {
    package static func _screenshotMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
#endif
