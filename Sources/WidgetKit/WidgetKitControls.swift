// Controls (iOS 18): Control Center, Lock Screen and Action Button controls. They compile so a
// widget bundle that lists them builds, but they are not rendered (the system draws controls
// from their label and tint; there is no canvas for them here).

import ActivityKit
import AppIntents
import Foundation
import SwiftUI

@MainActor @preconcurrency
public protocol ControlWidget {
    associatedtype Body: ControlWidgetConfiguration
    init()
    @ControlWidgetConfigurationBuilder var body: Self.Body { get }
}

@MainActor @preconcurrency
public protocol ControlWidgetConfiguration {
    associatedtype Body: ControlWidgetConfiguration
    @ControlWidgetConfigurationBuilder var body: Self.Body { get }
}

@MainActor @preconcurrency
public protocol ControlWidgetTemplate {
    associatedtype Body: ControlWidgetTemplate
    @ControlWidgetTemplateBuilder var body: Self.Body { get }
}

extension Never: ControlWidgetConfiguration, ControlWidgetTemplate {}
extension ControlWidgetConfiguration where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive control configuration") }
}
extension ControlWidgetTemplate where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive control template") }
}

@resultBuilder
public enum ControlWidgetConfigurationBuilder {
    public static func buildBlock<C: ControlWidgetConfiguration>(_ content: C) -> C { content }
    public static func buildEither<T: ControlWidgetConfiguration>(first: T) -> _ControlConfiguration { _ControlConfiguration() }
    public static func buildEither<F: ControlWidgetConfiguration>(second: F) -> _ControlConfiguration { _ControlConfiguration() }
    public static func buildLimitedAvailability<C: ControlWidgetConfiguration>(_ content: C) -> _ControlConfiguration { _ControlConfiguration() }
}

@resultBuilder
public enum ControlWidgetTemplateBuilder {
    public static func buildBlock<C: ControlWidgetTemplate>(_ content: C) -> C { content }
    public static func buildEither<T: ControlWidgetTemplate>(first: T) -> _ControlTemplate { _ControlTemplate() }
    public static func buildEither<F: ControlWidgetTemplate>(second: F) -> _ControlTemplate { _ControlTemplate() }
    public static func buildLimitedAvailability<C: ControlWidgetTemplate>(_ content: C) -> _ControlTemplate { _ControlTemplate() }
}

/// A configuration or template after a modifier or a branch (controls are not rendered).
public struct _ControlConfiguration: ControlWidgetConfiguration { public typealias Body = Never }
public struct _ControlTemplate: ControlWidgetTemplate { public typealias Body = Never }

public protocol ControlValueProvider {
    associatedtype Value
    var previewValue: Value { get }
    func currentValue() async throws -> Value
}

public protocol AppIntentControlValueProvider {
    associatedtype Value
    associatedtype Configuration: ControlConfigurationIntent
    func previewValue(configuration: Configuration) -> Value
    func currentValue(configuration: Configuration) async throws -> Value
}

public protocol ControlConfigurationIntent: AppIntent {}

public struct StaticControlConfiguration<Content: ControlWidgetTemplate>: ControlWidgetConfiguration {
    public typealias Body = Never
    public init(kind: String, @ControlWidgetTemplateBuilder content: () -> Content) {}
    public init<Provider: ControlValueProvider>(kind: String, provider: Provider,
                                                @ControlWidgetTemplateBuilder content: @escaping (Provider.Value) -> Content) {}
}

public struct AppIntentControlConfiguration<Intent: ControlConfigurationIntent, Content: ControlWidgetTemplate>: ControlWidgetConfiguration {
    public typealias Body = Never
    public init<Provider: AppIntentControlValueProvider>(kind: String, intent: Intent.Type = Intent.self, provider: Provider,
                                                         @ControlWidgetTemplateBuilder content: @escaping (Provider.Value) -> Content)
    where Provider.Configuration == Intent {}
    public init(kind: String, intent: Intent.Type = Intent.self, @ControlWidgetTemplateBuilder content: @escaping (Intent) -> Content) {}
}

public struct ControlWidgetButton<Content: View, ValueLabel: View, Action: AppIntent>: ControlWidgetTemplate {
    public typealias Body = Never
    public init(action: Action, @ViewBuilder label: () -> Content) where ValueLabel == EmptyView {}
    public init(action: Action, @ViewBuilder label: () -> Content, @ViewBuilder actionLabel: (Bool) -> ValueLabel) {}
}

extension ControlWidgetButton where Content == Label<Text, Image>, ValueLabel == EmptyView {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: Action) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, action: Action) {}
}

public struct ControlWidgetToggle<Content: View, ValueLabel: View, Action: AppIntent>: ControlWidgetTemplate {
    public typealias Body = Never
    public init(isOn: Bool, action: Action, @ViewBuilder label: () -> Content) where ValueLabel == EmptyView {}
    public init(isOn: Bool, action: Action, @ViewBuilder label: () -> Content, @ViewBuilder valueLabel: (Bool) -> ValueLabel) {}
}

extension ControlWidgetToggle where Content == Label<Text, Image>, ValueLabel == EmptyView {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Bool, action: Action) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, isOn: Bool, action: Action) {}
}

public struct ControlWidgetActionHint: Sendable {
    public init(_ hint: LocalizedStringResource) {}
}

extension ControlWidgetTemplate {
    public func tint(_ tint: Color?) -> some ControlWidgetTemplate { _ControlTemplate() }
    public func controlWidgetActionHint(_ hint: LocalizedStringResource) -> some ControlWidgetTemplate { _ControlTemplate() }
    public func controlWidgetActionHint(_ hint: ControlWidgetActionHint) -> some ControlWidgetTemplate { _ControlTemplate() }
    public func controlWidgetStatus(_ status: LocalizedStringResource) -> some ControlWidgetTemplate { _ControlTemplate() }
}

extension ControlWidgetConfiguration {
    public func displayName(_ displayName: LocalizedStringResource) -> some ControlWidgetConfiguration { _ControlConfiguration() }
    public func description(_ description: LocalizedStringResource) -> some ControlWidgetConfiguration { _ControlConfiguration() }
    public func promptsForUserConfiguration() -> some ControlWidgetConfiguration { _ControlConfiguration() }
}
