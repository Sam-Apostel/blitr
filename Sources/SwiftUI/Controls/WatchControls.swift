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
