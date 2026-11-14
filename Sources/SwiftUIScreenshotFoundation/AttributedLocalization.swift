// AttributedString(localized:): the localized string (see Localization.swift), with its inline Markdown
// interpreted as on Apple platforms.
import Foundation

extension AttributedString {
    public struct LocalizationOptions: Hashable, Sendable {
        public init() {}
    }

    public init(localized keyAndValue: String.LocalizationValue, options: LocalizationOptions = .init(), table: String? = nil,
                bundle: Bundle? = nil, locale: Locale? = nil, comment: StaticString? = nil) {
        self = Self.markdownOrPlain(keyAndValue.resolved)
    }
    public init(localized key: StaticString, defaultValue: String.LocalizationValue, options: LocalizationOptions = .init(),
                table: String? = nil, bundle: Bundle? = nil, locale: Locale? = nil, comment: StaticString? = nil) {
        let text = ScreenshotStrings.lookup("\(key)").map { _ in String(localized: key, defaultValue: defaultValue) } ?? defaultValue.resolved
        self = Self.markdownOrPlain(text)
    }
    public init(localized resource: LocalizedStringResource) {
        self = Self.markdownOrPlain(String(localized: resource))
    }
    public init(localized resource: LocalizedStringResource, options: LocalizationOptions) {
        self = Self.markdownOrPlain(String(localized: resource))
    }

    private static func markdownOrPlain(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
