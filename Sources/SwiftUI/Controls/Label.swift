
// Label, LabelStyle, LabeledContent, ShareLink.

// MARK: - LabelStyle

public struct LabelStyleConfiguration {
    public struct Title: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
    }
    public struct Icon: View, PrimitiveView {
        public typealias Body = Never
        let view: AnyView
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) { view.resolve(ctx, into: &out) }
    }
    public var title: LabelStyleConfiguration.Title
    public var icon: LabelStyleConfiguration.Icon
}

@MainActor @preconcurrency
public protocol LabelStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

struct LabelStyleBox {
    let make: @MainActor (AnyView, AnyView) -> AnyView
}

enum LabelStyleKey: EnvironmentKey {
    static var defaultValue: LabelStyleBox { LabelStyleBox { title, icon in AnyView(_DefaultLabelLayout(title: title, icon: icon)) } }
}
extension EnvironmentValues {
    var labelStyleBox: LabelStyleBox {
        get { self[LabelStyleKey.self] }
        set { self[LabelStyleKey.self] = newValue }
    }
}

/// Icon then title, like `.titleAndIcon`.
struct _DefaultLabelLayout: View {
    let title: AnyView
    let icon: AnyView
    @Environment(\.designLanguage) private var design
    @Environment(\.renderPlatform) private var platform
    /// measured: iOS 27.0 simulator: titles start 1.67 to 2.67pt (2.25 on average) further from
    /// the icon than with a 6pt gap (heart, star.fill, globe, apple.logo labels in
    /// ControlsButtons and 04_Login).
    static let glassSpacing: CGFloat = 8.33
    /// In a list row the icon sits in a column, so the titles of rows line up whatever their icons:
    /// the icon is centred `listIconCenter` from the label's leading edge at the large image scale, and
    /// the title starts `listTitleInset` from it (where the row's separator starts).
    /// measured: iOS 27.0 simulator (SplitView tray icons centred at 44pt and titles at 72pt in rows starting at 32pt;
    /// the same for 10_Agenda's caption-sized mappin labels; icons 1.28x their size outside a list)
    static let listIconCenter: CGFloat = 12
    static let listTitleInset: CGFloat = 40
    @Environment(\.isInListRow) private var inListRow
    var body: some View {
        if design.isGlass && platform != .tvOS && inListRow {
            // The larger icon does not make the row taller: it is centred on the title's line.
            title.padding(.leading, Self.listTitleInset)
                .overlay(alignment: .leading) { icon.imageScale(.large).frame(width: Self.listIconCenter * 2) }
        } else {
            HStack(spacing: design.isGlass && platform != .tvOS ? Self.glassSpacing : 6) { icon; title }
        }
    }
}

struct _LabelStyleApplier<S: LabelStyle>: View {
    let style: S
    let title: AnyView
    let icon: AnyView
    var body: some View {
        style.makeBody(configuration: LabelStyleConfiguration(title: .init(view: title), icon: .init(view: icon)))
    }
}

public struct AutomaticLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: LabelStyleConfiguration) -> some View {
        _DefaultLabelLayout(title: AnyView(configuration.title), icon: AnyView(configuration.icon))
    }
}
public struct TitleAndIconLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: LabelStyleConfiguration) -> some View {
        _DefaultLabelLayout(title: AnyView(configuration.title), icon: AnyView(configuration.icon))
    }
}
public struct TitleOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: LabelStyleConfiguration) -> some View { configuration.title }
}
public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: LabelStyleConfiguration) -> some View { configuration.icon }
}

extension LabelStyle where Self == AutomaticLabelStyle { public static var automatic: AutomaticLabelStyle { AutomaticLabelStyle() } }
extension LabelStyle where Self == TitleAndIconLabelStyle { public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() } }
extension LabelStyle where Self == TitleOnlyLabelStyle { public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() } }
extension LabelStyle where Self == IconOnlyLabelStyle { public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() } }

extension View {
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        env { $0.labelStyleBox = LabelStyleBox { title, icon in AnyView(_LabelStyleApplier(style: style, title: title, icon: icon)) } }
    }
}

// MARK: - Label

public struct Label<Title: View, Icon: View>: View {
    let title: Title
    let icon: Icon
    @Environment(\.labelStyleBox) private var styleBox

    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public init(_ configuration: LabelStyleConfiguration) where Title == LabelStyleConfiguration.Title, Icon == LabelStyleConfiguration.Icon {
        self.title = configuration.title
        self.icon = configuration.icon
    }

    public var body: some View {
        let titleText = axPlainString(title)
        return styleBox.make(AnyView(title), AnyView(icon.axInfo { $0.hidden = true }))
            .axInfo(shared: true) {
                $0.isElement = true
                $0.children = .combine
                $0.label = titleText
            }
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(systemName: name) })
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String) {
        self.init(title: { Text(title) }, icon: { Image(systemName: name) })
    }
    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(name) })
    }
    public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(title: { Text(title) }, icon: { Image(name) })
    }
}

// MARK: - LabeledContent

public struct LabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    @Environment(\.labeledContentStyleBox) private var customStyle
    var forceDefault = false
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }
    public var body: some View {
        if let custom = customStyle, !forceDefault {
            custom.make(AnyView(label), AnyView(content))
                .axInfo { $0.isElement = true; $0.children = .combine }
        } else {
            defaultBody
        }
    }
    private var defaultBody: some View {
        HStack {
            label
            Spacer(minLength: 8)
            content.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .axInfo { $0.isElement = true; $0.children = .combine }
    }
}

extension LabeledContent where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) {
        self.init(content: { Text(value) }) { Text(titleKey) }
    }
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.init(content: { Text(value) }) { Text(title) }
    }
    public init<F: FormatStyle>(_ titleKey: LocalizedStringKey, value: F.FormatInput, format: F)
    where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(content: { Text(value, format: format) }) { Text(titleKey) }
    }
    public init<S: StringProtocol, F: FormatStyle>(_ title: S, value: F.FormatInput, format: F)
    where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(content: { Text(value, format: format) }) { Text(title) }
    }
}

// MARK: - ShareLink

/// Stand-in for the framework protocol; real conformances declare a `transferRepresentation`.
public protocol Transferable {}
extension String: Transferable {}
extension URL: Transferable {}
extension Data: Transferable {}
extension Image: Transferable {}
extension Never: Transferable {}

public struct SharePreview<Image: Transferable, Icon: Transferable> {
    let title: Text
    public init(_ title: LocalizedStringKey) where Image == Never, Icon == Never { self.title = Text(title) }
    public init<S: StringProtocol>(_ title: S) where Image == Never, Icon == Never { self.title = Text(title) }
    public init(_ title: LocalizedStringKey, image: Image) where Icon == Never { self.title = Text(title) }
    public init<S: StringProtocol>(_ title: S, image: Image) where Icon == Never { self.title = Text(title) }
    public init(_ title: LocalizedStringKey, icon: Icon) where Image == Never { self.title = Text(title) }
    public init<S: StringProtocol>(_ title: S, icon: Icon) where Image == Never { self.title = Text(title) }
    public init(_ title: LocalizedStringKey, image: Image, icon: Icon) { self.title = Text(title) }
    public init<S: StringProtocol>(_ title: S, image: Image, icon: Icon) { self.title = Text(title) }
}

public struct DefaultShareLinkLabel: View {
    public var body: some View { Label("Share", systemImage: "square.and.arrow.up") }
}

public struct ShareLink<Data, PreviewImage, PreviewIcon, Label>: View
where Data: RandomAccessCollection, Data.Element: Transferable, PreviewImage: Transferable, PreviewIcon: Transferable, Label: View {
    let label: Label
    private let _tvOSCheck = tvOSUnavailable("ShareLink")

    init(label: Label) { self.label = label }

    public var body: some View {
        Button(action: {}) { label }
    }
}

extension ShareLink where Data == CollectionOfOne<String>, PreviewImage == Never, PreviewIcon == Never, Label == DefaultShareLinkLabel {
    public init(item: String, subject: Text? = nil, message: Text? = nil) { self.init(label: DefaultShareLinkLabel()) }
}
extension ShareLink where Data == CollectionOfOne<URL>, PreviewImage == Never, PreviewIcon == Never, Label == DefaultShareLinkLabel {
    public init(item: URL, subject: Text? = nil, message: Text? = nil) { self.init(label: DefaultShareLinkLabel()) }
}
extension ShareLink where Label == DefaultShareLinkLabel {
    public init<I: Transferable>(item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview<PreviewImage, PreviewIcon>)
    where Data == CollectionOfOne<I> {
        self.init(label: DefaultShareLinkLabel())
    }
    public init(items: Data, subject: Text? = nil, message: Text? = nil, preview: @escaping (Data.Element) -> SharePreview<PreviewImage, PreviewIcon>) {
        self.init(label: DefaultShareLinkLabel())
    }
}
extension ShareLink where Data == CollectionOfOne<String>, PreviewImage == Never, PreviewIcon == Never {
    public init(item: String, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) { self.init(label: label()) }
}
extension ShareLink where Data == CollectionOfOne<URL>, PreviewImage == Never, PreviewIcon == Never {
    public init(item: URL, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) { self.init(label: label()) }
}
extension ShareLink {
    public init<I: Transferable>(item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview<PreviewImage, PreviewIcon>,
                                 @ViewBuilder label: () -> Label) where Data == CollectionOfOne<I> {
        self.init(label: label())
    }
    public init(items: Data, subject: Text? = nil, message: Text? = nil, preview: @escaping (Data.Element) -> SharePreview<PreviewImage, PreviewIcon>,
                @ViewBuilder label: () -> Label) {
        self.init(label: label())
    }
}
extension ShareLink where Data == CollectionOfOne<String>, PreviewImage == Never, PreviewIcon == Never, Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, item: String, subject: Text? = nil, message: Text? = nil) {
        self.init(label: SwiftUI.Label(titleKey, systemImage: "square.and.arrow.up"))
    }
}
extension ShareLink where Data == CollectionOfOne<URL>, PreviewImage == Never, PreviewIcon == Never, Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(label: SwiftUI.Label(titleKey, systemImage: "square.and.arrow.up"))
    }
}
