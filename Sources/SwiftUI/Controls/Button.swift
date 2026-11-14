
// Button, its styles, and the pieces that depend on it (Link, Menu).

public struct ButtonRole: Equatable, Sendable {
    let raw: Int
    public static let destructive = ButtonRole(raw: 0)
    public static let cancel = ButtonRole(raw: 1)
    public static let close = ButtonRole(raw: 2)
    public static let confirm = ButtonRole(raw: 3)
}

// MARK: - Border shape

public struct ButtonBorderShape: Shape, Equatable {
    enum Kind: Equatable, Sendable { case automatic, capsule, circle, rounded(CGFloat?) }
    let kind: Kind
    public static let automatic = ButtonBorderShape(kind: .automatic)
    public static let capsule = ButtonBorderShape(kind: .capsule)
    public static let circle = ButtonBorderShape(kind: .circle)
    public static let roundedRectangle = ButtonBorderShape(kind: .rounded(nil))
    public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { ButtonBorderShape(kind: .rounded(radius)) }

    public nonisolated func path(in rect: CGRect) -> Path {
        switch kind {
        case .capsule: return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .circular)
        case .circle:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .automatic: return Path(roundedRect: rect, cornerRadius: 8)
        case .rounded(let r): return Path(roundedRect: rect, cornerRadius: r ?? 8)
        }
    }
}

enum ButtonBorderShapeKey: EnvironmentKey { static let defaultValue = ButtonBorderShape.automatic }
extension EnvironmentValues {
    public var buttonBorderShape: ButtonBorderShape {
        get { self[ButtonBorderShapeKey.self] }
        set { self[ButtonBorderShapeKey.self] = newValue }
    }
}
extension View {
    public func buttonBorderShape(_ shape: ButtonBorderShape) -> some View { env { $0.buttonBorderShape = shape } }
}

// MARK: - Style protocols

public struct ButtonStyleConfiguration {
    public struct Label: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
    }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    let action: @MainActor () -> Void
    @MainActor public func trigger() { action() }
}

@MainActor @preconcurrency
public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

/// The style in the environment, type-erased.
struct ButtonStyleBox {
    let make: @MainActor (AnyView, ButtonRole?, @escaping @MainActor () -> Void) -> AnyView
}

enum ButtonStyleKey: EnvironmentKey {
    static var defaultValue: ButtonStyleBox { ButtonStyleBox { label, role, _ in AnyView(_ButtonVisual(kind: .automatic, label: label, role: role)) } }
}

extension EnvironmentValues {
    var buttonStyleBox: ButtonStyleBox {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

struct _ButtonStyleApplier<S: ButtonStyle>: View {
    let style: S
    let label: AnyView
    let role: ButtonRole?
    var body: some View {
        style.makeBody(configuration: ButtonStyleConfiguration(role: role, label: .init(view: label), isPressed: false))
    }
}

struct _PrimitiveButtonStyleApplier<S: PrimitiveButtonStyle>: View {
    let style: S
    let label: AnyView
    let role: ButtonRole?
    let action: @MainActor () -> Void
    var body: some View {
        style.makeBody(configuration: PrimitiveButtonStyleConfiguration(role: role, label: .init(view: label), action: action))
    }
}

extension View {
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        env { $0.buttonStyleBox = ButtonStyleBox { label, role, _ in AnyView(_ButtonStyleApplier(style: style, label: label, role: role)) } }
    }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        env { $0.buttonStyleBox = ButtonStyleBox { label, role, action in
            AnyView(_PrimitiveButtonStyleApplier(style: style, label: label, role: role, action: action))
        } }
    }
}

// MARK: - Built-in styles

public struct DefaultButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .automatic, label: AnyView(configuration.label), role: configuration.role)
    }
}
public struct BorderlessButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .borderless, label: AnyView(configuration.label), role: configuration.role)
    }
}
public struct PlainButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .plain, label: AnyView(configuration.label), role: configuration.role)
    }
}
public struct BorderedButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .bordered, label: AnyView(configuration.label), role: configuration.role)
    }
}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .prominent, label: AnyView(configuration.label), role: configuration.role)
    }
}

extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { DefaultButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() } }

// MARK: - The visual shared by the built-in styles

struct ButtonMetrics {
    var h: CGFloat, v: CGFloat, radius: CGFloat
    var font: Font?
    var weight: Font.Weight?
    /// Minimum height of the bordered/glass background (glass designs; nil keeps the padding-derived height).
    var minHeight: CGFloat?

    init(_ size: ControlSize, design: DesignLanguage = .flat) {
        minHeight = nil
        if design.isGlass {
            // iOS 26: capsule buttons with fixed heights; the horizontal padding grows with the rounder ends.
            // All estimates (est.), shared by iOS 26 and 27.
            switch size {
            case .mini: (h, v, radius, font, weight, minHeight) = (10, 3, 12, .system(size: 12), nil, 24)
            case .small: (h, v, radius, font, weight, minHeight) = (12, 4, 14, .system(size: 15), nil, 28)
            case .regular: (h, v, radius, font, weight, minHeight) = (16, 7, 18, nil, nil, 36)
            case .large: (h, v, radius, font, weight, minHeight) = (24, 14, 26, nil, .semibold, 52)
            case .extraLarge: (h, v, radius, font, weight, minHeight) = (28, 16, 30, .system(size: 20), .semibold, 60)
            }
            return
        }
        switch size {
        case .mini: (h, v, radius, font, weight) = (8, 3, 7, .system(size: 12), nil)
        case .small: (h, v, radius, font, weight) = (10, 4, 8, .system(size: 15), nil)
        case .regular: (h, v, radius, font, weight) = (12, 7, 8, nil, nil)
        case .large: (h, v, radius, font, weight) = (20, 14, 12, nil, .semibold)
        case .extraLarge: (h, v, radius, font, weight) = (24, 16, 14, .system(size: 20), .semibold)
        }
    }
}

// MARK: - Glass styles and sizing (iOS 26)

/// A neutral Liquid Glass capsule with a primary-colored label. Renders as `.bordered` before iOS 26.
public struct GlassButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .glass, label: AnyView(configuration.label), role: configuration.role)
    }
}
/// Accent-tinted Liquid Glass with a white label. Renders as `.borderedProminent` before iOS 26.
public struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .glassProminent, label: AnyView(configuration.label), role: configuration.role)
    }
}
extension PrimitiveButtonStyle where Self == GlassButtonStyle { public static var glass: GlassButtonStyle { GlassButtonStyle() } }
extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle { public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() } }

public struct ButtonSizing: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case automatic, flexible, fitted }
    let kind: Kind
    public static let automatic = ButtonSizing(kind: .automatic)
    /// Fills the width the parent offers.
    public static let flexible = ButtonSizing(kind: .flexible)
    /// Sizes to the label.
    public static let fitted = ButtonSizing(kind: .fitted)
}
enum ButtonSizingKey: EnvironmentKey { static let defaultValue = ButtonSizing.automatic }
extension EnvironmentValues {
    var buttonSizing: ButtonSizing {
        get { self[ButtonSizingKey.self] }
        set { self[ButtonSizingKey.self] = newValue }
    }
}
extension View {
    public func buttonSizing(_ sizing: ButtonSizing) -> some View { env { $0.buttonSizing = sizing } }
}

struct _ButtonVisual: View {
    /// `automatic` is borderless on iOS and bordered on tvOS; `card` exists on tvOS only.
    enum Kind { case automatic, plain, borderless, bordered, prominent, glass, glassProminent, card }
    let kind: Kind
    let label: AnyView
    let role: ButtonRole?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var size
    @Environment(\.buttonBorderShape) private var borderShape
    @Environment(\.buttonSizing) private var sizing
    @Environment(\.designLanguage) private var design
    @Environment(\.accentColor) private var explicitAccent
    @Environment(\.foregroundStyle) private var explicitForeground
    @Environment(\.font) private var userFont
    @Environment(\.renderPlatform) private var platform

    private var destructive: Bool { role == .destructive }

    private func shape(_ m: ButtonMetrics) -> AnyShape {
        switch borderShape.kind {
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        case .rounded(let r?): return AnyShape(RoundedRectangle(cornerRadius: r))
        case .rounded(nil), .automatic:
            // iOS 26: bordered buttons default to a capsule.
            return design.isGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: m.radius))
        }
    }

    private var styled: AnyView {
        let m = ButtonMetrics(size, design: design)
        let tinted = destructive || explicitAccent != nil
        let disabledColor = Color(SystemColor.tertiaryLabel)
        var content = label
        if let f = userFont ?? m.font { content = AnyView(content.font(f)) }
        if let w = m.weight { content = AnyView(content.fontWeight(w)) }

        switch kind {
        case .plain:
            return AnyView(content.opacity(isEnabled ? 1 : 0.3))
        case .card:
            Runtime.current?.warn(".buttonStyle(.card) is tvOS only; a real iOS build fails. Drawn like .plain")
            return AnyView(content.opacity(isEnabled ? 1 : 0.3))
        case .borderless, .automatic:
            if !isEnabled { return AnyView(content.foregroundStyle(disabledColor)) }
            if explicitForeground != nil && !destructive { return content }
            return AnyView(content.foregroundStyle(Color.accentColor))
        case .bordered:
            // Before iOS 26 the glass styles look like their bordered counterparts.
            let fill = tinted ? Color.accentColor.opacity(0.15) : Color(SystemColor.tertiaryFill)
            let foreground: Color = isEnabled ? Color.accentColor : disabledColor
            return AnyView(
                padded(content.foregroundStyle(foreground), m)
                    .background(fill, in: shape(m)))
        case .prominent:
            let fill: Color = isEnabled ? Color.accentColor : Color(SystemColor.tertiaryFill)
            let foreground: Color = isEnabled ? .white : disabledColor
            return AnyView(
                padded(content.foregroundStyle(foreground), m)
                    .background(fill, in: shape(m)))
        case .glass:
            guard design.isGlass else { return AnyView(_ButtonVisual(kind: .bordered, label: label, role: role)) }
            let foreground: Color = !isEnabled ? disabledColor : (tinted ? Color.accentColor : Color(SystemColor.label))
            return AnyView(
                padded(content.foregroundStyle(foreground), m)
                    .modifier(ControlGlassSurface(prominent: false, borderShape: borderShape, enabled: isEnabled)))
        case .glassProminent:
            guard design.isGlass else { return AnyView(_ButtonVisual(kind: .prominent, label: label, role: role)) }
            let foreground: Color = isEnabled ? .white : disabledColor
            let semibold = design == .liquidGlass27
            return AnyView(
                padded(semibold ? AnyView(content.fontWeight(.semibold).foregroundStyle(foreground)) : AnyView(content.foregroundStyle(foreground)), m)
                    .modifier(ControlGlassSurface(prominent: true, borderShape: borderShape, enabled: isEnabled)))
        }
    }

    /// The label with the style's padding; glass designs add the fixed control height, and
    /// `.buttonSizing(.flexible)` stretches the button over the available width.
    private func padded<V: View>(_ content: V, _ m: ButtonMetrics) -> AnyView {
        let padded = content.padding(.horizontal, m.h).padding(.vertical, m.v)
        switch (m.minHeight, sizing.kind) {
        case (nil, .flexible): return AnyView(padded.frame(maxWidth: .infinity))
        case (let h?, .flexible): return AnyView(padded.frame(minHeight: h).frame(maxWidth: .infinity))
        case (let h?, _): return AnyView(padded.frame(minHeight: h))
        case (nil, _): return AnyView(padded)
        }
    }

    var body: some View {
        if platform == .tvOS { return AnyView(_TVButtonVisual(kind: kind, label: label, role: role)) }
        return AnyView(styled.env { if destructive { $0.accentColor = Color.red } })
    }
}

// MARK: - Button

public struct Button<Label: View>: View {
    let action: @MainActor () -> Void
    let role: ButtonRole?
    let label: Label
    @Environment(\.buttonStyleBox) private var styleBox

    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.role = nil
        self.label = label()
    }
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.role = role
        self.label = label()
    }

    public var body: some View {
        let styled = styleBox.make(AnyView(label), role, action)
            .axInfo(shared: true, context: { ctx in .button(enabled: ctx.env.isEnabled, activate: action) })
            .focusElement(role: "button", activate: action)
        // Alerts and confirmation dialogs read the role off the action's nodes.
        if role == .cancel {
            styled.trait(PresentationActionRoleTraitKey.self, .cancel)
        } else if role == .destructive {
            styled.trait(PresentationActionRoleTraitKey.self, .destructive)
        } else {
            styled
        }
    }
}

extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
        self.init(role: nil, action: action) { Text(titleKey) }
    }
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
        self.init(role: nil, action: action) { Text(title) }
    }
    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, action: @escaping @MainActor () -> Void) {
        self.init(role: nil, action: action) { SwiftUI.Label(titleKey, systemImage: name) }
    }
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(titleKey, systemImage: name) }
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String, action: @escaping @MainActor () -> Void) {
        self.init(role: nil, action: action) { SwiftUI.Label(title, systemImage: name) }
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, systemImage: name) }
    }
}

// MARK: - Link

public struct Link<Label: View>: View {
    let destination: URL
    let label: Label
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }
    @Environment(\.renderPlatform) private var platform

    public var body: some View {
        // tvOS draws a link like a button (it cannot open URLs; est. look).
        (platform == .tvOS ? AnyView(_TVButtonVisual(kind: .automatic, label: AnyView(label), role: nil))
                           : AnyView(label.foregroundStyle(Color.accentColor)))
            .axInfo(shared: true, context: { ctx in
                AccessibilityInfo {
                    $0.isElement = true
                    $0.addTraits = [.link]
                    $0.children = .combine
                    $0.isTapTarget = true
                    $0.isEnabled = ctx.env.isEnabled
                }
            })
            .focusElement(role: "link", activate: { [destination] in
                Runtime.current?.warn("select on Link(\(destination.absoluteString)) would open the URL; nothing to show here")
            })
    }
}

extension Link where Label == Text {
    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.init(destination: destination) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.init(destination: destination) { Text(title) }
    }
}

// MARK: - Menu

public struct Menu<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    let primaryAction: (@MainActor () -> Void)?
    @Environment(\.menuStyleBox) private var customStyle
    var forceDefault = false

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
        self.primaryAction = nil
    }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping @MainActor () -> Void) {
        self.content = content()
        self.label = label()
        self.primaryAction = primaryAction
    }

    /// A closed menu looks like a button with the menu's label; the items are not shown.
    public var body: some View {
        if let custom = customStyle, !forceDefault {
            custom.make(AnyView(label), AnyView(content))
        } else {
            Button(action: primaryAction ?? {}) { _MenuLabel(label: label) }
                .axInfo(shared: true) { $0.addTraits = [.hasPopup] }
        }
    }
}

extension Menu where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(titleKey, systemImage: name) }
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(title, systemImage: name) }
    }
}
