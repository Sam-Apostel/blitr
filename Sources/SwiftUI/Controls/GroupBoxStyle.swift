// GroupBoxStyle: custom group box looks. The built-in look lives in `GroupBox.defaultBody`; a style set
// with `.groupBoxStyle(_:)` replaces it, and `GroupBox(configuration)` inside a style draws the built-in look.

/// Internal: a slot of a style configuration. It resolves to the view the styled control passed in.
protocol _StyleSlot: PrimitiveView {
    var view: AnyView { get }
}
extension _StyleSlot {
    @MainActor func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
}

public struct GroupBoxStyleConfiguration {
    public struct Label: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Content: View, _StyleSlot {
        public typealias Body = Never
        let view: AnyView
    }
    public let label: GroupBoxStyleConfiguration.Label
    public let content: GroupBoxStyleConfiguration.Content
}

@MainActor @preconcurrency
public protocol GroupBoxStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = GroupBoxStyleConfiguration
}

struct GroupBoxStyleBox {
    let make: @MainActor (AnyView, AnyView) -> AnyView
}

enum GroupBoxStyleKey: EnvironmentKey { static let defaultValue: GroupBoxStyleBox? = nil }
extension EnvironmentValues {
    var groupBoxStyleBox: GroupBoxStyleBox? {
        get { self[GroupBoxStyleKey.self] }
        set { self[GroupBoxStyleKey.self] = newValue }
    }
}

struct _GroupBoxStyleApplier<S: GroupBoxStyle>: View {
    let style: S
    let label: AnyView
    let content: AnyView
    var body: some View {
        style.makeBody(configuration: GroupBoxStyleConfiguration(label: .init(view: label), content: .init(view: content)))
    }
}

public struct DefaultGroupBoxStyle: GroupBoxStyle {
    public init() {}
    public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View { GroupBox(configuration) }
}

extension GroupBoxStyle where Self == DefaultGroupBoxStyle {
    public static var automatic: DefaultGroupBoxStyle { DefaultGroupBoxStyle() }
}

extension GroupBox where Label == GroupBoxStyleConfiguration.Label, Content == GroupBoxStyleConfiguration.Content {
    /// Draws the built-in look from a style configuration (what `.automatic` does).
    public init(_ configuration: GroupBoxStyleConfiguration) {
        self.init(content: { configuration.content }, label: { configuration.label })
        self.forceDefault = true
    }
}

extension View {
    public func groupBoxStyle<S: GroupBoxStyle>(_ style: S) -> some View {
        env {
            if style is DefaultGroupBoxStyle { $0.groupBoxStyleBox = nil; return }
            $0.groupBoxStyleBox = GroupBoxStyleBox { label, content in
                AnyView(_GroupBoxStyleApplier(style: style, label: label, content: content))
            }
        }
    }
}
