// TabView: the iOS tab bar (and the page style). Only the selected tab's content is drawn;
// the other tabs are resolved only to read their tab items.
//
// Tab bar background (iOS 15+ scroll-edge behaviour): the bar is transparent unless content is
// drawn under it. Heuristic (`contentExtendsBelow`): after layout, any visible leaf node of the
// selected tab whose absolute frame reaches below the bar's top edge counts as content under
// the bar, except leaves that look like full-bleed backgrounds (as wide as the screen and at
// least half its height, e.g. `Color.x.ignoresSafeArea()`). Backgrounds that only bleed while
// drawing (`.background(Color)`) never count because their frames stop at the safe area.

enum TabBarMetrics {
    static let height = ChromeMetrics.tabBarHeight                      // 49 (+ bottom safe area)
    /// Centre of the icon, from the bar's top edge.
    static let iconCenterY: CGFloat = 17.5
    /// Baseline of the title, from the bar's top edge.
    static let titleBaseline: CGFloat = 43
    static let iconFont = Font.system(size: 20, weight: .medium)
    static let titleFont = Font.system(size: 10, weight: .medium)
    static let unselectedColor = SystemColor.gray
    // Badge.
    static let badgeHeight: CGFloat = 18
    static let badgeHorizontalPadding: CGFloat = 5
    static let badgeFont = Font.system(size: 13)
    /// Badge leading edge relative to the icon's centre, and top edge relative to the bar's top.
    static let badgeLeadingFromIconCenter: CGFloat = 4
    static let badgeTop: CGFloat = 2
    // Page style.
    static let pageDotDiameter: CGFloat = 7
    static let pageDotPitch: CGFloat = 16
    static let pageDotsCenterFromBottom: CGFloat = 12
    static let pageDotsBackgroundHeight: CGFloat = 26
    static let pageDotInactiveOpacity: Double = 0.3
}

// MARK: - Tab items and badges on views

typealias TabLabelResolver = @MainActor (_ adjust: (inout EnvironmentValues) -> Void) -> [Node]

enum TabItemTraitKey: TraitKey { typealias Value = TabLabelResolver }

/// `.badge(...)`: read by a TabView (tab item badge) or a List (row badge).
enum BadgeTraitKey: TraitKey { typealias Value = Text }

struct TabItemModifier<Label: View>: ViewModifier, PrimitiveModifier {
    let label: Label
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let label = self.label
        let labelCtx = ctx.child("tabItem")
        let resolver: TabLabelResolver = { adjust in resolveNodes(label, labelCtx.with(adjust)) }
        for node in content.nodes(ctx) {
            node.traits[TabItemTraitKey.self] = resolver
            out.append(node)
        }
    }
}

extension View {
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View { modifier(TabItemModifier(label: label())) }

    public func badge(_ count: Int) -> some View { modifier(BadgeModifier(badge: count == 0 ? nil : Text(verbatim: "\(count)"))) }
    public func badge(_ label: Text?) -> some View { modifier(BadgeModifier(badge: label)) }
    public func badge(_ key: LocalizedStringKey?) -> some View { modifier(BadgeModifier(badge: key.map { Text($0) })) }
    @_disfavoredOverload
    public func badge<S: StringProtocol>(_ label: S?) -> some View { modifier(BadgeModifier(badge: label.map { Text($0) })) }
}

struct BadgeModifier: ViewModifier, PrimitiveModifier {
    let badge: Text?
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) {
            node.traits[BadgeTraitKey.self] = badge
            out.append(node)
        }
    }
}

// MARK: - Styles

public protocol TabViewStyle {}
public struct DefaultTabViewStyle: TabViewStyle { public init() {} }
public struct TabBarOnlyTabViewStyle: TabViewStyle { public init() {} }
public struct SidebarAdaptableTabViewStyle: TabViewStyle { public init() {} }
public struct PageTabViewStyle: TabViewStyle {
    public struct IndexDisplayMode: Hashable, Sendable {
        let raw: Int
        public static let automatic = IndexDisplayMode(raw: 0)
        public static let always = IndexDisplayMode(raw: 1)
        public static let never = IndexDisplayMode(raw: 2)
    }
    let indexDisplayMode: IndexDisplayMode
    public init(indexDisplayMode: IndexDisplayMode = .automatic) { self.indexDisplayMode = indexDisplayMode }
}
extension TabViewStyle where Self == DefaultTabViewStyle { public static var automatic: Self { .init() } }
extension TabViewStyle where Self == TabBarOnlyTabViewStyle { public static var tabBarOnly: Self { .init() } }
extension TabViewStyle where Self == SidebarAdaptableTabViewStyle { public static var sidebarAdaptable: Self { .init() } }
extension TabViewStyle where Self == PageTabViewStyle {
    public static var page: Self { .init() }
    public static func page(indexDisplayMode: PageTabViewStyle.IndexDisplayMode) -> Self { .init(indexDisplayMode: indexDisplayMode) }
}

public protocol IndexViewStyle {}
public struct PageIndexViewStyle: IndexViewStyle {
    public struct BackgroundDisplayMode: Hashable, Sendable {
        let raw: Int
        public static let automatic = BackgroundDisplayMode(raw: 0)
        public static let always = BackgroundDisplayMode(raw: 1)
        public static let interactive = BackgroundDisplayMode(raw: 2)
        public static let never = BackgroundDisplayMode(raw: 3)
    }
    let backgroundDisplayMode: BackgroundDisplayMode
    public init(backgroundDisplayMode: BackgroundDisplayMode = .automatic) { self.backgroundDisplayMode = backgroundDisplayMode }
}
extension IndexViewStyle where Self == PageIndexViewStyle {
    public static var page: Self { .init() }
    public static func page(backgroundDisplayMode: PageIndexViewStyle.BackgroundDisplayMode) -> Self { .init(backgroundDisplayMode: backgroundDisplayMode) }
}

enum TabViewPageModeKey: EnvironmentKey { static let defaultValue: PageTabViewStyle.IndexDisplayMode? = nil }
enum PageIndexBackgroundKey: EnvironmentKey { static let defaultValue = PageIndexViewStyle.BackgroundDisplayMode.automatic }
extension EnvironmentValues {
    /// Non-nil when `.tabViewStyle(.page)` is in effect.
    var tabViewPageMode: PageTabViewStyle.IndexDisplayMode? {
        get { self[TabViewPageModeKey.self] }
        set { self[TabViewPageModeKey.self] = newValue }
    }
    var pageIndexBackground: PageIndexViewStyle.BackgroundDisplayMode {
        get { self[PageIndexBackgroundKey.self] }
        set { self[PageIndexBackgroundKey.self] = newValue }
    }
}

public enum TabBarMinimizeBehavior: Hashable, Sendable { case automatic, onScrollDown, onScrollUp, never }
public struct TabViewCustomization: Codable, Hashable, Sendable {
    public init() {}
    public mutating func resetVisibility() {}
    public mutating func resetSectionOrder() {}
}
public struct AdaptableTabBarPlacement: Hashable, Sendable {
    public static let automatic = AdaptableTabBarPlacement()
    public static let tabBar = AdaptableTabBarPlacement()
    public static let sidebar = AdaptableTabBarPlacement()
}
public struct TabPlacement: Hashable, Sendable {
    public static let automatic = TabPlacement()
    public static let pinned = TabPlacement()
    public static let sidebarOnly = TabPlacement()
}

extension View {
    public func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        let mode = (style as? PageTabViewStyle)?.indexDisplayMode
        return env { $0.tabViewPageMode = mode }
    }
    public func indexViewStyle<S: IndexViewStyle>(_ style: S) -> some View {
        let mode = (style as? PageIndexViewStyle)?.backgroundDisplayMode ?? .automatic
        return env { $0.pageIndexBackground = mode }
    }
    public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View { self }
    public func tabViewCustomization(_ customization: Binding<TabViewCustomization>?) -> some View { self }
    public func tabViewSidebarHeader<C: View>(@ViewBuilder content: () -> C) -> some View { self }
    public func tabViewSidebarFooter<C: View>(@ViewBuilder content: () -> C) -> some View { self }
    public func tabViewSidebarBottomBar<C: View>(@ViewBuilder content: () -> C) -> some View { self }
    public func tabViewSidebarHeader<C: View>(@ViewBuilder _ content: () -> C) -> some View { self }
}

// MARK: - iOS 18 Tab API

public enum TabRole: Hashable, Sendable { case search }

/// A collected tab: its tag, how to build its label and content, and its badge.
struct TabEntry {
    var tag: AnyHashable?
    var label: TabLabelResolver?
    var badge: Text?
    var content: @MainActor () -> Node
}

@MainActor @preconcurrency
public protocol TabContent<TabValue> {
    associatedtype TabValue: Hashable
    associatedtype Body: TabContent
    @TabContentBuilder<TabValue> @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: TabContent { public typealias TabValue = Never }

protocol PrimitiveTabContent {
    @MainActor func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry])
}

extension TabContent where Body == Never {
    public var body: Never { fatalError("\(Self.self) is primitive tab content") }
}

@MainActor
func collectTabContent<T: TabContent>(_ content: T, _ ctx: ResolveContext, into out: inout [TabEntry]) {
    if let primitive = content as? PrimitiveTabContent {
        primitive.collectTabs(ctx, into: &out)
        return
    }
    let ctx = ctx.child(ObjectIdentifier(T.self))
    installDynamicProperties(of: content, ctx)
    collectTabContent(content.body, ctx, into: &out)
}

/// The label a `Tab("Title", systemImage:)` shows: an icon and a title.
public struct DefaultTabLabel: View, PrimitiveView {
    public typealias Body = Never
    let title: Text
    let image: Image?
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        if let image { resolveView(image, ctx.child(0), into: &out) }
        resolveView(title, ctx.child(1), into: &out)
    }
}

public struct Tab<Value: Hashable, Content: View, Label: View>: TabContent, PrimitiveTabContent {
    public typealias TabValue = Value
    public typealias Body = Never
    let tag: AnyHashable?
    let content: Content
    let label: Label

    init(tag: AnyHashable?, content: Content, label: Label) {
        self.tag = tag
        self.content = content
        self.label = label
    }

    public init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: AnyHashable(value), content: content(), label: label())
    }
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: AnyHashable(value), content: content(), label: label())
    }

    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        let (content, label) = (self.content, self.label)
        let index = out.count
        let tabCtx = ctx.child("tab\(index)")
        out.append(TabEntry(tag: tag, label: { adjust in resolveNodes(label, tabCtx.child("label").with(adjust)) }, badge: nil,
                            content: { resolveSingle(content, tabCtx.child("content")) }))
    }
}

extension Tab where Label == DefaultTabLabel {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(systemName: systemImage)))
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(title), image: Image(systemName: systemImage)))
    }
    public init(_ titleKey: LocalizedStringKey, image: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(image)))
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(title), image: Image(image)))
    }
    /// `Tab(value:role: .search) { ... }`: the system search tab.
    public init(value: Value, role: TabRole, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(verbatim: "Search"), image: Image(systemName: "magnifyingglass")))
    }
}

extension Tab where Value == Never, Label == DefaultTabLabel {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(systemName: systemImage)))
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(title), image: Image(systemName: systemImage)))
    }
    public init(_ titleKey: LocalizedStringKey, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(image)))
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(title), image: Image(image)))
    }
    public init(role: TabRole, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(verbatim: "Search"), image: Image(systemName: "magnifyingglass")))
    }
}

extension Tab where Value == Never {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: nil, content: content(), label: label())
    }
}

/// On an iPhone tab bar, sections are flattened into their tabs.
public struct TabSection<Header: View, Content: TabContent, Footer: View>: TabContent, PrimitiveTabContent {
    public typealias TabValue = Content.TabValue
    public typealias Body = Never
    let content: Content
    public init(@TabContentBuilder<Content.TabValue> content: () -> Content, @ViewBuilder header: () -> Header,
                @ViewBuilder footer: () -> Footer) {
        self.content = content()
    }
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) { collectTabContent(content, ctx, into: &out) }
}
extension TabSection where Footer == EmptyView {
    public init(@TabContentBuilder<Content.TabValue> content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
    }
}
extension TabSection where Header == Text, Footer == EmptyView {
    public init(_ titleKey: LocalizedStringKey, @TabContentBuilder<Content.TabValue> content: () -> Content) {
        self.content = content()
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @TabContentBuilder<Content.TabValue> content: () -> Content) {
        self.content = content()
    }
}
extension TabSection where Header == EmptyView, Footer == EmptyView {
    public init(@TabContentBuilder<Content.TabValue> content: () -> Content) {
        self.content = content()
    }
}

public struct TupleTabContent<TabValue: Hashable, T>: TabContent, PrimitiveTabContent {
    public typealias Body = Never
    let collector: @MainActor (ResolveContext, inout [TabEntry]) -> Void
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) { collector(ctx, &out) }
}

public struct _OptionalTabContent<Wrapped: TabContent>: TabContent, PrimitiveTabContent {
    public typealias TabValue = Wrapped.TabValue
    public typealias Body = Never
    let wrapped: Wrapped?
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        if let wrapped { collectTabContent(wrapped, ctx.child("some"), into: &out) }
    }
}

public struct _ConditionalTabContent<TrueContent: TabContent, FalseContent: TabContent>: TabContent, PrimitiveTabContent
where TrueContent.TabValue == FalseContent.TabValue {
    public typealias TabValue = TrueContent.TabValue
    public typealias Body = Never
    enum Storage { case trueContent(TrueContent), falseContent(FalseContent) }
    let storage: Storage
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        switch storage {
        case .trueContent(let c): collectTabContent(c, ctx.child("true"), into: &out)
        case .falseContent(let c): collectTabContent(c, ctx.child("false"), into: &out)
        }
    }
}

extension ForEach: TabContent, PrimitiveTabContent where Content: TabContent {
    public typealias TabValue = Content.TabValue
    public typealias Body = Never
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @TabContentBuilder<Content.TabValue> content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        for element in data { collectTabContent(content(element), ctx.child(idGetter(element)), into: &out) }
    }
}

@resultBuilder
public struct TabContentBuilder<TabValue: Hashable> {
    public static func buildExpression<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue { content }
    public static func buildBlock<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue { content }
    public static func buildBlock<each C: TabContent>(_ content: repeat each C) -> TupleTabContent<TabValue, (repeat each C)>
    {
        TupleTabContent { ctx, out in
            var index = 0
            for child in repeat each content {
                collectTabContent(child, ctx.child(index), into: &out)
                index += 1
            }
        }
    }
    public static func buildIf<C: TabContent>(_ content: C?) -> _OptionalTabContent<C> where C.TabValue == TabValue { .init(wrapped: content) }
    public static func buildOptional<C: TabContent>(_ content: C?) -> _OptionalTabContent<C> where C.TabValue == TabValue { .init(wrapped: content) }
    public static func buildEither<T: TabContent, F: TabContent>(first: T) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue {
        .init(storage: .trueContent(first))
    }
    public static func buildEither<T: TabContent, F: TabContent>(second: F) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue {
        .init(storage: .falseContent(second))
    }
    public static func buildLimitedAvailability<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue { content }

    /// The view a TabView's tab content builder produces.
    public struct Content<C: TabContent>: View, PrimitiveView, TabEntriesProvider where C.TabValue == TabValue {
        public typealias Body = Never
        let content: C
        func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
            // Used outside a TabView: show the first tab's content.
            if let first = entries(ctx).first { out.append(first.content()) }
        }
        func entries(_ ctx: ResolveContext) -> [TabEntry] {
            var out: [TabEntry] = []
            collectTabContent(content, ctx, into: &out)
            return out
        }
    }
}

protocol TabEntriesProvider {
    @MainActor func entries(_ ctx: ResolveContext) -> [TabEntry]
}

/// Tab content with a modifier applied (`.badge`, `.hidden`, ...).
public struct _ModifiedTabContent<Base: TabContent>: TabContent, PrimitiveTabContent {
    public typealias TabValue = Base.TabValue
    public typealias Body = Never
    let base: Base
    let transform: (inout TabEntry) -> Bool
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        var entries: [TabEntry] = []
        collectTabContent(base, ctx, into: &entries)
        for var entry in entries where transform(&entry) { out.append(entry) }
    }
}

extension TabContent {
    func modifyingTab(_ transform: @escaping (inout TabEntry) -> Bool) -> _ModifiedTabContent<Self> {
        _ModifiedTabContent(base: self, transform: transform)
    }
    public func badge(_ count: Int) -> _ModifiedTabContent<Self> {
        modifyingTab { $0.badge = count == 0 ? nil : Text(verbatim: "\(count)"); return true }
    }
    public func badge(_ label: Text?) -> _ModifiedTabContent<Self> { modifyingTab { $0.badge = label; return true } }
    public func badge(_ key: LocalizedStringKey?) -> _ModifiedTabContent<Self> { modifyingTab { $0.badge = key.map { Text($0) }; return true } }
    @_disfavoredOverload
    public func badge<S: StringProtocol>(_ label: S?) -> _ModifiedTabContent<Self> { modifyingTab { $0.badge = label.map { Text($0) }; return true } }
    public func hidden(_ hidden: Bool = true) -> _ModifiedTabContent<Self> { modifyingTab { _ in !hidden } }
    public func customizationID(_ id: String) -> Self { self }
    public func customizationBehavior(_ behavior: TabCustomizationBehavior, for placements: AdaptableTabBarPlacement...) -> Self { self }
    public func defaultVisibility(_ visibility: Visibility, for placements: AdaptableTabBarPlacement...) -> Self { self }
    public func tabPlacement(_ placement: TabPlacement) -> Self { self }
    public func sectionActions<C: View>(@ViewBuilder content: () -> C) -> Self { self }
    public func disabled(_ disabled: Bool) -> Self { self }
    public func accessibilityIdentifier(_ identifier: String) -> Self { self }
}

public struct TabCustomizationBehavior: Sendable {
    public static let automatic = TabCustomizationBehavior()
    public static let reorderable = TabCustomizationBehavior()
    public static let disabled = TabCustomizationBehavior()
}

// MARK: - TabView

public struct TabView<SelectionValue: Hashable, Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let selection: AnyHashable?
    let content: Content

    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection.map { AnyHashable($0.wrappedValue) }
        self.content = content()
    }
    public init<C: TabContent>(selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C)
    where Content == TabContentBuilder<SelectionValue>.Content<C>, C.TabValue == SelectionValue {
        self.selection = AnyHashable(selection.wrappedValue)
        self.content = TabContentBuilder<SelectionValue>.Content(content: content())
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        var entries: [TabEntry]
        if let provider = content as? TabEntriesProvider {
            entries = provider.entries(ctx)
        } else {
            entries = resolveNodes(content, ctx.with { $0.stackAxis = nil }).map { node in
                TabEntry(tag: node.traits[TagTraitKey.self], label: node.traits[TabItemTraitKey.self],
                         badge: node.traits[BadgeTraitKey.self], content: { node })
            }
        }
        guard !entries.isEmpty else { return }
        let target = selection.map(unwrapOptional)
        let selected = target.flatMap { t in entries.firstIndex { $0.tag.map(unwrapOptional) == t } } ?? 0
        if let mode = ctx.env.tabViewPageMode {
            out.append(PageTabViewNode(content: entries[selected].content(), count: entries.count, selected: selected,
                                       mode: mode, background: ctx.env.pageIndexBackground))
        } else {
            out.append(TabViewNode(entries: entries, selected: selected, ctx: ctx))
        }
    }
}

extension TabView where SelectionValue == Int {
    public init(@ViewBuilder content: () -> Content) {
        selection = nil
        self.content = content()
    }
}

extension TabView where SelectionValue == Never {
    public init<C: TabContent>(@TabContentBuilder<Never> content: () -> C) where Content == TabContentBuilder<Never>.Content<C>, C.TabValue == Never {
        selection = nil
        self.content = TabContentBuilder<Never>.Content(content: content())
    }
}

/// `Optional(x)` and `x` select the same tab.
func unwrapOptional(_ value: AnyHashable) -> AnyHashable {
    let mirror = Mirror(reflecting: value.base)
    if mirror.displayStyle == .optional, let child = mirror.children.first, let inner = child.value as? AnyHashable {
        return unwrapOptional(inner)
    }
    return value
}

// MARK: - Bar nodes

final class TabBadgeNode: Node {
    let fill: _Paint
    var label: Node { children[0] }
    init(label: Node, fill: _Paint) {
        self.fill = fill
        super.init(children: [label])
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let m = TabBarMetrics.self
        let s = label.sizeThatFits(.unspecified)
        return CGSize(width: max(m.badgeHeight, s.width + m.badgeHorizontalPadding * 2), height: m.badgeHeight)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let s = label.sizeThatFits(.unspecified)
        label.place(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2), size: s, ctx)
    }
    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        p.fill(Path(roundedRect: bounds, cornerRadius: bounds.height / 2, style: .circular), with: fill, in: bounds)
        drawChildren(p)
    }
}

final class TabViewNode: Node {
    struct Item { var icon: Node?; var title: Node?; var badge: Node? }
    let content: Node
    let items: [Item]
    let barVisible: Bool
    let backgroundVisibility: Visibility
    let background: _Paint
    let hairline: _Paint
    /// The index of the selected tab (accessibility).
    let selectedIndex: Int

    private(set) var barTop: CGFloat = 0
    private var barBottom: CGFloat = 0
    private var showsBackground = false

    init(entries: [TabEntry], selected: Int, ctx: ResolveContext) {
        selectedIndex = selected
        let env = ctx.env
        let content = entries[selected].content()
        self.content = content
        var chrome = content.preferences[NavigationChromeKey.self]
        let settings = chrome.bars[.tabBar] ?? .init()
        chrome.bars[.tabBar] = nil
        barVisible = settings.visibility != .hidden
        let scheme = (settings.colorScheme ?? nil) ?? env.colorScheme
        var barEnv = env
        barEnv.colorScheme = scheme
        backgroundVisibility = settings.backgroundVisibility ?? .automatic
        background = settings.backgroundStyle?._paint(in: barEnv) ?? Material.bar._paint(in: barEnv)
        hairline = .color(SystemColor.separator.resolve(scheme))

        let accent = Color.accentColor.rgba(in: barEnv)
        let gray = TabBarMetrics.unselectedColor.resolve(scheme)
        var items: [Item] = []
        if barVisible {
            for (i, entry) in entries.enumerated() {
                let color = AnyShapeStyle(_FixedPaintStyle(.color(i == selected ? accent : gray)))
                func adjust(_ font: Font) -> (inout EnvironmentValues) -> Void {
                    { e in
                        e.colorScheme = scheme
                        e.font = font
                        e.fontWeight = nil
                        e.imageScale = .medium
                        e.symbolVariants = .fill
                        e.foregroundStyle = color
                        e.foregroundStyleLevels = nil
                        e.lineLimit = 1
                        e.stackAxis = nil
                    }
                }
                var item = Item()
                if let label = entry.label {
                    item.icon = label(adjust(TabBarMetrics.iconFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first
                    item.title = label(adjust(TabBarMetrics.titleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
                }
                if let badge = entry.badge {
                    var badgeEnv = barEnv
                    badgeEnv.font = TabBarMetrics.badgeFont
                    badgeEnv.foregroundStyle = AnyShapeStyle(Color.white)
                    badgeEnv.lineLimit = 1
                    item.badge = TabBadgeNode(label: badge.makeNode(badgeEnv), fill: .color(SystemColor.red.resolve(scheme)))
                }
                items.append(item)
            }
        }
        self.items = items
        super.init(children: [content] + items.flatMap { [$0.icon, $0.title, $0.badge].compactMap { $0 } })
        traits = content.traits
        preferences = content.preferences
        preferences.set(NavigationChromeKey.self, chrome)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let m = TabBarMetrics.self
        let safeTop = max(0, ctx.safeRect.minY - ctx.origin.y)
        let safeBottom = min(size.height, ctx.safeRect.maxY - ctx.origin.y)
        barTop = barVisible ? safeBottom - m.height : safeBottom
        barBottom = max(size.height, ctx.container.maxY - ctx.origin.y)

        let area = CGRect(x: 0, y: safeTop, width: size.width, height: max(0, barTop - safeTop))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + area.minY, width: ctx.safeRect.width, height: area.height)
        let c = content.sizeThatFits(ProposedViewSize(area.size))
        content.place(at: CGPoint(x: area.midX - c.width / 2, y: area.midY - c.height / 2), size: c, inner)
        guard barVisible, !items.isEmpty else { return }

        let itemWidth = size.width / CGFloat(items.count)
        for (i, item) in items.enumerated() {
            let cx = itemWidth * (CGFloat(i) + 0.5)
            var iconMidX = cx
            if let icon = item.icon {
                let s = icon.sizeThatFits(.unspecified)
                icon.place(at: CGPoint(x: cx - s.width / 2, y: barTop + m.iconCenterY - s.height / 2), size: s, ctx)
                iconMidX = cx
            }
            if let title = item.title {
                var s = title.sizeThatFits(ProposedViewSize(width: itemWidth - 4, height: nil))
                s.width = min(s.width, itemWidth - 4)
                let baseline = title.explicitAlignment(VerticalAlignment.firstTextBaseline.key, size: s) ?? s.height
                title.place(at: CGPoint(x: cx - s.width / 2, y: barTop + m.titleBaseline - baseline), size: s, ctx)
            }
            if let badge = item.badge {
                let s = badge.sizeThatFits(.unspecified)
                badge.place(at: CGPoint(x: iconMidX + m.badgeLeadingFromIconCenter, y: barTop + m.badgeTop), size: s, ctx)
            }
        }
        switch backgroundVisibility {
        case .visible: showsBackground = true
        case .hidden: showsBackground = false
        case .automatic: showsBackground = contentExtendsBelow(content, y: ctx.origin.y + barTop, container: ctx.container)
        }
    }

    override func drawContent(_ p: Painter) {
        content.draw(p)
        guard barVisible else { return }
        if showsBackground {
            let rect = CGRect(x: 0, y: barTop, width: frame.width, height: barBottom - barTop)
            p.fill(Path(rect), with: background, in: rect)
            let line = CGRect(x: 0, y: barTop - ChromeMetrics.hairline, width: frame.width, height: ChromeMetrics.hairline)
            p.fill(Path(line), with: hairline, in: line)
        }
        for child in children.dropFirst() { child.draw(p) }
    }
}

final class PageTabViewNode: Node {
    let count: Int
    let selected: Int
    let showsDots: Bool
    let showsBackground: Bool
    var content: Node { children[0] }
    private var dotsCenterY: CGFloat = 0

    init(content: Node, count: Int, selected: Int, mode: PageTabViewStyle.IndexDisplayMode,
         background: PageIndexViewStyle.BackgroundDisplayMode) {
        self.count = count
        self.selected = selected
        showsDots = mode == .always || (mode == .automatic && count > 1)
        showsBackground = background == .always
        super.init(children: [content])
        traits = content.traits
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = content.sizeThatFits(ProposedViewSize(size))
        content.place(at: CGPoint(x: (size.width - c.width) / 2, y: (size.height - c.height) / 2), size: c, ctx)
        let bottom = min(size.height, ctx.safeRect.maxY - ctx.origin.y)
        dotsCenterY = bottom - TabBarMetrics.pageDotsCenterFromBottom
    }

    override func drawContent(_ p: Painter) {
        drawChildren(p)
        guard showsDots, count > 0 else { return }
        let m = TabBarMetrics.self
        let total = CGFloat(count - 1) * m.pageDotPitch
        let startX = frame.width / 2 - total / 2
        if showsBackground {
            let bg = CGRect(x: startX - m.pageDotPitch, y: dotsCenterY - m.pageDotsBackgroundHeight / 2,
                            width: total + m.pageDotPitch * 2, height: m.pageDotsBackgroundHeight)
            p.fill(Path(roundedRect: bg, cornerRadius: bg.height / 2, style: .circular), with: .color(RGBA(0, 0, 0, 0.25)), in: bg)
        }
        for i in 0..<count {
            let x = startX + CGFloat(i) * m.pageDotPitch
            let r = CGRect(x: x - m.pageDotDiameter / 2, y: dotsCenterY - m.pageDotDiameter / 2, width: m.pageDotDiameter, height: m.pageDotDiameter)
            let alpha = i == selected ? 1 : m.pageDotInactiveOpacity
            p.fill(Path(ellipseIn: r), with: .color(RGBA(1, 1, 1, alpha)), in: r)
        }
    }
}

// MARK: - Scroll-edge heuristic

/// Whether any visible content (not a full-bleed background) is laid out below absolute `y`.
@MainActor
func contentExtendsBelow(_ root: Node, y: CGFloat, container: CGRect) -> Bool {
    func visit(_ node: Node) -> Bool {
        if node.children.isEmpty {
            if node is SpacerNode || node is EmptyNode { return false }
            let r = CGRect(origin: node.absoluteOrigin, size: node.frame.size)
            guard r.width > 0.5, r.height > 0.5, r.maxY > y + 0.5, r.minY < container.maxY else { return false }
            if r.width >= container.width - 1 && r.height >= container.height * 0.5 { return false }
            return true
        }
        return node.children.contains(where: visit)
    }
    return visit(root)
}
