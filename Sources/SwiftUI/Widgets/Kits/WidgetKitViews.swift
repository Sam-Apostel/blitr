
// The SwiftUI API that WidgetKit adds: environment values, view modifiers, AccessoryWidgetBackground.

extension EnvironmentValues {
    public var widgetFamily: WidgetFamily {
        get { WidgetFamily(_widgetFamily) }
        set { _widgetFamily = newValue._id }
    }
    public var widgetRenderingMode: WidgetRenderingMode {
        get { WidgetRenderingMode(id: _widgetRenderingMode) }
        set { _widgetRenderingMode = newValue.id }
    }
    public var showsWidgetContainerBackground: Bool {
        get { _showsWidgetContainerBackground }
        set { _showsWidgetContainerBackground = newValue }
    }
    public var widgetContentMargins: EdgeInsets {
        get { _widgetContentMargins }
        set { _widgetContentMargins = newValue }
    }
}

extension ContainerBackgroundPlacement {
    public static var widget: ContainerBackgroundPlacement { ._widget }
}

extension View {
    /// Draws this content in the accent color when the widget is rendered in the accented mode.
    public func widgetAccentable(_ accentable: Bool = true) -> some View { _widgetAccentable(accentable) }

    /// The URL opened by a tap. Taps do not happen in a screenshot.
    public func widgetURL(_ url: URL?) -> some View { self }

    /// The label of a watchOS corner / circular complication. iOS does not show it.
    public func widgetLabel(_ label: Text) -> some View { self }
    public func widgetLabel(_ labelKey: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload
    public func widgetLabel<S: StringProtocol>(_ label: S) -> some View { self }
    public func widgetLabel<Label: View>(@ViewBuilder label: () -> Label) -> some View { self }
}

public struct WidgetAccentedRenderingMode: Hashable, Sendable {
    let name: String
    public static let accented = WidgetAccentedRenderingMode(name: "accented")
    public static let desaturated = WidgetAccentedRenderingMode(name: "desaturated")
    public static let accentedDesaturated = WidgetAccentedRenderingMode(name: "accentedDesaturated")
    public static let fullColor = WidgetAccentedRenderingMode(name: "fullColor")
}

extension Image {
    /// How the image is drawn in the accented rendering mode. Not implemented: in that mode the
    /// image is tinted like other content, and a warning says so.
    public func widgetAccentedRenderingMode(_ renderingMode: WidgetAccentedRenderingMode?) -> Image {
        if renderingMode != nil, _WidgetHostOptions.current.renderingMode == .accented {
            MainActor.assumeIsolated { _WidgetHost.warn("widgetAccentedRenderingMode(_:) is not implemented; the image is tinted like the rest of the widget") }
        }
        return self
    }
}

// MARK: - Relevance (Smart Stack ordering; no effect on a rendered frame)

public struct RelevantContext: Hashable, Sendable {
    let name: String
    public static func date(_ date: Date, kind: DateKind = .default) -> RelevantContext { RelevantContext(name: "date") }
    public static func date(interval: DateInterval, kind: DateKind = .default) -> RelevantContext { RelevantContext(name: "date") }
    public static func date(from: Date, to: Date) -> RelevantContext { RelevantContext(name: "date") }
    public static func sleep(_ condition: SleepCondition) -> RelevantContext { RelevantContext(name: "sleep") }
    public static let fitness = RelevantContext(name: "fitness")
    public struct DateKind: Hashable, Sendable {
        public static let `default` = DateKind(), scheduled = DateKind(), informational = DateKind()
    }
    public struct SleepCondition: Hashable, Sendable {
        public static let bedtime = SleepCondition(), wakeup = SleepCondition()
    }
}

public struct WidgetRelevanceAttribute<Configuration> {
    public init(context: RelevantContext) {}
    public init(configuration: Configuration, context: RelevantContext) {}
}

public struct WidgetRelevance<Configuration> {
    public let attributes: [WidgetRelevanceAttribute<Configuration>]
    public init(_ attributes: [WidgetRelevanceAttribute<Configuration>]) { self.attributes = attributes }
}

/// The standard backing of Lock Screen widgets: a circle (circular), a rounded rectangle
/// (rectangular) or nothing (inline).
public struct AccessoryWidgetBackground: View {
    @Environment(\.widgetFamily) private var family
    public init() {}
    public var body: some View {
        // White at low opacity: the vibrant treatment turns it into the translucent Lock Screen material.
        let fill = Color.white.opacity(0.22)
        switch family {
        case .accessoryCircular: Circle().fill(fill)
        case .accessoryInline: Color.clear
        default: ContainerRelativeShape().fill(fill)
        }
    }
}
