// A shim of Apple's WidgetKit: widgets, bundles, configurations and their modifiers.
// Rendering goes through `SwiftUI._WidgetCanvas` / `_LiveActivityCanvas`; see docs/WIDGETS.md.

import ActivityKit
import AppIntents
import Foundation
import SwiftUI

// MARK: - Families

public enum WidgetFamily: Int, CaseIterable, Codable, CustomStringConvertible, Hashable, Sendable {
    case systemSmall, systemMedium, systemLarge, systemExtraLarge
    case accessoryCircular, accessoryRectangular, accessoryInline

    public var description: String { _id.rawValue }

    var _id: _WidgetFamilyID {
        switch self {
        case .systemSmall: return .systemSmall
        case .systemMedium: return .systemMedium
        case .systemLarge: return .systemLarge
        case .systemExtraLarge: return .systemExtraLarge
        case .accessoryCircular: return .accessoryCircular
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        }
    }
    init(_ id: _WidgetFamilyID) {
        self = WidgetFamily.allCases.first { $0._id == id }!
    }
}

public struct WidgetRenderingMode: Equatable, Hashable, CustomStringConvertible, Sendable {
    let id: _WidgetRenderingModeID
    public static let fullColor = WidgetRenderingMode(id: .fullColor)
    public static let accented = WidgetRenderingMode(id: .accented)
    public static let vibrant = WidgetRenderingMode(id: .vibrant)
    public var description: String { id.rawValue }
}

// MARK: - Widget and bundles

@MainActor @preconcurrency
public protocol Widget {
    associatedtype Body: WidgetConfiguration
    init()
    @WidgetConfigurationBuilder var body: Self.Body { get }
}

@MainActor @preconcurrency
public protocol WidgetBundle {
    associatedtype Body: Widget
    init()
    @WidgetBundleBuilder var body: Self.Body { get }
}

extension WidgetBundle {
    /// `@main` is removed by the preprocessor; there is no extension process to run.
    public static func main() {}
}

/// The widgets of a bundle body, in order.
public struct _WidgetList: Widget {
    public typealias Body = Never
    let widgets: [any Widget]
    init(_ widgets: [any Widget]) { self.widgets = widgets }
    public init() { widgets = [] }
    public var body: Never { fatalError("_WidgetList has no body") }
}

@resultBuilder
public enum WidgetBundleBuilder {
    public static func buildExpression<W: Widget>(_ widget: W) -> _WidgetList {
        if let list = widget as? _WidgetList { return list }
        return _WidgetList([widget])
    }
    /// Controls are listed in bundles too; they are not rendered.
    public static func buildExpression<C: ControlWidget>(_ control: C) -> _WidgetList { _WidgetList([]) }
    public static func buildBlock(_ parts: _WidgetList...) -> _WidgetList { _WidgetList(parts.flatMap(\.widgets)) }
    public static func buildOptional(_ part: _WidgetList?) -> _WidgetList { part ?? _WidgetList([]) }
    public static func buildEither(first: _WidgetList) -> _WidgetList { first }
    public static func buildEither(second: _WidgetList) -> _WidgetList { second }
    public static func buildLimitedAvailability(_ part: _WidgetList) -> _WidgetList { part }
}

extension Widget {
    @MainActor var _widgets: [any Widget] {
        if let list = self as? _WidgetList { return list.widgets }
        return [self]
    }
}

// MARK: - Configurations

@MainActor @preconcurrency
public protocol WidgetConfiguration {
    associatedtype Body: WidgetConfiguration
    @WidgetConfigurationBuilder var body: Self.Body { get }
}

extension Never: WidgetConfiguration {}
extension WidgetConfiguration where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive widget configuration") }
}

@resultBuilder
public enum WidgetConfigurationBuilder {
    public static func buildBlock<C: WidgetConfiguration>(_ content: C) -> C { content }
    public static func buildEither<T: WidgetConfiguration, F: WidgetConfiguration>(first: T) -> _ConditionalWidgetConfiguration<T, F> {
        _ConditionalWidgetConfiguration(make: { first._widgetDescription() })
    }
    public static func buildEither<T: WidgetConfiguration, F: WidgetConfiguration>(second: F) -> _ConditionalWidgetConfiguration<T, F> {
        _ConditionalWidgetConfiguration(make: { second._widgetDescription() })
    }
    public static func buildLimitedAvailability<C: WidgetConfiguration>(_ content: C) -> _ConditionalWidgetConfiguration<C, EmptyWidgetConfiguration> {
        _ConditionalWidgetConfiguration(make: { content._widgetDescription() })
    }
}

public struct _ConditionalWidgetConfiguration<T: WidgetConfiguration, F: WidgetConfiguration>: WidgetConfiguration, _WidgetDescribing {
    public typealias Body = Never
    let make: @MainActor () -> _WidgetDescription?
    func _describe() -> _WidgetDescription? { make() }
}

public struct EmptyWidgetConfiguration: WidgetConfiguration {
    public typealias Body = Never
    public init() {}
}

/// What the renderer needs to know about a widget.
struct _WidgetDescription {
    var kind: String
    var supportedFamilies: [WidgetFamily]?
    var contentMarginsDisabled = false
    var backgroundRemovable = true
    /// Renders an entry (timeline widgets). Returns nil when the entry is of another type.
    var render: (@MainActor (Any) -> AnyView?)?
    /// A representative entry for a family (from the provider's snapshot, else its placeholder).
    var previewEntry: (@MainActor (TimelineProviderContext) -> any TimelineEntry)?
    var entryType: Any.Type?
    var activity: _ActivityDescription?
}

protocol _WidgetDescribing {
    @MainActor func _describe() -> _WidgetDescription?
}

extension WidgetConfiguration {
    @MainActor func _widgetDescription() -> _WidgetDescription? {
        if let primitive = self as? _WidgetDescribing { return primitive._describe() }
        if Body.self == Never.self { return nil }
        return body._widgetDescription()
    }
}

extension Widget {
    @MainActor func _widgetDescription() -> _WidgetDescription? {
        if Body.self == Never.self { return nil }
        return body._widgetDescription()
    }
}

public struct StaticConfiguration<Content: View>: WidgetConfiguration, _WidgetDescribing {
    public typealias Body = Never
    let description: _WidgetDescription

    public init<Provider: TimelineProvider>(kind: String, provider: Provider, @ViewBuilder content: @escaping (Provider.Entry) -> Content) {
        description = _WidgetDescription(
            kind: kind,
            render: { entry in (entry as? Provider.Entry).map { AnyView(content($0)) } },
            previewEntry: { context in
                _ProviderRunner.snapshot(provider, context) ?? provider.placeholder(in: context)
            },
            entryType: Provider.Entry.self)
    }
    func _describe() -> _WidgetDescription? { description }
}

public struct AppIntentConfiguration<Intent: WidgetConfigurationIntent, Content: View>: WidgetConfiguration, _WidgetDescribing {
    public typealias Body = Never
    let description: _WidgetDescription

    public init<Provider: AppIntentTimelineProvider>(kind: String, intent: Intent.Type = Intent.self, provider: Provider,
                                                     @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Intent == Provider.Intent {
        description = _WidgetDescription(
            kind: kind,
            render: { entry in (entry as? Provider.Entry).map { AnyView(content($0)) } },
            previewEntry: { context in
                _ProviderRunner.snapshot(provider, Intent(), context) ?? provider.placeholder(in: context)
            },
            entryType: Provider.Entry.self)
    }
    func _describe() -> _WidgetDescription? { description }
}

/// A configuration with a change applied to its description.
public struct _ModifiedWidgetConfiguration<Base: WidgetConfiguration>: WidgetConfiguration, _WidgetDescribing {
    public typealias Body = Never
    let base: Base
    let change: (inout _WidgetDescription) -> Void
    func _describe() -> _WidgetDescription? {
        guard var description = base._widgetDescription() else { return nil }
        change(&description)
        return description
    }
}

public struct WidgetLocation: Hashable, Sendable {
    let name: String
    public static let homeScreen = WidgetLocation(name: "homeScreen")
    public static let lockScreen = WidgetLocation(name: "lockScreen")
    public static let standBy = WidgetLocation(name: "standBy")
    public static let iPhoneWidgetsOnMac = WidgetLocation(name: "iPhoneWidgetsOnMac")
    public static let carPlay = WidgetLocation(name: "carPlay")
}

extension WidgetConfiguration {
    func modified(_ change: @escaping (inout _WidgetDescription) -> Void) -> _ModifiedWidgetConfiguration<Self> {
        _ModifiedWidgetConfiguration(base: self, change: change)
    }

    public func configurationDisplayName(_ displayName: Text) -> some WidgetConfiguration { modified { _ in } }
    public func configurationDisplayName(_ displayNameKey: LocalizedStringKey) -> some WidgetConfiguration { modified { _ in } }
    @_disfavoredOverload
    public func configurationDisplayName<S: StringProtocol>(_ displayName: S) -> some WidgetConfiguration { modified { _ in } }
    public func description(_ description: Text) -> some WidgetConfiguration { modified { _ in } }
    public func description(_ descriptionKey: LocalizedStringKey) -> some WidgetConfiguration { modified { _ in } }
    @_disfavoredOverload
    public func description<S: StringProtocol>(_ description: S) -> some WidgetConfiguration { modified { _ in } }

    public func supportedFamilies(_ families: [WidgetFamily]) -> some WidgetConfiguration {
        modified { $0.supportedFamilies = families }
    }
    public func contentMarginsDisabled() -> some WidgetConfiguration { modified { $0.contentMarginsDisabled = true } }
    public func containerBackgroundRemovable(_ isRemovable: Bool = true) -> some WidgetConfiguration {
        modified { $0.backgroundRemovable = isRemovable }
    }
    public func disfavoredLocations(_ locations: [WidgetLocation], for families: [WidgetFamily]) -> some WidgetConfiguration { modified { _ in } }
    public func promptsForUserConfiguration() -> some WidgetConfiguration { modified { _ in } }
    public func onBackgroundURLSessionEvents(matching identifier: String? = nil,
                                             _ handler: @escaping (String, @escaping () -> Void) -> Void) -> some WidgetConfiguration {
        modified { _ in }
    }
}

// MARK: - Widget center

/// Reload requests have no effect: nothing is scheduled here.
public final class WidgetCenter: @unchecked Sendable {
    public static let shared = WidgetCenter()
    public typealias UserInfo = WidgetInfo
    public func reloadAllTimelines() {}
    public func reloadTimelines(ofKind kind: String) {}
    public func invalidateConfigurationRecommendations() {}
    public func getCurrentConfigurations(_ completion: @escaping (Result<[WidgetInfo], Error>) -> Void) { completion(.success([])) }
    public func currentConfigurations() async throws -> [WidgetInfo] { [] }
}

public struct WidgetInfo: Sendable {
    public let kind: String
    public let family: WidgetFamily
}
