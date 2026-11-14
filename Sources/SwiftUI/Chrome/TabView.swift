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
    // iPad (regular width): the tab bar is a floating capsule of text tabs at the top. The sizes are estimates.
    static let topBarBand: CGFloat = 50          // room reserved below the status bar
    static let topBarGap: CGFloat = 6            // status bar to capsule
    static let topBarHeight: CGFloat = 42
    static let topBarInset: CGFloat = 4          // capsule edge to selection pill
    static let topItemPadding: CGFloat = 16
    static let topItemGap: CGFloat = 2
    static let topTitleFont = Font.system(size: 15, weight: .medium)
    // Compact height (landscape iPhone): 32pt bar, icon and title side by side.
    static let compactHeight: CGFloat = 32
    static let compactIconTitleGap: CGFloat = 5
    static var isCompactHeight: Bool {
        let device = _currentConfiguration().device
        return device.idiom == .phone && device.orientation.isLandscape
    }

    /// Liquid Glass tab bar (iOS 26+). Values marked (est.) are estimates kept here for calibration.
    struct Glass {
        /// Floating capsule: height, inset from the screen's sides, and its bottom edge above the screen's bottom.
        var height: CGFloat = 62                    // measured: iOS 27.0 simulator (769...831pt)
        var sideInset: CGFloat = 21                 // measured: iOS 27.0 simulator
        var bottomInset: CGFloat = 21               // phones with a home indicator; measured: iOS 27.0 simulator
        var bottomInsetWithoutHomeIndicator: CGFloat = 8   // (est.) iPhone SE
        /// Selection pill: inset from the capsule's edges.
        var pillInset: CGFloat = 4                  // (est.)
        var pillLight: RGBA
        var pillDark: RGBA
        /// Item frames (the selection pill): at least `minItemWidth`, or the title plus `itemTitlePadding`.
        /// Neighbouring frames overlap by up to `itemOverlapPerTab` times the number of tabs: frames that
        /// fit even without overlap make a narrower, centred capsule; otherwise they fill the capsule,
        /// overlapping more (up to that limit) and then shrinking.
        /// measured: iOS 27.0 simulator (2 tabs: 94pt frames, 8pt overlap, 188pt capsule; 4 tabs: 95.8pt,
        /// 13.3pt; 5 tabs: 84.6pt, 20pt; "Listen Now" 96.2pt among 81.7pt frames).
        var minItemWidth: CGFloat = 94
        var itemTitlePadding: CGFloat = 44          // (est.) from one long title
        var itemOverlapPerTab: CGFloat = 4
        /// Icon centre and title baseline from the capsule's top edge.
        var iconCenterY: CGFloat = 24               // measured: iOS 27.0 simulator
        var titleBaseline: CGFloat = 48.67          // measured: iOS 27.0 simulator
        var iconFont = Font.system(size: 23, weight: .medium)    // measured: iOS 27.0 simulator (house 27 x 24pt)
        var titleFont = Font.system(size: 10, weight: .medium)
        /// Badge top edge from the capsule's top edge.
        var badgeTop: CGFloat = 6                   // measured: iOS 27.0 simulator
        var badgeLeadingFromIconCenter: CGFloat = 7 // measured: iOS 27.0 simulator ("3" and "New" badges)
        /// A search / prominent tab: a separate circle this far from the main capsule.
        var separateGap: CGFloat = 12               // (est.)
        /// `tabViewBottomAccessory`: capsule height and gap above the bar.
        var accessoryHeight: CGFloat = 48           // (est.)
        var accessoryGap: CGFloat = 8               // measured: iOS 27.0 simulator (713...761pt over a bar at 769pt)
        /// The accessory's content spans the capsule. measured: iOS 27.0 simulator (content 21...371.7pt)
        var accessoryPadding: CGFloat = 0
        /// Compact height (landscape iPhone): a shorter capsule sized to its items, centred.
        var compactHeight: CGFloat = 48             // (est.)
        var compactItemPadding: CGFloat = 16        // (est.)
        var compactIconTitleGap: CGFloat = 6        // (est.)
        var compactAccessoryMinWidth: CGFloat = 360 // (est.)
        /// iPad top bar.
        var topBarHeight: CGFloat = 44              // (est.)

        /// iOS 26 draws the pill as a small raised glass platter (lighter than the bar, with a soft shadow);
        /// iOS 27 as a flat, darker fill.
        var pillIsRaised = false

        func pill(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? pillDark : pillLight }

        /// Draws the selection pill.
        @MainActor func drawPill(_ rect: CGRect, scheme: ColorScheme, design: DesignLanguage, in p: Painter) {
            guard rect.width > 0 else { return }
            if pillIsRaised {
                var a = GlassAppearance.system(.regular, scheme: scheme, design: design)
                a.tint = pill(scheme)
                a.lensStrength = 4
                a.shadow = (RGBA(0, 0, 0, scheme == .dark ? 0.3 : 0.12), 6, 1)
                p.fillGlass(.roundedRect(rect, radius: rect.height / 2), appearance: a)
            } else {
                p.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .circular), with: .color(pill(scheme)), in: rect)
            }
        }
    }

    static func forDesign(_ design: DesignLanguage) -> Glass {
        switch design {
        case .liquidGlass27:
            // iOS 27: the selection pill is darker than the bar.
            // measured: iOS 27.0 simulator (pill 235 on a 249 bar in light, 10 on 32 in dark)
            return Glass(pillLight: RGBA(0, 0, 0, 0.056), pillDark: RGBA(0, 0, 0, 0.69))
        default:
            // iOS 26: a flat fill, darker than the bar in light mode and lighter in dark mode.
            // measured: iOS 26.5 simulator (pill 235 on a 253 bar in light, 53 on 19 in dark)
            return Glass(pillLight: RGBA(0, 0, 0, 0.07), pillDark: RGBA(1, 1, 1, 0.14))
        }
    }
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

enum TabViewSidebarAdaptableKey: EnvironmentKey { static let defaultValue = false }
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
public struct AdaptableTabBarPlacement: Hashable, Sendable {
    let raw: Int
    public static let automatic = AdaptableTabBarPlacement(raw: 0)
    public static let tabBar = AdaptableTabBarPlacement(raw: 1)
    public static let sidebar = AdaptableTabBarPlacement(raw: 2)
}
public struct TabPlacement: Hashable, Sendable {
    let raw: Int
    public static let automatic = TabPlacement(raw: 0)
    public static let pinned = TabPlacement(raw: 1)
    public static let sidebarOnly = TabPlacement(raw: 2)
}

extension View {
    public func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        let mode = (style as? PageTabViewStyle)?.indexDisplayMode
        let sidebar = style is SidebarAdaptableTabViewStyle
        return env { $0.tabViewPageMode = mode; $0[TabViewSidebarAdaptableKey.self] = sidebar }
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
    @_disfavoredOverload
    public func tabViewSidebarHeader<C: View>(@ViewBuilder _ content: () -> C) -> some View { self }
}

// MARK: - iOS 18 Tab API

public enum TabRole: Hashable, Sendable {
    case search
    /// iOS 27: a tab drawn apart from the others at the trailing end of the tab bar.
    case prominent
}

/// A collected tab: its tag, how to build its label and content, and its badge.
struct TabEntry {
    var tag: AnyHashable?
    var label: TabLabelResolver?
    var badge: Text?
    var content: @MainActor () -> Node
    var role: TabRole? = nil
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
    let role: TabRole?

    init(tag: AnyHashable?, content: Content, label: Label, role: TabRole? = nil) {
        self.tag = tag
        self.content = content
        self.label = label
        self.role = role
    }

    public init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: AnyHashable(value), content: content(), label: label())
    }
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: AnyHashable(value), content: content(), label: label(), role: role)
    }

    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) {
        let (content, label) = (self.content, self.label)
        let index = out.count
        let tabCtx = ctx.child("tab\(index)")
        out.append(TabEntry(tag: tag, label: { adjust in resolveNodes(label, tabCtx.child("label").with(adjust)) }, badge: nil,
                            content: { resolveSingle(content, tabCtx.child("content")) }, role: role))
    }
}

extension Tab where Label == DefaultTabLabel {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(systemName: systemImage)), role: role)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(title), image: Image(systemName: systemImage)), role: role)
    }
    public init(_ titleKey: LocalizedStringKey, image: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(image)), role: role)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(title), image: Image(image)), role: role)
    }
    /// `Tab(value:role: .search) { ... }`: the system search tab.
    public init(value: Value, role: TabRole, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: DefaultTabLabel(title: Text(verbatim: "Search"), image: Image(systemName: "magnifyingglass")), role: role)
    }
}

extension Tab where Value == Never, Label == DefaultTabLabel {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(systemName: systemImage)), role: role)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(title), image: Image(systemName: systemImage)), role: role)
    }
    public init(_ titleKey: LocalizedStringKey, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(titleKey), image: Image(image)), role: role)
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(title), image: Image(image)), role: role)
    }
    public init(role: TabRole, @ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: DefaultTabLabel(title: Text(verbatim: "Search"), image: Image(systemName: "magnifyingglass")), role: role)
    }
}

extension Tab where Value == Never {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: nil, content: content(), label: label())
    }
}

/// On an iPhone tab bar, sections are flattened into their tabs.
public struct TabSection<Header, Content: TabContent, Footer, SelectionValue: Hashable>: TabContent, PrimitiveTabContent
where Content.TabValue == SelectionValue {
    public typealias TabValue = SelectionValue
    public typealias Body = Never
    let content: Content
    public init(@TabContentBuilder<SelectionValue> content: () -> Content, @ViewBuilder header: () -> Header,
                @ViewBuilder footer: () -> Footer) where Header: View, Footer: View {
        self.content = content()
    }
    func collectTabs(_ ctx: ResolveContext, into out: inout [TabEntry]) { collectTabContent(content, ctx, into: &out) }
}
extension TabSection where Footer == EmptyView {
    public init(@TabContentBuilder<SelectionValue> content: () -> Content, @ViewBuilder header: () -> Header) where Header: View {
        self.content = content()
    }
}
extension TabSection where Header == Text, Footer == EmptyView {
    public init(_ titleKey: LocalizedStringKey, @TabContentBuilder<SelectionValue> content: () -> Content) {
        self.content = content()
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @TabContentBuilder<SelectionValue> content: () -> Content) {
        self.content = content()
    }
}
extension TabSection where Header == EmptyView, Footer == EmptyView {
    public init(@TabContentBuilder<SelectionValue> content: () -> Content) {
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
    public init<V>(_ data: Data, id: KeyPath<Data.Element, ID>, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content)
    where V == Content.TabValue {
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
    /// The tab bar is what is drawn (the sidebar is not), so a tab hidden from the tab bar by default is left out.
    public func defaultVisibility(_ visibility: Visibility, for placements: AdaptableTabBarPlacement...) -> _ModifiedTabContent<Self> {
        let hidesFromTabBar = visibility == .hidden && (placements.isEmpty || placements.contains(.tabBar) || placements.contains(.automatic))
        return modifyingTab { _ in !hidesFromTabBar }
    }
    /// A sidebar-only tab is not in the tab bar.
    public func tabPlacement(_ placement: TabPlacement) -> _ModifiedTabContent<Self> { modifyingTab { _ in placement != .sidebarOnly } }
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
    /// Writes the selection binding (remote `select` on a tab item).
    var setSelection: ((AnyHashable) -> Bool)?

    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection.map { AnyHashable($0.wrappedValue) }
        self.content = content()
        self.setSelection = selection.map(Self.setter)
    }
    public init<C: TabContent>(selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C)
    where Content == TabContentBuilder<SelectionValue>.Content<C>, C.TabValue == SelectionValue {
        self.selection = AnyHashable(selection.wrappedValue)
        self.content = TabContentBuilder<SelectionValue>.Content(content: content())
        self.setSelection = Self.setter(selection)
    }

    private static func setter(_ binding: Binding<SelectionValue>) -> (AnyHashable) -> Bool {
        { tag in
            if let value = tag.base as? SelectionValue { binding.wrappedValue = value; return true }
            if let value = unwrapOptional(tag).base as? SelectionValue { binding.wrappedValue = value; return true }
            return false
        }
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let accessory = ctx.env.tabViewBottomAccessory
        let showsBar = ctx.env.tabViewPageMode == nil
        let ctx = ctx.with {
            $0.tabViewBottomAccessory = nil
            if showsBar { $0.hasEnclosingTabBar = true }
        }
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
        let chosen = selection == nil ? ctx.runtime.focus.tabSelections[ctx.path] : nil
        let selected = chosen.flatMap { entries.indices.contains($0) ? $0 : nil }
            ?? target.flatMap { t in entries.firstIndex { $0.tag.map(unwrapOptional) == t } } ?? 0
        if let mode = ctx.env.tabViewPageMode {
            let page = PageTabViewNode(content: entries[selected].content(), count: entries.count, selected: selected,
                                       mode: mode, background: ctx.env.pageIndexBackground)
            if ctx.env.renderPlatform == .tvOS { page.dotScale = TVMetrics.pageDotScale }
            out.append(page)
            // Scripted `swipe` turns the page (Interaction/).
            InteractionRegistry.notePager(out[out.count - 1], count: entries.count, selected: selected) {
                [tags = entries.map(\.tag), path = ctx.path, setSelection = self.setSelection, runtime = ctx.runtime] index in
                if let setSelection { if let tag = tags[index] { _ = setSelection(tag) } } else { runtime.focus.tabSelections[path] = index }
                runtime.needsAnotherPass = true
            }
        } else {
            let accessoryNode: Node? = accessory.flatMap { resolver in
                guard ctx.env.designLanguage.isGlass else { return nil }
                let nodes = resolver(ctx.child("bottomAccessory").with { $0.stackAxis = nil; $0.hasEnclosingTabBar = false })
                if nodes.isEmpty { return nil }
                return nodes.count == 1 ? nodes[0] : StackNode(axis: .horizontal, alignment: .center, spacing: nil, children: nodes)
            }
            let node = TabViewNode(entries: entries, selected: selected, ctx: ctx, accessory: accessoryNode)
            node.focusPath = ctx.path
            let tags = entries.map(\.tag), path = ctx.path, setSelection = self.setSelection, runtime = ctx.runtime
            node.selectTab = { index in
                if let setSelection {
                    guard let tag = tags[index], setSelection(tag) else {
                        runtime.warn("Selecting tab \(index + 1): its tag does not match the TabView's selection type")
                        return
                    }
                } else {
                    runtime.focus.tabSelections[path] = index
                }
                runtime.needsAnotherPass = true
            }
            out.append(node)
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
    /// iPad regular width: text tabs in a capsule at the top instead of a bar at the bottom.
    let topBar: Bool
    /// The index of the selected tab (also read by the accessibility extractor).
    let selectedIndex: Int
    /// iOS 26+: the bar is a floating glass capsule.
    let design: DesignLanguage
    /// `tabViewBottomAccessory` content (glass only).
    let accessory: Node?
    /// The tab drawn as a separate circle at the trailing end (`role: .search`, iOS 27 `.prominent`).
    let separateIndex: Int?
    /// The TabView's identity and how to select a tab (focus engine: tab items and remote `select`).
    var focusPath: IdentityPath?
    var selectTab: (@MainActor (Int) -> Void)?
    let scheme: ColorScheme
    var capsule = CGRect.zero
    var itemRects: [CGRect] = []
    /// tvOS: the top tab bar or the sidebar (Chrome/TV/TVTabBar.swift); nil on other platforms.
    let tv: TVTabLayout?
    /// tvOS: the tab item that has focus, if any.
    let tvFocusedIndex: Int?

    var barTop: CGFloat = 0
    private var barBottom: CGFloat = 0
    private var backgroundX: CGFloat = 0
    private var backgroundWidth: CGFloat = 0
    private var showsBackground = false

    // Glass geometry (local coordinates).
    private var separateRect = CGRect.zero
    private var accessoryRect = CGRect.zero
    private var pillRect = CGRect.zero
    /// Glass only: each tab's frame and the bar's frame, for the accessibility tree. Nil for the flat bar.
    var glassItemFrames: [CGRect]?
    var glassBarFrame: CGRect?

    init(entries: [TabEntry], selected: Int, ctx: ResolveContext, accessory: Node? = nil) {
        selectedIndex = selected
        let env = ctx.env
        let design = env.designLanguage
        self.design = design
        let content = entries[selected].content()
        self.content = content
        var chrome = content.preferences[NavigationChromeKey.self]
        let settings = chrome.bars[.tabBar] ?? .init()
        chrome.bars[.tabBar] = nil
        barVisible = settings.visibility != .hidden
        let scheme = (settings.colorScheme ?? nil) ?? env.colorScheme
        self.scheme = scheme
        let tvFocused = entries.indices.first { ctx.runtime.focus.focusedPath == ctx.path.appending("tab").appending($0) }
        tvFocusedIndex = tvFocused
        let tv: TVTabLayout? = env.renderPlatform == .tvOS
            ? (env[TabViewSidebarAdaptableKey.self] ? .sidebar(expanded: tvFocused != nil) : .topBar) : nil
        self.tv = tv
        let topBar = tv == nil && barVisible && _currentConfiguration().device.idiom == .pad && env.horizontalSizeClass == .regular
        self.topBar = topBar
        var barEnv = env
        barEnv.colorScheme = scheme
        backgroundVisibility = settings.backgroundVisibility ?? .automatic
        background = settings.backgroundStyle?._paint(in: barEnv) ?? Material.bar._paint(in: barEnv)
        hairline = .color(SystemColor.separator.resolve(scheme))
        self.accessory = barVisible && !topBar ? accessory : nil

        var separate: Int? = nil
        if design.isGlass, !topBar, entries.count > 1 {
            // iOS 26 sets the search tab apart (Apple's iOS 26 design); the iOS 27.0 simulator draws it
            // inline with the other tabs (GlassTabsAndSheets "Search tab and accessory").
            separate = entries.firstIndex { ($0.role == .search && design == .liquidGlass26) || ($0.role == .prominent && design == .liquidGlass27) }
        }
        separateIndex = separate

        let glass = TabBarMetrics.forDesign(design)
        let accent = Color.accentColor.rgba(in: barEnv)
        let gray = (design.isGlass ? SystemColor.label : TabBarMetrics.unselectedColor).resolve(scheme)
        let iconFont = design.isGlass ? glass.iconFont : TabBarMetrics.iconFont
        let titleFont = design.isGlass ? glass.titleFont : TabBarMetrics.titleFont
        var items: [Item] = []
        if let tv, barVisible {
            items = TabViewNode.tvItems(entries, selected: selected, focused: tvFocused, layout: tv, env: barEnv)
        } else if barVisible {
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
                    if !topBar { item.icon = label(adjust(iconFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first }
                    item.title = label(adjust(topBar ? TabBarMetrics.topTitleFont : titleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
                }
                if let badge = entry.badge, !topBar {
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
        super.init(children: [content] + items.flatMap { [$0.icon, $0.title, $0.badge].compactMap { $0 } } + [self.accessory].compactMap { $0 })
        traits = content.traits
        preferences = content.preferences
        preferences.set(NavigationChromeKey.self, chrome)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let m = TabBarMetrics.self
        let safeTop = max(0, ctx.safeRect.minY - ctx.origin.y)
        let safeBottom = min(size.height, ctx.safeRect.maxY - ctx.origin.y)
        if topBar { layoutTopBar(size: size, safeTop: safeTop, safeBottom: safeBottom, ctx); return }
        if let tv { layoutTV(tv, size: size, ctx); return }
        if design.isGlass, barVisible, !items.isEmpty { layoutGlassBar(size: size, safeTop: safeTop, ctx); return }
        let compact = m.isCompactHeight
        barTop = barVisible ? safeBottom - (compact ? m.compactHeight : m.height) : safeBottom
        barBottom = max(size.height, ctx.container.maxY - ctx.origin.y)
        backgroundX = ctx.container.minX - ctx.origin.x
        backgroundWidth = ctx.container.width

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
            if compact {
                // Icon and title side by side, centred in the item.
                let iconSize = item.icon?.sizeThatFits(.unspecified) ?? .zero
                var titleSize = item.title?.sizeThatFits(ProposedViewSize(width: itemWidth - iconSize.width - 8, height: nil)) ?? .zero
                titleSize.width = min(titleSize.width, itemWidth - iconSize.width - 8)
                let gap = item.icon != nil && item.title != nil ? m.compactIconTitleGap : 0
                let x0 = cx - (iconSize.width + gap + titleSize.width) / 2
                let midY = barTop + m.compactHeight / 2
                item.icon?.place(at: CGPoint(x: x0, y: midY - iconSize.height / 2), size: iconSize, ctx)
                item.title?.place(at: CGPoint(x: x0 + iconSize.width + gap, y: midY - titleSize.height / 2), size: titleSize, ctx)
                if let badge = item.badge {
                    let s = badge.sizeThatFits(.unspecified)
                    badge.place(at: CGPoint(x: x0 + iconSize.width - 4, y: barTop - 3), size: s, ctx)
                }
                continue
            }
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

    // MARK: Liquid Glass bar

    private func layoutGlassBar(size: CGSize, safeTop: CGFloat, _ ctx: PlaceContext) {
        let g = TabBarMetrics.forDesign(design)
        var overlap: CGFloat = 0
        let compact = TabBarMetrics.isCompactHeight
        let device = _currentConfiguration().device
        let screen = ctx.container.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        let height = compact ? g.compactHeight : g.height
        let bottom = screen.maxY - (device.safeArea.bottom > 0 ? g.bottomInset : g.bottomInsetWithoutHomeIndicator)
        let top = bottom - height
        barTop = top
        let leftLimit = max(screen.minX + g.sideInset, ctx.safeRect.minX - ctx.origin.x)
        let rightLimit = min(screen.maxX - g.sideInset, ctx.safeRect.maxX - ctx.origin.x)
        let available = max(0, rightLimit - leftLimit)
        let separate = separateIndex
        let mainIndices = items.indices.filter { $0 != separate }
        let extra = separate == nil ? 0 : g.separateGap + height

        // Item widths in the main capsule: equal shares in portrait; sized to content in compact height.
        var widths: [CGFloat]
        var mainWidth: CGFloat
        if compact {
            widths = mainIndices.map { i in
                let item = items[i]
                let iw = item.icon?.sizeThatFits(.unspecified).width ?? 0
                let tw = item.title?.sizeThatFits(.unspecified).width ?? 0
                let gap: CGFloat = item.icon != nil && item.title != nil ? g.compactIconTitleGap : 0
                return iw + gap + tw + g.compactItemPadding * 2
            }
            mainWidth = widths.reduce(0, +) + g.pillInset * 2
            if mainWidth + extra > available {
                let k = max(0, available - extra - g.pillInset * 2) / max(1, mainWidth - g.pillInset * 2)
                widths = widths.map { $0 * k }
                mainWidth = available - extra
            }
        } else {
            // Natural frames; neighbours overlap. They fill the capsule unless they fit at their natural width.
            let n = CGFloat(mainIndices.count)
            overlap = mainIndices.count > 1 ? g.itemOverlapPerTab * n : 0
            let natural = mainIndices.map { i in
                max(g.minItemWidth, (items[i].title?.sizeThatFits(.unspecified).width ?? 0) + g.itemTitlePadding)
            }
            let inner = available - extra - g.pillInset * 2
            // The overlap that makes natural frames fill the capsule exactly.
            let needed = n > 1 ? (natural.reduce(0, +) - inner) / (n - 1) : 0
            if n <= 1 || needed <= 0 {
                // They fit with room to spare: a narrower capsule, centred.
                widths = natural
                mainWidth = natural.reduce(0, +) - overlap * (n - 1) + g.pillInset * 2
            } else if needed <= overlap {
                // A little more overlap makes them fill (4 tabs).
                overlap = needed
                widths = natural
                mainWidth = available - extra
            } else {
                // Stretch the frames that are at the minimum; wider (long-title) frames keep their width.
                widths = natural
                let wide = natural.filter { $0 > g.minItemWidth + 0.01 }
                let narrowCount = n - CGFloat(wide.count)
                let rest = inner + overlap * (n - 1) - wide.reduce(0, +)
                let each = narrowCount > 0 ? rest / narrowCount : 0
                widths = natural.map { $0 > g.minItemWidth + 0.01 && each < $0 ? $0 : each }
                let total = widths.reduce(0, +) - overlap * (n - 1)
                if total > inner + 0.01 { let k = inner / total; widths = widths.map { $0 * k } }
                mainWidth = available - extra
            }
        }
        let groupX = leftLimit + (available - mainWidth - extra) / 2
        capsule = CGRect(x: groupX, y: top, width: mainWidth, height: height)
        separateRect = separate == nil ? .zero : CGRect(x: capsule.maxX + g.separateGap, y: top, width: height, height: height)

        var cells = Array(repeating: CGRect.zero, count: items.count)
        var x = capsule.minX + g.pillInset
        for (k, i) in mainIndices.enumerated() {
            cells[i] = CGRect(x: x, y: top + g.pillInset, width: widths[k], height: height - g.pillInset * 2)
            x += widths[k] - (compact ? 0 : overlap)
        }
        if let separate { cells[separate] = separateRect.insetBy(dx: g.pillInset, dy: g.pillInset) }
        pillRect = cells.indices.contains(selectedIndex) ? cells[selectedIndex] : .zero

        // Accessory capsule above the bar.
        var contentBottom = top
        if let accessory {
            // As wide as the bar; in compact height the bar is narrow, so keep a usable minimum width.
            let groupWidth = compact ? min(available, max(mainWidth + extra, g.compactAccessoryMinWidth)) : available
            accessoryRect = CGRect(x: compact ? leftLimit + (available - groupWidth) / 2 : leftLimit,
                                   y: top - g.accessoryGap - g.accessoryHeight, width: groupWidth, height: g.accessoryHeight)
            contentBottom = accessoryRect.minY
            let inner = accessoryRect.insetBy(dx: g.accessoryPadding, dy: 0)
            var actx = ctx
            actx.container = inner.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
            actx.safeRect = actx.container
            let s = accessory.sizeThatFits(ProposedViewSize(inner.size))
            accessory.place(at: CGPoint(x: inner.midX - min(s.width, inner.width) / 2, y: inner.midY - min(s.height, inner.height) / 2),
                            size: CGSize(width: min(s.width, inner.width), height: min(s.height, inner.height)), actx)
        }

        // Content: laid out above the bar, drawn under it.
        let area = CGRect(x: 0, y: safeTop, width: size.width, height: max(0, contentBottom - safeTop))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + area.minY, width: ctx.safeRect.width, height: area.height)
        let c = content.sizeThatFits(ProposedViewSize(area.size))
        content.place(at: CGPoint(x: area.midX - c.width / 2, y: area.midY - c.height / 2), size: c, inner)

        for (i, item) in items.enumerated() {
            let cell = cells[i]
            let isSeparate = i == separate
            var iconMidX = cell.midX
            var iconTop = top
            if compact || isSeparate {
                // Icon and title side by side (a separate tab shows only its icon), centred in the cell.
                let iconSize = item.icon?.sizeThatFits(.unspecified) ?? .zero
                let showsTitle = !isSeparate && item.title != nil
                let maxTitle = max(0, cell.width - iconSize.width - 8)
                var titleSize = showsTitle ? (item.title?.sizeThatFits(ProposedViewSize(width: maxTitle, height: nil)) ?? .zero) : .zero
                titleSize.width = min(titleSize.width, maxTitle)
                let gap: CGFloat = item.icon != nil && showsTitle ? g.compactIconTitleGap : 0
                let x0 = cell.midX - (iconSize.width + gap + titleSize.width) / 2
                item.icon?.place(at: CGPoint(x: x0, y: cell.midY - iconSize.height / 2), size: iconSize, ctx)
                if showsTitle { item.title?.place(at: CGPoint(x: x0 + iconSize.width + gap, y: cell.midY - titleSize.height / 2), size: titleSize, ctx) }
                else if let title = item.title {
                    // Not drawn (a separate tab shows its icon only), but placed so it still labels the tab.
                    var s = title.sizeThatFits(.unspecified)
                    s.width = min(s.width, cell.width)
                    title.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
                }
                iconMidX = x0 + iconSize.width / 2
                iconTop = cell.midY - iconSize.height / 2 - (g.pillInset + 4)
            } else {
                if let icon = item.icon {
                    let s = icon.sizeThatFits(.unspecified)
                    icon.place(at: CGPoint(x: cell.midX - s.width / 2, y: top + g.iconCenterY - s.height / 2), size: s, ctx)
                }
                if let title = item.title {
                    var s = title.sizeThatFits(ProposedViewSize(width: cell.width - 4, height: nil))
                    s.width = min(s.width, cell.width - 4)
                    let baseline = title.explicitAlignment(VerticalAlignment.firstTextBaseline.key, size: s) ?? s.height
                    title.place(at: CGPoint(x: cell.midX - s.width / 2, y: top + g.titleBaseline - baseline), size: s, ctx)
                }
            }
            if let badge = item.badge {
                let s = badge.sizeThatFits(.unspecified)
                badge.place(at: CGPoint(x: iconMidX + g.badgeLeadingFromIconCenter,
                                        y: compact || isSeparate ? iconTop : top + g.badgeTop), size: s, ctx)
            }
        }
        // Hit frames: the whole cell, to the capsule's outer edge.
        glassItemFrames = cells.enumerated().map { i, cell in
            i == separate ? separateRect : compact ? CGRect(x: cell.minX, y: top, width: cell.width, height: height) : cell
        }
        glassBarFrame = separate == nil ? capsule : capsule.union(separateRect)
    }

    private func drawGlassBar(_ p: Painter) {
        let g = TabBarMetrics.forDesign(design)
        let appearance = GlassAppearance.system(.regular, scheme: scheme, design: design)
        p.fillGlass(.roundedRect(capsule, radius: capsule.height / 2), appearance: appearance)
        if separateIndex != nil {
            p.fillGlass(.roundedRect(separateRect, radius: separateRect.height / 2), appearance: appearance)
        }
        if accessory != nil {
            p.fillGlass(.roundedRect(accessoryRect, radius: accessoryRect.height / 2), appearance: appearance)
        }
        g.drawPill(pillRect, scheme: scheme, design: design, in: p)
        accessory?.draw(p)
        for (i, item) in items.enumerated() {
            item.icon?.draw(p)
            if i != separateIndex { item.title?.draw(p) }
            item.badge?.draw(p)
        }
    }

    private func layoutTopBar(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, _ ctx: PlaceContext) {
        let m = TabBarMetrics.self
        let area = CGRect(x: 0, y: safeTop + m.topBarBand, width: size.width, height: max(0, safeBottom - safeTop - m.topBarBand))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + area.minY, width: ctx.safeRect.width, height: area.height)
        let c = content.sizeThatFits(ProposedViewSize(area.size))
        content.place(at: CGPoint(x: area.midX - c.width / 2, y: area.midY - c.height / 2), size: c, inner)

        let sizes = items.map { $0.title?.sizeThatFits(.unspecified) ?? .zero }
        let widths = sizes.map { $0.width + m.topItemPadding * 2 }
        let total = widths.reduce(0, +) + m.topItemGap * CGFloat(max(0, widths.count - 1)) + m.topBarInset * 2
        let height = design.isGlass ? TabBarMetrics.forDesign(design).topBarHeight : m.topBarHeight
        capsule = CGRect(x: (size.width - total) / 2, y: safeTop + m.topBarGap, width: total, height: height)
        var x = capsule.minX + m.topBarInset
        itemRects = []
        for (item, (s, w)) in zip(items, zip(sizes, widths)) {
            let rect = CGRect(x: x, y: capsule.minY + m.topBarInset, width: w, height: capsule.height - m.topBarInset * 2)
            itemRects.append(rect)
            item.title?.place(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), size: s, ctx)
            x += w + m.topItemGap
        }
    }

    private func drawTopBar(_ p: Painter) {
        let shape = Path(roundedRect: capsule, cornerRadius: capsule.height / 2, style: .circular)
        if design.isGlass {
            p.fillGlass(.roundedRect(capsule, radius: capsule.height / 2), appearance: GlassAppearance.system(.regular, scheme: scheme, design: design))
            if itemRects.indices.contains(selectedIndex) {
                TabBarMetrics.forDesign(design).drawPill(itemRects[selectedIndex], scheme: scheme, design: design, in: p)
            }
            for child in children.dropFirst() { child.draw(p) }
            return
        }
        p.fill(shape, with: .color(SystemColor.secondaryBackground.resolve(scheme)), in: capsule)
        p.stroke(shape, with: .color(SystemColor.separator.resolve(scheme)), style: StrokeStyle(lineWidth: ChromeMetrics.hairline), in: capsule)
        if itemRects.indices.contains(selectedIndex) {
            let r = itemRects[selectedIndex]
            p.fill(Path(roundedRect: r, cornerRadius: r.height / 2, style: .circular), with: .color(SystemColor.tertiaryFill.resolve(scheme)), in: r)
        }
        for child in children.dropFirst() { child.draw(p) }
    }

    override func drawContent(_ p: Painter) {
        content.draw(p)
        guard barVisible else { return }
        if let tv { drawTV(tv, p); return }
        if topBar { drawTopBar(p); return }
        if design.isGlass, !items.isEmpty { drawGlassBar(p); return }
        if showsBackground {
            let rect = CGRect(x: backgroundX, y: barTop, width: backgroundWidth, height: barBottom - barTop)
            p.fill(Path(rect), with: background, in: rect)
            let line = CGRect(x: backgroundX, y: barTop - ChromeMetrics.hairline, width: backgroundWidth, height: ChromeMetrics.hairline)
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
    /// tvOS draws larger page dots (est.).
    var dotScale: CGFloat = 1

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
        dotsCenterY = bottom - TabBarMetrics.pageDotsCenterFromBottom * dotScale
    }

    override func drawContent(_ p: Painter) {
        drawChildren(p)
        guard showsDots, count > 0 else { return }
        let m = TabBarMetrics.self
        let pitch = m.pageDotPitch * dotScale, diameter = m.pageDotDiameter * dotScale
        let total = CGFloat(count - 1) * pitch
        let startX = frame.width / 2 - total / 2
        if showsBackground {
            let bg = CGRect(x: startX - pitch, y: dotsCenterY - m.pageDotsBackgroundHeight * dotScale / 2,
                            width: total + pitch * 2, height: m.pageDotsBackgroundHeight * dotScale)
            p.fill(Path(roundedRect: bg, cornerRadius: bg.height / 2, style: .circular), with: .color(RGBA(0, 0, 0, 0.25)), in: bg)
        }
        for i in 0..<count {
            let x = startX + CGFloat(i) * pitch
            let r = CGRect(x: x - diameter / 2, y: dotsCenterY - diameter / 2, width: diameter, height: diameter)
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
