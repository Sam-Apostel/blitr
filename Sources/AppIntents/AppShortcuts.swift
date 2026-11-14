// App Shortcuts: the phrases Siri and Spotlight offer for an app's intents. They are declared, never run.
import Foundation
import SwiftUI

/// A spoken phrase: text with the app's name and intent parameters interpolated.
public struct AppShortcutPhrase<Intent: AppIntent>: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation(_ token: AppShortcutPhraseToken) { text += "${\(token.name)}" }
        public mutating func appendInterpolation<Value>(_ parameter: KeyPath<Intent, IntentParameter<Value>>) { text += "${parameter}" }
    }
    let text: String
    public init(_ string: String) { text = string }
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }
}

public struct AppShortcutPhraseToken: Sendable {
    let name: String
    public static let applicationName = AppShortcutPhraseToken(name: "applicationName")
}

public struct AppShortcut: Sendable {
    public let shortTitle: LocalizedStringResource?
    public let systemImageName: String?
    let phrases: [String]

    public init<Intent: AppIntent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>], shortTitle: LocalizedStringResource,
                                   systemImageName: String) {
        self.phrases = phrases.map(\.text)
        self.shortTitle = shortTitle
        self.systemImageName = systemImageName
    }
    @available(*, deprecated, message: "Provide a shortTitle and systemImageName")
    public init<Intent: AppIntent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>], systemImageName: String? = nil) {
        self.phrases = phrases.map(\.text)
        self.shortTitle = nil
        self.systemImageName = systemImageName
    }
}

@resultBuilder
public enum AppShortcutsBuilder {
    public static func buildExpression(_ expression: AppShortcut) -> [AppShortcut] { [expression] }
    public static func buildExpression(_ expression: [AppShortcut]) -> [AppShortcut] { expression }
    public static func buildBlock() -> [AppShortcut] { [] }
    public static func buildBlock(_ components: [AppShortcut]...) -> [AppShortcut] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [AppShortcut]?) -> [AppShortcut] { component ?? [] }
    public static func buildEither(first component: [AppShortcut]) -> [AppShortcut] { component }
    public static func buildEither(second component: [AppShortcut]) -> [AppShortcut] { component }
    public static func buildLimitedAvailability(_ component: [AppShortcut]) -> [AppShortcut] { component }
}

public enum ShortcutTileColor: Int, Sendable {
    case red, tangerine, orange, yellow, lime, grayGreen, teal, lightBlue, navy, blue, grape, purple, pink, grayBlue, grayBrown, gray
}

public protocol AppShortcutsProvider: Sendable {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
    static var shortcutTileColor: ShortcutTileColor { get }
    static var negativePhrases: [NegativeAppShortcutPhrase] { get }
}
extension AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor { .navy }
    public static var negativePhrases: [NegativeAppShortcutPhrase] { [] }
    /// Asks the system to read parameter values again; there is no system index here.
    public static func updateAppShortcutParameters() {}
}

public struct NegativeAppShortcutPhrase: ExpressibleByStringLiteral, Sendable {
    public init(_ string: String) {}
    public init(stringLiteral value: String) {}
}
