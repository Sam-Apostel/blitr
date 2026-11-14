// A shim of Apple's AppIntents: the part widget code uses (configuration intents, parameters,
// intent results, `Button(intent:)` / `Toggle(isOn:intent:)`). Intents never run here: a
// static frame cannot be tapped, so `perform()` is never called.

// MARK: - Intents

public protocol AppIntent {
    associatedtype PerformResult: IntentResult
    static var title: LocalizedStringResource { get }
    static var description: IntentDescription? { get }
    static var openAppWhenRun: Bool { get }
    static var isDiscoverable: Bool { get }
    init()
    func perform() async throws -> PerformResult
}

extension AppIntent {
    public static var description: IntentDescription? { nil }
    public static var openAppWhenRun: Bool { false }
    public static var isDiscoverable: Bool { true }
    public typealias Parameter<Value> = IntentParameter<Value>
}

/// The intent behind a configurable widget (`AppIntentConfiguration`).
public protocol WidgetConfigurationIntent: AppIntent {}

extension WidgetConfigurationIntent {
    public func perform() async throws -> some IntentResult { IntentResultContainer<Never, Never, Never, Never>() }
}

public protocol SystemIntent: AppIntent {}
public protocol LiveActivityIntent: AppIntent {}
public protocol AudioPlaybackIntent: AppIntent {}
public protocol SetValueIntent: AppIntent {
    associatedtype ValueType
    var value: ValueType { get set }
}

public struct IntentDescription: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public var descriptionText: LocalizedStringResource
    public init(_ descriptionText: LocalizedStringResource, categoryName: LocalizedStringResource? = nil,
                searchKeywords: [LocalizedStringResource] = [], resultValueName: LocalizedStringResource? = nil) {
        self.descriptionText = descriptionText
    }
    public init(stringLiteral value: String) { descriptionText = LocalizedStringResource(stringLiteral: value) }
    public init(stringInterpolation: DefaultStringInterpolation) {
        descriptionText = LocalizedStringResource(stringInterpolation: stringInterpolation)
    }
}

// MARK: - Results

public protocol IntentResult {}
public protocol ReturnsValue<Value>: IntentResult { associatedtype Value }
public protocol ProvidesDialog: IntentResult {}
public protocol OpensIntent: IntentResult {}
public protocol ShowsSnippetView: IntentResult {}

public struct IntentDialog: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public var text: LocalizedStringResource
    public init(_ text: LocalizedStringResource) { self.text = text }
    public init(full: LocalizedStringResource, supporting: LocalizedStringResource) { text = full }
    public init(stringLiteral value: String) { text = LocalizedStringResource(stringLiteral: value) }
    public init(stringInterpolation: DefaultStringInterpolation) { text = LocalizedStringResource(stringInterpolation: stringInterpolation) }
}

public struct IntentResultContainer<Value, OpensIntentType, Content, DialogType>: IntentResult {
    public var value: Value?
    init(value: Value? = nil) { self.value = value }
}
extension IntentResultContainer: ReturnsValue {}
extension IntentResultContainer: ProvidesDialog where DialogType == IntentDialog {}
extension IntentResultContainer: OpensIntent where OpensIntentType: AppIntent {}

extension IntentResult {
    public static func result<I: AppIntent>(opensIntent: I) -> Self where Self == IntentResultContainer<Never, I, Never, Never> { .init() }
    public static func result<I: AppIntent>(opensIntent: I, dialog: IntentDialog) -> Self
    where Self == IntentResultContainer<Never, I, Never, IntentDialog> { .init() }
}

/// Opens a URL (the system intent). Nothing is opened here.
public struct OpenURLIntent: AppIntent {
    public static var title: LocalizedStringResource { "Open URL" }
    public var url: URL
    public init() { url = URL(string: "about:blank")! }
    public init(_ url: URL) { self.url = url }
    public func perform() async throws -> some IntentResult { IntentResultContainer<Never, Never, Never, Never>() }
}

extension IntentResult {
    public static func result() -> Self where Self == IntentResultContainer<Never, Never, Never, Never> { .init() }
    public static func result(dialog: IntentDialog) -> Self where Self == IntentResultContainer<Never, Never, Never, IntentDialog> { .init() }
    public static func result<V>(value: V) -> Self where Self == IntentResultContainer<V, Never, Never, Never> { .init(value: value) }
    public static func result<V>(value: V, dialog: IntentDialog) -> Self where Self == IntentResultContainer<V, Never, Never, IntentDialog> {
        .init(value: value)
    }
}

// MARK: - Parameters

/// `@Parameter`: an intent's configurable value. A parameter without a default and without a
/// wrapped value is unset; reading it stops the render with a message saying so.
@propertyWrapper
public final class IntentParameter<Value> {
    public let title: LocalizedStringResource
    public let description: LocalizedStringResource?
    private var storage: Value?
    private let isOptional: Bool

    public var wrappedValue: Value {
        get {
            if let storage { return storage }
            if isOptional, let none = Optional<Any>.none as? Value { return none }
            fatalError("@Parameter \"\(title)\" has no value: give it a default (@Parameter(title:default:)) or set it before the widget reads it")
        }
        set { storage = newValue }
    }
    public var projectedValue: IntentParameter<Value> { self }

    public init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value? = nil,
                requestValueDialog: IntentDialog? = nil) {
        self.title = title
        self.description = description
        self.storage = defaultValue
        self.isOptional = Value.self is _OptionalMarker.Type
    }
    public init(wrappedValue: Value, title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                requestValueDialog: IntentDialog? = nil) {
        self.title = title
        self.description = description
        self.storage = wrappedValue
        self.isOptional = Value.self is _OptionalMarker.Type
    }
    public convenience init<R: RangeExpression>(title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                                    default defaultValue: Value? = nil, inclusiveRange: R) {
        self.init(title: title, description: description, default: defaultValue)
    }
    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value? = nil,
                controlStyle: ParameterControlStyle) {
        self.init(title: title, description: description, default: defaultValue)
    }
}

public protocol _OptionalMarker {}
extension Optional: _OptionalMarker {}

public struct ParameterControlStyle: Sendable {
    public static let field = ParameterControlStyle(), slider = ParameterControlStyle(), stepper = ParameterControlStyle()
}

// MARK: - Enums

public struct TypeDisplayRepresentation: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public var name: LocalizedStringResource
    public init(name: LocalizedStringResource, numericFormat: LocalizedStringResource? = nil) { self.name = name }
    public init(stringLiteral value: String) { name = LocalizedStringResource(stringLiteral: value) }
    public init(stringInterpolation: DefaultStringInterpolation) { name = LocalizedStringResource(stringInterpolation: stringInterpolation) }
}

public struct DisplayRepresentation: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public struct Image: Sendable {
        public var systemName: String?
        public init(systemName: String, tintColor: UIColor? = nil, symbolConfiguration: Any? = nil) { self.systemName = systemName }
        public init(named name: String, isTemplate: Bool = false) { systemName = nil }
    }
    public var title: LocalizedStringResource
    public var subtitle: LocalizedStringResource?
    public var image: Image?
    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: Image? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
    }
    public init(stringLiteral value: String) { title = LocalizedStringResource(stringLiteral: value) }
    public init(stringInterpolation: DefaultStringInterpolation) { title = LocalizedStringResource(stringInterpolation: stringInterpolation) }
}

public protocol AppEnum: CaseIterable, RawRepresentable, Hashable where RawValue: Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { get }
}

// MARK: - Entities

public protocol EntityIdentifierConvertible {}
extension String: EntityIdentifierConvertible {}
extension Int: EntityIdentifierConvertible {}
extension UUID: EntityIdentifierConvertible {}

/// An app entity, e.g. the value of a configuration intent's `@Parameter`. Queries are never run here.
public protocol AppEntity: Identifiable where ID: EntityIdentifierConvertible {
    associatedtype DefaultQuery: EntityQuery
    static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
    static var defaultQuery: DefaultQuery { get }
    var displayRepresentation: DisplayRepresentation { get }
}

public protocol EntityQuery {
    associatedtype Entity: AppEntity
    associatedtype Result = [Entity]
    init()
    func entities(for identifiers: [Entity.ID]) async throws -> [Entity]
    func suggestedEntities() async throws -> Result
}

extension EntityQuery where Result == [Entity] {
    public func suggestedEntities() async throws -> [Entity] { [] }
}

public protocol EntityStringQuery: EntityQuery {
    func entities(matching string: String) async throws -> Result
}

// MARK: - SwiftUI controls that run an intent

extension Button {
    public init<I: AppIntent>(intent: I, @ViewBuilder label: () -> Label) {
        self.init(action: {}, label: label)
    }
    public init<I: AppIntent>(role: ButtonRole?, intent: I, @ViewBuilder label: () -> Label) {
        self.init(role: role, action: {}, label: label)
    }
}

extension Button where Label == Text {
    public init<I: AppIntent>(_ titleKey: LocalizedStringKey, intent: I) {
        self.init(intent: intent) { Text(titleKey) }
    }
    @_disfavoredOverload
    public init<I: AppIntent, S: StringProtocol>(_ title: S, intent: I) {
        self.init(intent: intent) { Text(title) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    public init<I: AppIntent>(_ titleKey: LocalizedStringKey, systemImage: String, intent: I) {
        self.init(intent: intent) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload
    public init<I: AppIntent, S: StringProtocol>(_ title: S, systemImage: String, intent: I) {
        self.init(intent: intent) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}

extension Toggle {
    public init<I: AppIntent>(isOn: Bool, intent: I, @ViewBuilder label: () -> Label) {
        self.init(isOn: .constant(isOn), label: label)
    }
}

extension Toggle where Label == Text {
    public init<I: AppIntent>(_ titleKey: LocalizedStringKey, isOn: Bool, intent: I) {
        self.init(isOn: .constant(isOn)) { Text(titleKey) }
    }
    @_disfavoredOverload
    public init<I: AppIntent, S: StringProtocol>(_ title: S, isOn: Bool, intent: I) {
        self.init(isOn: .constant(isOn)) { Text(title) }
    }
}
