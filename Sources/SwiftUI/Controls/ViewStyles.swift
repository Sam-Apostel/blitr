// Style protocols with `makeBody(configuration:)` for LabeledContent, DisclosureGroup, Menu, ControlGroup,
// NavigationSplitView, TextEditor, DatePicker and Gauge. Each follows the Toggle/Label pattern: the
// styled control looks up a style box in the environment; without one it draws its built-in look.
// `Control(configuration)` inside a style draws the built-in look (`forceDefault`), as in SwiftUI.

// MARK: - LabeledContentStyle

public struct LabeledContentStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Content: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public let label: LabeledContentStyleConfiguration.Label
    public let content: LabeledContentStyleConfiguration.Content
}

@MainActor @preconcurrency
public protocol LabeledContentStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabeledContentStyleConfiguration
}

struct TwoSlotStyleBox {
    let make: @MainActor (AnyView, AnyView) -> AnyView
}

enum LabeledContentStyleKey: EnvironmentKey { static let defaultValue: TwoSlotStyleBox? = nil }
extension EnvironmentValues {
    var labeledContentStyleBox: TwoSlotStyleBox? {
        get { self[LabeledContentStyleKey.self] }
        set { self[LabeledContentStyleKey.self] = newValue }
    }
}

struct _LabeledContentStyleApplier<S: LabeledContentStyle>: View {
    let style: S
    let label: AnyView
    let content: AnyView
    var body: some View {
        style.makeBody(configuration: LabeledContentStyleConfiguration(label: .init(view: label), content: .init(view: content)))
    }
}

public struct AutomaticLabeledContentStyle: LabeledContentStyle {
    public init() {}
    public func makeBody(configuration: LabeledContentStyleConfiguration) -> some View { LabeledContent(configuration) }
}
extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
    public static var automatic: AutomaticLabeledContentStyle { AutomaticLabeledContentStyle() }
}

extension LabeledContent where Label == LabeledContentStyleConfiguration.Label, Content == LabeledContentStyleConfiguration.Content {
    public init(_ configuration: LabeledContentStyleConfiguration) {
        self.init(content: { configuration.content }, label: { configuration.label })
        self.forceDefault = true
    }
}

extension View {
    public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View {
        env {
            if style is AutomaticLabeledContentStyle { $0.labeledContentStyleBox = nil; return }
            $0.labeledContentStyleBox = TwoSlotStyleBox { label, content in
                AnyView(_LabeledContentStyleApplier(style: style, label: label, content: content))
            }
        }
    }
}

// MARK: - DisclosureGroupStyle

public struct DisclosureGroupStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Content: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public let label: DisclosureGroupStyleConfiguration.Label
    public let content: DisclosureGroupStyleConfiguration.Content
    @Binding public var isExpanded: Bool

    init(label: Label, content: Content, isExpanded: Binding<Bool>) {
        self.label = label
        self.content = content
        self._isExpanded = isExpanded
    }
}

@MainActor @preconcurrency
public protocol DisclosureGroupStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = DisclosureGroupStyleConfiguration
}

struct DisclosureStyleBox {
    let make: @MainActor (AnyView, AnyView, Binding<Bool>) -> AnyView
}

enum DisclosureGroupStyleKey: EnvironmentKey { static let defaultValue: DisclosureStyleBox? = nil }
extension EnvironmentValues {
    var disclosureGroupStyleBox: DisclosureStyleBox? {
        get { self[DisclosureGroupStyleKey.self] }
        set { self[DisclosureGroupStyleKey.self] = newValue }
    }
}

struct _DisclosureGroupStyleApplier<S: DisclosureGroupStyle>: View {
    let style: S
    let label: AnyView
    let content: AnyView
    let isExpanded: Binding<Bool>
    var body: some View {
        style.makeBody(configuration: DisclosureGroupStyleConfiguration(label: .init(view: label), content: .init(view: content), isExpanded: isExpanded))
    }
}

public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
    public init() {}
    public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
        var group = DisclosureGroup(isExpanded: configuration.$isExpanded, content: { configuration.content }, label: { configuration.label })
        group.forceDefault = true
        return group
    }
}
extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
    public static var automatic: AutomaticDisclosureGroupStyle { AutomaticDisclosureGroupStyle() }
}

extension View {
    public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View {
        env {
            if style is AutomaticDisclosureGroupStyle { $0.disclosureGroupStyleBox = nil; return }
            $0.disclosureGroupStyleBox = DisclosureStyleBox { label, content, isExpanded in
                AnyView(_DisclosureGroupStyleApplier(style: style, label: label, content: content, isExpanded: isExpanded))
            }
        }
    }
}

// MARK: - MenuStyle

public struct MenuStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Content: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    let label: Label
    let content: Content
}

@MainActor @preconcurrency
public protocol MenuStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = MenuStyleConfiguration
}

struct MenuStyleBox {
    let make: @MainActor (AnyView, AnyView) -> AnyView
}

enum MenuStyleKey: EnvironmentKey { static let defaultValue: MenuStyleBox? = nil }
extension EnvironmentValues {
    var menuStyleBox: MenuStyleBox? {
        get { self[MenuStyleKey.self] }
        set { self[MenuStyleKey.self] = newValue }
    }
}

struct _MenuStyleApplier<S: MenuStyle>: View {
    let style: S
    let label: AnyView
    let content: AnyView
    var body: some View {
        style.makeBody(configuration: MenuStyleConfiguration(label: .init(view: label), content: .init(view: content)))
    }
}

/// A closed menu is drawn the same way by every built-in style: the style only changes what an opened menu
/// looks like, and menus are always drawn closed.
public struct DefaultMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: MenuStyleConfiguration) -> some View { Menu(configuration) }
}
public struct ButtonMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: MenuStyleConfiguration) -> some View { Menu(configuration) }
}
@available(*, deprecated)
public struct BorderlessButtonMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: MenuStyleConfiguration) -> some View { Menu(configuration) }
}
@available(*, deprecated)
public struct BorderedButtonMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: MenuStyleConfiguration) -> some View { Menu(configuration) }
}
extension MenuStyle where Self == DefaultMenuStyle { public static var automatic: DefaultMenuStyle { DefaultMenuStyle() } }
extension MenuStyle where Self == ButtonMenuStyle { public static var button: ButtonMenuStyle { ButtonMenuStyle() } }
extension MenuStyle where Self == BorderlessButtonMenuStyle {
    @available(*, deprecated) public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}
extension MenuStyle where Self == BorderedButtonMenuStyle {
    @available(*, deprecated) public static var borderedButton: BorderedButtonMenuStyle { BorderedButtonMenuStyle() }
}

extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    public init(_ configuration: MenuStyleConfiguration) {
        self.init(content: { configuration.content }, label: { configuration.label })
        self.forceDefault = true
    }
}

extension View {
    public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        env {
            if style is DefaultMenuStyle || style is ButtonMenuStyle || style is BorderlessButtonMenuStyle || style is BorderedButtonMenuStyle {
                $0.menuStyleBox = nil
                return
            }
            $0.menuStyleBox = MenuStyleBox { label, content in
                AnyView(_MenuStyleApplier(style: style, label: label, content: content))
            }
        }
    }
}

// MARK: - ControlGroupStyle

public struct ControlGroupStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Content: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public let label: ControlGroupStyleConfiguration.Label
    public let content: ControlGroupStyleConfiguration.Content
}

@MainActor @preconcurrency
public protocol ControlGroupStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ControlGroupStyleConfiguration
}

enum ControlGroupKind { case automatic, navigation, palette, menu, compactMenu }
struct ControlGroupStyleBox {
    let kind: ControlGroupKind
    let make: (@MainActor (AnyView, AnyView) -> AnyView)?
}
enum ControlGroupStyleKey: EnvironmentKey { static let defaultValue: ControlGroupStyleBox? = nil }
extension EnvironmentValues {
    var controlGroupStyleBox: ControlGroupStyleBox? {
        get { self[ControlGroupStyleKey.self] }
        set { self[ControlGroupStyleKey.self] = newValue }
    }
}

struct _ControlGroupStyleApplier<S: ControlGroupStyle>: View {
    let style: S
    let label: AnyView
    let content: AnyView
    var body: some View {
        style.makeBody(configuration: ControlGroupStyleConfiguration(label: .init(view: label), content: .init(view: content)))
    }
}

public struct AutomaticControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View { ControlGroup(configuration) }
}
public struct NavigationControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View { ControlGroup(configuration) }
}
public struct PaletteControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View { ControlGroup(configuration) }
}
public struct MenuControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View { ControlGroup(configuration) }
}
public struct CompactMenuControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: ControlGroupStyleConfiguration) -> some View { ControlGroup(configuration) }
}
extension ControlGroupStyle where Self == AutomaticControlGroupStyle { public static var automatic: AutomaticControlGroupStyle { .init() } }
extension ControlGroupStyle where Self == NavigationControlGroupStyle { public static var navigation: NavigationControlGroupStyle { .init() } }
extension ControlGroupStyle where Self == PaletteControlGroupStyle { public static var palette: PaletteControlGroupStyle { .init() } }
extension ControlGroupStyle where Self == MenuControlGroupStyle { public static var menu: MenuControlGroupStyle { .init() } }
extension ControlGroupStyle where Self == CompactMenuControlGroupStyle { public static var compactMenu: CompactMenuControlGroupStyle { .init() } }

extension ControlGroup where Content == ControlGroupStyleConfiguration.Content {
    public init(_ configuration: ControlGroupStyleConfiguration) {
        self.init(content: { configuration.content })
        self.forceDefault = true
    }
}

extension View {
    public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View {
        env {
            switch style {
            case is AutomaticControlGroupStyle: $0.controlGroupStyleBox = nil
            case is NavigationControlGroupStyle: $0.controlGroupStyleBox = ControlGroupStyleBox(kind: .navigation, make: nil)
            case is PaletteControlGroupStyle: $0.controlGroupStyleBox = ControlGroupStyleBox(kind: .palette, make: nil)
            case is MenuControlGroupStyle: $0.controlGroupStyleBox = ControlGroupStyleBox(kind: .menu, make: nil)
            case is CompactMenuControlGroupStyle: $0.controlGroupStyleBox = ControlGroupStyleBox(kind: .compactMenu, make: nil)
            default:
                $0.controlGroupStyleBox = ControlGroupStyleBox(kind: .automatic) { label, content in
                    AnyView(_ControlGroupStyleApplier(style: style, label: label, content: content))
                }
            }
        }
    }
}

// MARK: - NavigationSplitViewStyle

/// The split view's columns are not public API, so a custom style has nothing to arrange.
public struct NavigationSplitViewStyleConfiguration {
    init() {}
}

@MainActor @preconcurrency
public protocol NavigationSplitViewStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = NavigationSplitViewStyleConfiguration
}

public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: NavigationSplitViewStyleConfiguration) -> some View { EmptyView() }
}
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: NavigationSplitViewStyleConfiguration) -> some View { EmptyView() }
}
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: NavigationSplitViewStyleConfiguration) -> some View { EmptyView() }
}
extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle { public static var automatic: Self { .init() } }
extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle { public static var balanced: Self { .init() } }
extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle { public static var prominentDetail: Self { .init() } }

extension View {
    public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View {
        if !(style is AutomaticNavigationSplitViewStyle || style is BalancedNavigationSplitViewStyle || style is ProminentDetailNavigationSplitViewStyle) {
            Runtime.current?.warn("a custom NavigationSplitViewStyle is ignored: the split view draws with the automatic style")
        }
        return self
    }
}

// MARK: - TextEditorStyle

public struct TextEditorStyleConfiguration {
    init() {}
}

@MainActor @preconcurrency
public protocol TextEditorStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = TextEditorStyleConfiguration
}

public struct AutomaticTextEditorStyle: TextEditorStyle {
    public init() {}
    public func makeBody(configuration: TextEditorStyleConfiguration) -> some View { EmptyView() }
}
public struct PlainTextEditorStyle: TextEditorStyle {
    public init() {}
    public func makeBody(configuration: TextEditorStyleConfiguration) -> some View { EmptyView() }
}
public struct RoundedBorderTextEditorStyle: TextEditorStyle {
    public init() {}
    public func makeBody(configuration: TextEditorStyleConfiguration) -> some View { EmptyView() }
}
extension TextEditorStyle where Self == AutomaticTextEditorStyle { public static var automatic: AutomaticTextEditorStyle { .init() } }
extension TextEditorStyle where Self == PlainTextEditorStyle { public static var plain: PlainTextEditorStyle { .init() } }
extension TextEditorStyle where Self == RoundedBorderTextEditorStyle { public static var roundedBorder: RoundedBorderTextEditorStyle { .init() } }

enum TextEditorBorderKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var textEditorRoundedBorder: Bool {
        get { self[TextEditorBorderKey.self] }
        set { self[TextEditorBorderKey.self] = newValue }
    }
}

extension View {
    /// Plain and automatic draw the built-in editor; rounded border draws it inside a bordered field.
    public func textEditorStyle(_ style: some TextEditorStyle) -> some View {
        if !(style is AutomaticTextEditorStyle || style is PlainTextEditorStyle || style is RoundedBorderTextEditorStyle) {
            Runtime.current?.warn("a custom TextEditorStyle is ignored: the text editor has no configuration to build from")
        }
        return env { $0.textEditorRoundedBorder = style is RoundedBorderTextEditorStyle }
    }
}

// MARK: - GaugeStyle

public struct GaugeStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct CurrentValueLabel: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct MinimumValueLabel: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct MaximumValueLabel: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct MarkedValueLabel: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public var value: Double
    public var label: GaugeStyleConfiguration.Label
    public var currentValueLabel: GaugeStyleConfiguration.CurrentValueLabel?
    public var minimumValueLabel: GaugeStyleConfiguration.MinimumValueLabel?
    public var maximumValueLabel: GaugeStyleConfiguration.MaximumValueLabel?
    public var markedValueLabels: [GaugeStyleConfiguration.MarkedValueLabel] = []
}

@MainActor @preconcurrency
public protocol GaugeStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = GaugeStyleConfiguration
}

struct GaugeStyleBox {
    let make: @MainActor (GaugeStyleConfiguration) -> AnyView
}
enum GaugeCustomStyleKey: EnvironmentKey { static let defaultValue: GaugeStyleBox? = nil }
extension EnvironmentValues {
    var gaugeCustomStyleBox: GaugeStyleBox? {
        get { self[GaugeCustomStyleKey.self] }
        set { self[GaugeCustomStyleKey.self] = newValue }
    }
}

struct _GaugeStyleApplier<S: GaugeStyle>: View {
    let style: S
    let configuration: GaugeStyleConfiguration
    var body: some View { style.makeBody(configuration: configuration) }
}

public struct DefaultGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .linearCapacity) }
}
public struct LinearCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .linearCapacity) }
}
public struct AccessoryLinearGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .accessoryLinear) }
}
public struct AccessoryLinearCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .accessoryLinearCapacity) }
}
public struct AccessoryCircularGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .accessoryCircular) }
}
public struct AccessoryCircularCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .accessoryCircularCapacity) }
}
/// watchOS: the open ring (drawn like the accessory circular gauge).
public struct CircularGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .accessoryCircular) }
}
/// watchOS: the linear bar.
public struct LinearGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: GaugeStyleConfiguration) -> some View { _BuiltInGauge(configuration: configuration, kind: .linearCapacity) }
}
extension GaugeStyle where Self == CircularGaugeStyle { public static var circular: CircularGaugeStyle { CircularGaugeStyle() } }
extension GaugeStyle where Self == LinearGaugeStyle { public static var linear: LinearGaugeStyle { LinearGaugeStyle() } }

/// What the built-in gauge styles draw, from a configuration.
struct _BuiltInGauge: View {
    let configuration: GaugeStyleConfiguration
    let kind: GaugeStyleKind.Kind
    var body: some View {
        Gauge(fraction: configuration.value, label: AnyView(configuration.label),
              current: configuration.currentValueLabel.map { AnyView($0) },
              minLabel: configuration.minimumValueLabel.map { AnyView($0) },
              maxLabel: configuration.maximumValueLabel.map { AnyView($0) }, forcedKind: kind)
        as Gauge<EmptyView, EmptyView, EmptyView, EmptyView>
    }
}

// MARK: - DatePickerStyle

public struct DatePickerStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public let label: DatePickerStyleConfiguration.Label
    @Binding public var selection: Date
    public var minimumDate: Date?
    public var maximumDate: Date?
    public var displayedComponents: DatePickerComponents

    init(label: Label, selection: Binding<Date>, minimumDate: Date?, maximumDate: Date?, displayedComponents: DatePickerComponents) {
        self.label = label
        self._selection = selection
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.displayedComponents = displayedComponents
    }
}

@MainActor @preconcurrency
public protocol DatePickerStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = DatePickerStyleConfiguration
}

enum DatePickerKind { case compact, graphical, field, stepperField }
struct DatePickerStyleBox {
    let kind: DatePickerKind
    let make: (@MainActor (DatePickerStyleConfiguration) -> AnyView)?
}
enum DatePickerStyleKey: EnvironmentKey { static let defaultValue: DatePickerStyleBox? = nil }
extension EnvironmentValues {
    var datePickerStyleBox: DatePickerStyleBox? {
        get { self[DatePickerStyleKey.self] }
        set { self[DatePickerStyleKey.self] = newValue }
    }
}

struct _DatePickerStyleApplier<S: DatePickerStyle>: View {
    let style: S
    let configuration: DatePickerStyleConfiguration
    var body: some View { style.makeBody(configuration: configuration) }
}

public struct DefaultDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .compact) }
}
public struct CompactDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .compact) }
}
public struct GraphicalDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .graphical) }
}
/// Drawn like the compact style: the wheel is not simulated.
public struct WheelDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .compact) }
}
/// macOS: a text field with the date and time, editable in place.
public struct FieldDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .field) }
}
/// macOS: the field style plus a stepper.
public struct StepperFieldDatePickerStyle: DatePickerStyle {
    public init() {}
    public func makeBody(configuration: DatePickerStyleConfiguration) -> some View { _BuiltInDatePicker(configuration: configuration, kind: .stepperField) }
}
extension DatePickerStyle where Self == DefaultDatePickerStyle { public static var automatic: DefaultDatePickerStyle { DefaultDatePickerStyle() } }
extension DatePickerStyle where Self == CompactDatePickerStyle { public static var compact: CompactDatePickerStyle { CompactDatePickerStyle() } }
extension DatePickerStyle where Self == GraphicalDatePickerStyle { public static var graphical: GraphicalDatePickerStyle { GraphicalDatePickerStyle() } }
extension DatePickerStyle where Self == WheelDatePickerStyle { public static var wheel: WheelDatePickerStyle { WheelDatePickerStyle() } }
extension DatePickerStyle where Self == FieldDatePickerStyle { public static var field: FieldDatePickerStyle { FieldDatePickerStyle() } }
extension DatePickerStyle where Self == StepperFieldDatePickerStyle { public static var stepperField: StepperFieldDatePickerStyle { StepperFieldDatePickerStyle() } }

extension View {
    /// Compact, graphical, field and stepper-field are drawn; the wheel style is drawn as compact.
    public func datePickerStyle<S: DatePickerStyle>(_ style: S) -> some View {
        env {
            $0.datePickerGraphical = style is GraphicalDatePickerStyle
            switch style {
            case is DefaultDatePickerStyle, is CompactDatePickerStyle, is GraphicalDatePickerStyle, is WheelDatePickerStyle:
                $0.datePickerStyleBox = nil
            case is FieldDatePickerStyle: $0.datePickerStyleBox = DatePickerStyleBox(kind: .field, make: nil)
            case is StepperFieldDatePickerStyle: $0.datePickerStyleBox = DatePickerStyleBox(kind: .stepperField, make: nil)
            default:
                $0.datePickerStyleBox = DatePickerStyleBox(kind: .compact) { configuration in
                    AnyView(_DatePickerStyleApplier(style: style, configuration: configuration))
                }
            }
        }
    }
}

// MARK: - Built-in drawings used by the styles above

struct _BuiltInDatePicker: View {
    let configuration: DatePickerStyleConfiguration
    let kind: DatePickerKind
    var body: some View {
        var picker = DatePicker<DatePickerStyleConfiguration.Label>(
            selection: configuration.$selection, components: configuration.displayedComponents, label: configuration.label,
            minimumDate: configuration.minimumDate, maximumDate: configuration.maximumDate)
        picker.forcedKind = kind
        return picker
    }
}

/// macOS field date picker: the date and time as text in a bordered field, optionally with a stepper.
struct _DateField: View {
    let date: Date
    let components: DatePickerComponents
    let stepper: Bool
    var body: some View {
        var parts: [String] = []
        if components.contains(.date) { parts.append(formatted(date, "M/d/yyyy")) }
        if components.contains(.hourAndMinute) { parts.append(formatted(date, "h:mm a")) }
        return HStack(spacing: 4) {
            Text(verbatim: parts.joined(separator: ", "))
                .font(.system(size: 13)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(SystemColor.background), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(SystemColor.gray3), lineWidth: 1))
            if stepper {
                VStack(spacing: 3) {
                    ChevronShape(direction: .up).stroke(Color(SystemColor.label), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 6, height: 3.5)
                    ChevronShape(direction: .down).stroke(Color(SystemColor.label), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 6, height: 3.5)
                }
                .frame(width: 13, height: 22)
                .background(Color(SystemColor.background), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(SystemColor.gray3), lineWidth: 1))
            }
        }
    }
}

/// What a control group draws for a style that is not the automatic row of buttons; nil for the row.
@MainActor
func _styledControlGroup(_ box: ControlGroupStyleBox, content: AnyView, label: AnyView?) -> AnyView? {
    if let make = box.make { return make(label ?? AnyView(EmptyView()), content) }
    switch box.kind {
    case .automatic, .navigation, .palette:
        return nil
    case .menu, .compactMenu:
        // A menu control group is a closed menu: its label, or the ellipsis button when it has none.
        return AnyView(Menu(content: { content }, label: { label ?? AnyView(Image(systemName: "ellipsis.circle")) }))
    }
}

extension ControlGroup {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(titleKey) })
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Label(titleKey, systemImage: systemImage) })
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Label(title, systemImage: systemImage) })
    }
}

struct _TextEditorBorder: ViewModifier, PrimitiveModifier {
    typealias Body = Never
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        guard ctx.env.textEditorRoundedBorder else { return content.resolve(ctx, into: &out) }
        let view = _ViewModifier_Content<_TextEditorBorder>(content: content)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(SystemColor.gray3), lineWidth: 1))
        resolveView(view, ctx, into: &out)
    }
}
