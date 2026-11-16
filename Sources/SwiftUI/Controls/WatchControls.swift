// watchOS SwiftUI API: TextFieldLink and the vertical paging tab view style.

/// watchOS: a button that opens text input. Drawn as the button it is.
public struct TextFieldLink<Label: View>: View {
    let label: Label
    let onSubmit: (String) -> Void

    public init(prompt: Text? = nil, @ViewBuilder label: () -> Label, onSubmit: @escaping (String) -> Void) {
        self.label = label()
        self.onSubmit = onSubmit
    }

    public var body: some View {
        Button(action: { Runtime.current?.warn("TextFieldLink would open text input; nothing is entered here") }) { label }
    }
}

extension TextFieldLink where Label == Text {
    public init(_ titleKey: LocalizedStringKey, prompt: Text? = nil, onSubmit: @escaping (String) -> Void) {
        self.init(prompt: prompt, label: { Text(titleKey) }, onSubmit: onSubmit)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, prompt: Text? = nil, onSubmit: @escaping (String) -> Void) {
        self.init(prompt: prompt, label: { Text(title) }, onSubmit: onSubmit)
    }
}

extension TextFieldLink where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, prompt: Text? = nil, onSubmit: @escaping (String) -> Void) {
        self.init(prompt: prompt, label: { SwiftUI.Label(titleKey, systemImage: systemImage) }, onSubmit: onSubmit)
    }
}

/// watchOS: pages stacked vertically, scrolled with the Digital Crown; a page indicator at the trailing edge.
public struct VerticalPageTabViewStyle: TabViewStyle {
    public struct TransitionStyle: Hashable, Sendable {
        let raw: Int
        public static let automatic = TransitionStyle(raw: 0)
        public static let blur = TransitionStyle(raw: 1)
        public static let identity = TransitionStyle(raw: 2)
    }
    public init() {}
    public init(transitionStyle: TransitionStyle) {}
}
extension TabViewStyle where Self == VerticalPageTabViewStyle {
    public static var verticalPage: VerticalPageTabViewStyle { VerticalPageTabViewStyle() }
    public static func verticalPage(transitionStyle: VerticalPageTabViewStyle.TransitionStyle) -> VerticalPageTabViewStyle {
        VerticalPageTabViewStyle(transitionStyle: transitionStyle)
    }
}

enum TabViewVerticalPageKey: EnvironmentKey { static let defaultValue = false }

/// watchOS buttons: `automatic` and `bordered` are capsules on a translucent gray platter,
/// `borderedProminent` fills the capsule with the accent; the label in the body font, centred.
/// watchOS 26 (measured: watchOS 26.5 simulator): 52.5pt tall and at most 178pt wide on the 46mm screen,
/// 48 x 161 on the 42mm one, 54 x 174 on the Ultra 2 (`WatchMetrics`). Earlier versions (estimates from
/// watchOS 10/11 screenshots): full width, 44pt tall on the 42mm screen, 48pt on the bigger ones.
struct _WatchButtonVisual: View {
    let kind: _ButtonVisual.Kind
    let label: AnyView
    let role: ButtonRole?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accentColor) private var explicitAccent
    @Environment(\.foregroundStyle) private var explicitForeground

    var body: some View {
        switch kind {
        case .plain, .card:
            return AnyView(label.opacity(isEnabled ? 1 : 0.3))
        case .borderless:
            return AnyView(label.foregroundStyle(role == .destructive ? Color.red : Color.accentColor).opacity(isEnabled ? 1 : 0.3))
        case .automatic, .bordered, .glass, .prominent, .glassProminent:
            let prominent = kind == .prominent || kind == .glassProminent
            let measured = RenderedPlatform.current >= 26 ? WatchMetrics.current : nil
            let height: CGFloat = measured?.buttonHeight ?? (RenderedPlatform.watchTextIsExtraLarge ? 48 : 44)
            let fill: Color = prominent ? Color.accentColor
                : role == .destructive ? Color.red.opacity(0.25)
                : explicitAccent != nil ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.14)
            var content = label
            if explicitForeground == nil {
                content = AnyView(content.foregroundStyle(prominent ? Color.black : role == .destructive ? Color.red : Color.white))
            }
            return AnyView(
                content
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: measured?.buttonMaxWidth ?? .infinity, minHeight: height)
                    .background(fill, in: Capsule())
                    .opacity(isEnabled ? 1 : 0.4))
        }
    }
}
