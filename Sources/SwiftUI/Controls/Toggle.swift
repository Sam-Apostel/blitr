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
        _SwitchToggle(label: AnyView(configuration.label), isOn: configuration.$isOn, explicitSwitch: true).env { if let t = tint { $0.accentColor = t } }
    }
}
public struct ButtonToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        _ButtonToggle(label: AnyView(configuration.label), isOn: configuration.isOn)
    }
}

/// tvOS has no button toggle style; draws the tvOS toggle and warns.
struct _ButtonToggleOnTV: View {
    let label: AnyView
    let isOn: Bool
    var body: some View {
        Runtime.current?.warn("ToggleStyle.button is not available on tvOS: a real tvOS build fails to compile. Drawn as the tvOS toggle")
        return _TVToggle(label: label, isOn: isOn, showsSwitch: false)
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
    @Environment(\.designLanguage) private var design
    @Environment(\.isElevatedPresentation) private var inSheet

    var body: some View {
        let onColor = accent ?? Color(SystemColor.green)
        if design.isGlass {
            // iOS 26/27: 63x28 capsule track with a 37x24 pill knob.
            let m = ControlGlassMetrics.self
            let offTrack = inSheet ? m.sheetToggleOffTrack(design) : m.toggleOffTrack
            return AnyView(ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? onColor : Color(offTrack))
                Capsule().fill(Color.white)
                    .frame(width: m.toggleKnob.width, height: m.toggleKnob.height).padding(m.toggleKnobInset)
            }
            .frame(width: m.toggleTrack.width, height: m.toggleTrack.height)
            .frame(width: m.toggleLayoutWidth, alignment: .leading)
            .opacity(isEnabled ? 1 : 0.5))
        }
        return AnyView(flatBody(onColor))
    }

    private func flatBody(_ onColor: Color) -> some View {
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
    /// `.toggleStyle(.switch)` (tvOS draws its own toggle unless a switch is asked for).
    var explicitSwitch = false
    @Environment(\.renderPlatform) private var platform
    var body: some View {
        if platform == .tvOS { return AnyView(_TVToggle(label: label, isOn: isOn.wrappedValue, showsSwitch: explicitSwitch)) }
        return AnyView(HStack {
            ControlLabel(label: label)
            SwitchControl(isOn: isOn.wrappedValue)
        })
    }
}

struct _ButtonToggle: View {
    let label: AnyView
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.renderPlatform) private var platform
    var body: some View {
        if platform == .tvOS { return AnyView(_ButtonToggleOnTV(label: label, isOn: isOn)) }
        if design.isGlass {
            // measured: iOS 27.0 simulator (ControlsIndicators): on, a bordered capsule with the
            // tint at 18% / 25% behind a tint-coloured label (D1EAFF on white); off, plain bordered.
            let fill = isOn
                ? Color.accentColor.opacity(colorScheme == .dark ? ButtonColors.tintedFillDark : ButtonColors.tintedFillLight)
                : Color(SystemColor.secondaryFill)
            return AnyView(label
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(fill, in: Capsule())
                .opacity(isEnabled ? 1 : 0.4))
        }
        return AnyView(label
            .foregroundStyle(isOn ? Color.white : Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color.accentColor : Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4))
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

    public var body: some View {
        let on = isOn.wrappedValue
        return styleBox.make(AnyView(label), isOn)
            .axInfo(shared: true, context: { ctx in
                AccessibilityInfo {
                    $0.isElement = true
                    $0.role = "switch"
                    $0.addTraits = [.toggle]
                    $0.children = .combine
                    $0.value = on ? "1" : "0"
                    $0.isTapTarget = true
                    $0.systemHitSlop = true
                    $0.isEnabled = ctx.env.isEnabled
                    $0.activate = { isOn.wrappedValue.toggle() }
                }
            })
            .focusElement(role: "toggle", activate: { isOn.wrappedValue.toggle() })
            .interaction(.toggle(isOn))
    }
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
