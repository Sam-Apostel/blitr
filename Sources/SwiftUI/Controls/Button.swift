
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
    static var defaultValue: ButtonStyleBox { ButtonStyleBox { label, role, _ in AnyView(_ButtonVisual(kind: .borderless, label: label, role: role)) } }
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
        _ButtonVisual(kind: .borderless, label: AnyView(configuration.label), role: configuration.role)
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

    init(_ size: ControlSize) {
        switch size {
        case .mini: (h, v, radius, font, weight) = (8, 3, 7, .system(size: 12), nil)
        case .small: (h, v, radius, font, weight) = (10, 4, 8, .system(size: 15), nil)
        case .regular: (h, v, radius, font, weight) = (12, 7, 8, nil, nil)
        case .large: (h, v, radius, font, weight) = (20, 14, 12, nil, .semibold)
        case .extraLarge: (h, v, radius, font, weight) = (24, 16, 14, .system(size: 20), .semibold)
        }
    }
}

struct _ButtonVisual: View {
    enum Kind { case plain, borderless, bordered, prominent }
    let kind: Kind
    let label: AnyView
    let role: ButtonRole?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var size
    @Environment(\.buttonBorderShape) private var borderShape
    @Environment(\.accentColor) private var explicitAccent
    @Environment(\.foregroundStyle) private var explicitForeground
    @Environment(\.font) private var userFont

    private var destructive: Bool { role == .destructive }

    private func shape(_ m: ButtonMetrics) -> AnyShape {
        switch borderShape.kind {
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        case .rounded(let r?): return AnyShape(RoundedRectangle(cornerRadius: r))
        case .rounded(nil), .automatic: return AnyShape(RoundedRectangle(cornerRadius: m.radius))
        }
    }

    private var styled: AnyView {
        let m = ButtonMetrics(size)
        let tinted = destructive || explicitAccent != nil
        let disabledColor = Color(SystemColor.tertiaryLabel)
        var content = label
        if let f = userFont ?? m.font { content = AnyView(content.font(f)) }
        if let w = m.weight { content = AnyView(content.fontWeight(w)) }

        switch kind {
        case .plain:
            return AnyView(content.opacity(isEnabled ? 1 : 0.3))
        case .borderless:
            if !isEnabled { return AnyView(content.foregroundStyle(disabledColor)) }
            if explicitForeground != nil && !destructive { return content }
            return AnyView(content.foregroundStyle(Color.accentColor))
        case .bordered:
            let fill = tinted ? Color.accentColor.opacity(0.15) : Color(SystemColor.tertiaryFill)
            let foreground: Color = isEnabled ? Color.accentColor : disabledColor
            return AnyView(
                content
                    .foregroundStyle(foreground)
                    .padding(.horizontal, m.h).padding(.vertical, m.v)
                    .background(fill, in: shape(m)))
        case .prominent:
            let fill: Color = isEnabled ? Color.accentColor : Color(SystemColor.tertiaryFill)
            let foreground: Color = isEnabled ? .white : disabledColor
            return AnyView(
                content
                    .foregroundStyle(foreground)
                    .padding(.horizontal, m.h).padding(.vertical, m.v)
                    .background(fill, in: shape(m)))
        }
    }

    var body: some View {
        styled.env { if destructive { $0.accentColor = Color.red } }
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
        styleBox.make(AnyView(label), role, action)
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
    public var body: some View { label.foregroundStyle(Color.accentColor) }
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
        Button(action: primaryAction ?? {}) { label }
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

public struct MenuStyle: Sendable {
    let raw: Int
    public static let automatic = MenuStyle(raw: 0)
    public static let button = MenuStyle(raw: 1)
    public static let borderlessButton = MenuStyle(raw: 2)
}
extension View {
    /// Menus are always drawn closed, so the style has no effect on a screenshot.
    public func menuStyle(_ style: MenuStyle) -> some View { self }
}
