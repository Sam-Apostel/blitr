// Toggle and its styles.

public struct ToggleStyleConfiguration {
    public struct Label: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
    }
    public let label: ToggleStyleConfiguration.Label
    @Binding public var isOn: Bool
    public var isMixed: Bool = false

    init(label: Label, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }
}

@MainActor @preconcurrency
public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
}

struct ToggleStyleBox {
    let make: @MainActor (AnyView, Binding<Bool>) -> AnyView
}

enum ToggleStyleKey: EnvironmentKey {
    static var defaultValue: ToggleStyleBox { ToggleStyleBox { label, isOn in AnyView(_SwitchToggle(label: label, isOn: isOn)) } }
}
extension EnvironmentValues {
    var toggleStyleBox: ToggleStyleBox {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

struct _ToggleStyleApplier<S: ToggleStyle>: View {
    let style: S
    let label: AnyView
    let isOn: Binding<Bool>
    var body: some View {
        style.makeBody(configuration: ToggleStyleConfiguration(label: .init(view: label), isOn: isOn))
    }
}

public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        _SwitchToggle(label: AnyView(configuration.label), isOn: configuration.$isOn)
    }
}
public struct SwitchToggleStyle: ToggleStyle {
    var tint: Color?
    public init() {}
    public init(tint: Color) { self.tint = tint }
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        _SwitchToggle(label: AnyView(configuration.label), isOn: configuration.$isOn).env { if let t = tint { $0.accentColor = t } }
    }
}
public struct ButtonToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        _ButtonToggle(label: AnyView(configuration.label), isOn: configuration.isOn)
    }
}

extension ToggleStyle where Self == DefaultToggleStyle { public static var automatic: DefaultToggleStyle { DefaultToggleStyle() } }
extension ToggleStyle where Self == SwitchToggleStyle { public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() } }
extension ToggleStyle where Self == ButtonToggleStyle { public static var button: ButtonToggleStyle { ButtonToggleStyle() } }

extension View {
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        env { $0.toggleStyleBox = ToggleStyleBox { label, isOn in AnyView(_ToggleStyleApplier(style: style, label: label, isOn: isOn)) } }
    }
}

// MARK: - Switch drawing

/// The 51x31 iOS switch.
struct SwitchControl: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accentColor) private var accent

    var body: some View {
        let onColor = accent ?? Color(SystemColor.green)
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? onColor : Color(SystemColor.secondaryFill))
            Circle().fill(Color.white).frame(width: 27, height: 27).knobShadow().padding(2)
        }
        .frame(width: 51, height: 31)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct _SwitchToggle: View {
    let label: AnyView
    let isOn: Binding<Bool>
    var body: some View {
        HStack {
            ControlLabel(label: label)
            SwitchControl(isOn: isOn.wrappedValue)
        }
    }
}

struct _ButtonToggle: View {
    let label: AnyView
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        label
            .foregroundStyle(isOn ? Color.white : Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color.accentColor : Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Toggle

public struct Toggle<Label: View>: View {
    let isOn: Binding<Bool>
    let label: Label
    @Environment(\.toggleStyleBox) private var styleBox

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }

    public var body: some View { styleBox.make(AnyView(label), isOn) }
}

extension Toggle where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(titleKey) } }
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(title) } }
}

extension Toggle where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}
