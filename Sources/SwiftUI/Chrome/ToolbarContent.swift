// Toolbar content: ToolbarItem / ToolbarItemGroup, placements, the result builder, and the
// `.toolbar` modifiers. Items are not drawn where they are declared: they are collected into
// the `NavigationChromeKey` preference and laid out by the enclosing NavigationStack.

// MARK: - Placements

public struct ToolbarItemPlacement: Sendable {
    enum Kind: Hashable, Sendable {
        case leading, trailing, confirmation, principal, bottom, status, secondary, hidden
        /// iOS 27: trailing edge, in its own capsule, never moved into the overflow menu.
        case pinnedTrailing
    }
    let kind: Kind

    public static let automatic = ToolbarItemPlacement(kind: .trailing)
    public static let principal = ToolbarItemPlacement(kind: .principal)
    public static let navigation = ToolbarItemPlacement(kind: .leading)
    public static let primaryAction = ToolbarItemPlacement(kind: .trailing)
    public static let secondaryAction = ToolbarItemPlacement(kind: .secondary)
    public static let status = ToolbarItemPlacement(kind: .status)
    public static let confirmationAction = ToolbarItemPlacement(kind: .confirmation)
    public static let cancellationAction = ToolbarItemPlacement(kind: .leading)
    public static let destructiveAction = ToolbarItemPlacement(kind: .trailing)
    public static let keyboard = ToolbarItemPlacement(kind: .hidden)
    public static let topBarLeading = ToolbarItemPlacement(kind: .leading)
    public static let topBarTrailing = ToolbarItemPlacement(kind: .trailing)
    public static let navigationBarLeading = ToolbarItemPlacement(kind: .leading)
    public static let navigationBarTrailing = ToolbarItemPlacement(kind: .trailing)
    public static let bottomBar = ToolbarItemPlacement(kind: .bottom)
    public static let bottomOrnament = ToolbarItemPlacement(kind: .hidden)
    /// iOS 27: an item pinned to the trailing edge of the navigation bar.
    public static let topBarPinnedTrailing = ToolbarItemPlacement(kind: .pinnedTrailing)
}

/// A bar that toolbar modifiers (`toolbar(_:for:)`, `toolbarBackground`, ...) can target.
public struct ToolbarPlacement: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case automatic, navigationBar, tabBar, bottomBar, other }
    let kind: Kind
    public static let automatic = ToolbarPlacement(kind: .automatic)
    public static let navigationBar = ToolbarPlacement(kind: .navigationBar)
    public static let tabBar = ToolbarPlacement(kind: .tabBar)
    public static let bottomBar = ToolbarPlacement(kind: .bottomBar)
    public static let windowToolbar = ToolbarPlacement(kind: .other)
    public static let bottomOrnament = ToolbarPlacement(kind: .other)
}

public struct ToolbarRole: Sendable {
    let raw: Int
    public static let automatic = ToolbarRole(raw: 0)
    public static let navigationStack = ToolbarRole(raw: 1)
    public static let browser = ToolbarRole(raw: 2)
    public static let editor = ToolbarRole(raw: 3)
}

public struct ToolbarTitleDisplayMode: Sendable {
    let mode: NavigationBarItem.TitleDisplayMode
    public static let automatic = ToolbarTitleDisplayMode(mode: .automatic)
    public static let inline = ToolbarTitleDisplayMode(mode: .inline)
    public static let inlineLarge = ToolbarTitleDisplayMode(mode: .large)
    public static let large = ToolbarTitleDisplayMode(mode: .large)
}

public struct ToolbarCustomizationBehavior: Sendable {
    public static let `default` = ToolbarCustomizationBehavior()
    public static let reorderable = ToolbarCustomizationBehavior()
    public static let disabled = ToolbarCustomizationBehavior()
}

public struct ToolbarDefaultItemKind: Sendable {
    enum Kind: Sendable { case sidebarToggle, title, search }
    let kind: Kind
    public static let sidebarToggle = ToolbarDefaultItemKind(kind: .sidebarToggle)
    public static let title = ToolbarDefaultItemKind(kind: .title)
    public static let search = ToolbarDefaultItemKind(kind: .search)
}

/// iOS 27: how toolbar items collapse while content scrolls. A static frame shows them expanded.
public struct ToolbarMinimizeBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = ToolbarMinimizeBehavior(raw: 0)
    public static let never = ToolbarMinimizeBehavior(raw: 1)
    public static let onScrollDown = ToolbarMinimizeBehavior(raw: 2)
    public static let onScrollUp = ToolbarMinimizeBehavior(raw: 3)
}

/// iOS 27: which items stay visible when a bar runs out of room.
public struct ToolbarItemVisibilityPriority: Hashable, Comparable, Sendable {
    let raw: Int
    public static let automatic = ToolbarItemVisibilityPriority(raw: 0)
    public static let low = ToolbarItemVisibilityPriority(raw: -1)
    public static let high = ToolbarItemVisibilityPriority(raw: 1)
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }
}

// MARK: - Collected items

/// One toolbar item, resolved lazily by the bar that shows it (so the bar decides the font, scheme, ...).
struct ToolbarEntry {
    let placement: ToolbarItemPlacement.Kind
    let resolve: @MainActor (_ adjust: (inout EnvironmentValues) -> Void) -> [Node]
    /// Set on the entry a `ToolbarSpacer` produces (Liquid Glass bars split item groups at it).
    var spacer: ToolbarSpacer.Sizing?
    /// `sharedBackgroundVisibility(_:)`: `.hidden` takes the item off its glass.
    var sharedBackground: Visibility = .automatic
    /// `DefaultToolbarItem(kind: .search)`: where the search field goes in a Liquid Glass bar.
    var isSearchSlot = false

    init(placement: ToolbarItemPlacement.Kind, spacer: ToolbarSpacer.Sizing? = nil, isSearchSlot: Bool = false,
         resolve: @escaping @MainActor (_ adjust: (inout EnvironmentValues) -> Void) -> [Node]) {
        self.placement = placement
        self.resolve = resolve
        self.spacer = spacer
        self.isSearchSlot = isSearchSlot
    }
    /// Entries that only steer Liquid Glass layout and must not reach the iOS 18 bar.
    var isGlassOnly: Bool { isSearchSlot || (spacer != nil && placement != .bottom) }
}

// MARK: - ToolbarContent

@MainActor @preconcurrency
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    @ToolbarContentBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

@MainActor @preconcurrency
public protocol CustomizableToolbarContent: ToolbarContent where Body: CustomizableToolbarContent {}

extension Never: ToolbarContent, CustomizableToolbarContent {}

/// Built-in toolbar content collects its items directly instead of having a body.
protocol PrimitiveToolbarContent {
    @MainActor func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry])
}

extension ToolbarContent where Body == Never {
    public var body: Never { fatalError("\(Self.self) is primitive toolbar content") }
}

@MainActor
func collectToolbar<T: ToolbarContent>(_ content: T, _ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
    if let primitive = content as? PrimitiveToolbarContent {
        primitive.collect(ctx, into: &out)
        return
    }
    let ctx = ctx.child(ObjectIdentifier(T.self))
    installDynamicProperties(of: content, ctx)
    collectToolbar(content.body, ctx, into: &out)
}

public struct ToolbarItem<ID, Content: View>: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let placement: ToolbarItemPlacement
    let content: Content

    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        let content = self.content
        let index = out.count
        out.append(ToolbarEntry(placement: placement.kind) { adjust in
            resolveNodes(content, ctx.child("toolbarItem\(index)").with(adjust))
        })
    }
}

extension ToolbarItem where ID == () {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

extension ToolbarItem where ID == String {
    public init(id: String, placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
    @available(*, deprecated)
    public init(id: String, placement: ToolbarItemPlacement = .automatic, showsByDefault: Bool, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

public struct ToolbarItemGroup<Content: View>: ToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let placement: ToolbarItemPlacement
    let content: Content
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
    public init<L: View>(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content,
                         @ViewBuilder label: () -> L) {
        self.placement = placement
        self.content = content()
    }
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        let content = self.content
        let index = out.count
        // A group contributes each of its views as a separate item.
        out.append(ToolbarEntry(placement: placement.kind) { adjust in
            resolveNodes(content, ctx.child("toolbarGroup\(index)").with(adjust))
        })
    }
}

/// `ToolbarSpacer` (iOS 26): fixed or flexible space between items. Liquid Glass bars split item
/// groups at it; the iOS 18 bar only honours it in a bottom bar (a flexible spacer spreads items like `Spacer()`).
public struct ToolbarSpacer: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    public enum Sizing: Sendable { case fixed, flexible }
    let sizing: Sizing
    let placement: ToolbarItemPlacement
    public init(_ sizing: Sizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        guard placement.kind == .bottom else {
            out.append(ToolbarEntry(placement: placement.kind, spacer: sizing) { _ in [] })
            return
        }
        let flexible = sizing == .flexible
        out.append(ToolbarEntry(placement: .bottom, spacer: sizing) { _ in [SpacerNode(axis: .horizontal, minLength: flexible ? 8 : 16)] })
    }
}

/// System-provided items. Only the search item has an effect: it says where a Liquid Glass bar puts
/// the `.searchable` field. The sidebar toggle and title have nothing to draw on a compact iPhone bar.
public struct DefaultToolbarItem: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let kind: ToolbarDefaultItemKind
    let placement: ToolbarItemPlacement
    public init(kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic) {
        self.kind = kind
        self.placement = placement
    }
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        guard kind.kind == .search else { return }
        out.append(ToolbarEntry(placement: placement.kind, isSearchSlot: true) { _ in [] })
    }
}

/// iOS 27: the overflow ("More") menu of a bar, with explicit content. Drawn closed, as the ellipsis item.
public struct ToolbarOverflowMenu<Content: View>: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) {}
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        out.append(ToolbarEntry(placement: .secondary) { _ in [] })
    }
}

/// `ToolbarTitleMenu`: the menu behind the navigation title. Static frame: the title is unchanged.
public struct ToolbarTitleMenu<Content: View>: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) {}
    public init() where Content == EmptyView {}
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {}
}

/// Plain views placed directly inside a toolbar builder (`.toolbar { Button(...) }`).
struct ViewToolbarContent<Content: View>: ToolbarContent, PrimitiveToolbarContent {
    typealias Body = Never
    let placement: ToolbarItemPlacement
    let content: Content
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        ToolbarItemGroup(placement: placement) { content }.collect(ctx, into: &out)
    }
}

public struct TupleToolbarContent<T>: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let collector: @MainActor (ResolveContext, inout [ToolbarEntry]) -> Void
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) { collector(ctx, &out) }
}

public struct _ConditionalToolbarContent<TrueContent: ToolbarContent, FalseContent: ToolbarContent>: ToolbarContent,
    CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    enum Storage { case trueContent(TrueContent), falseContent(FalseContent) }
    let storage: Storage
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        switch storage {
        case .trueContent(let c): collectToolbar(c, ctx.child("true"), into: &out)
        case .falseContent(let c): collectToolbar(c, ctx.child("false"), into: &out)
        }
    }
}

public struct _OptionalToolbarContent<Wrapped: ToolbarContent>: ToolbarContent, CustomizableToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let wrapped: Wrapped?
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        if let wrapped { collectToolbar(wrapped, ctx.child("some"), into: &out) }
    }
}

@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildExpression<Content: ToolbarContent>(_ content: Content) -> Content { content }
    public static func buildBlock() -> TupleToolbarContent<()> { TupleToolbarContent { _, _ in } }
    public static func buildBlock<Content: ToolbarContent>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: ToolbarContent>(_ content: repeat each Content) -> TupleToolbarContent<(repeat each Content)> {
        TupleToolbarContent { ctx, out in
            var index = 0
            for child in repeat each content {
                collectToolbar(child, ctx.child(index), into: &out)
                index += 1
            }
        }
    }
    public static func buildIf<Content: ToolbarContent>(_ content: Content?) -> _OptionalToolbarContent<Content> { .init(wrapped: content) }
    public static func buildOptional<Content: ToolbarContent>(_ content: Content?) -> _OptionalToolbarContent<Content> { .init(wrapped: content) }
    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(first: T) -> _ConditionalToolbarContent<T, F> { .init(storage: .trueContent(first)) }
    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(second: F) -> _ConditionalToolbarContent<T, F> { .init(storage: .falseContent(second)) }
    public static func buildLimitedAvailability<Content: ToolbarContent>(_ content: Content) -> Content { content }
}

extension ToolbarContent {
    public func hidden(_ hidden: Bool = true) -> some ToolbarContent { _HiddenToolbarContent(base: self, isHidden: hidden) }
    /// iOS 26: `.hidden` draws the item without the glass it would share with its neighbours.
    public func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        _SharedBackgroundToolbarContent(base: self, visibility: visibility)
    }
    /// iOS 27: which items stay when the bar is crowded. Every item fits in a static frame, so it has no effect.
    public func visibilityPriority(_ priority: ToolbarItemVisibilityPriority) -> Self { self }
}

public struct _SharedBackgroundToolbarContent<Base: ToolbarContent>: ToolbarContent, PrimitiveToolbarContent {
    public typealias Body = Never
    let base: Base
    let visibility: Visibility
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        let start = out.count
        collectToolbar(base, ctx, into: &out)
        for i in start..<out.count { out[i].sharedBackground = visibility }
    }
}
extension _SharedBackgroundToolbarContent: CustomizableToolbarContent where Base: CustomizableToolbarContent {}
extension CustomizableToolbarContent {
    public func defaultCustomization(_ defaultVisibility: Visibility = .automatic, options: ToolbarCustomizationOptions = []) -> Self { self }
    public func customizationBehavior(_ behavior: ToolbarCustomizationBehavior) -> Self { self }
}
public struct ToolbarCustomizationOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alwaysAvailable = ToolbarCustomizationOptions(rawValue: 1)
}

struct _HiddenToolbarContent<Base: ToolbarContent>: ToolbarContent, PrimitiveToolbarContent {
    typealias Body = Never
    let base: Base
    let isHidden: Bool
    func collect(_ ctx: ResolveContext, into out: inout [ToolbarEntry]) {
        if !isHidden { collectToolbar(base, ctx, into: &out) }
    }
}

// MARK: - Modifiers

/// Writes the navigation chrome preference on the first node the content produces.
struct NavigationChromeModifier: ViewModifier, PrimitiveModifier {
    let apply: @MainActor (inout NavigationChrome, ResolveContext) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = content.nodes(ctx)
        if let first = nodes.first {
            var value = first.preferences[NavigationChromeKey.self]
            apply(&value, ctx)
            first.preferences.set(NavigationChromeKey.self, value)
        }
        out.append(contentsOf: nodes)
    }
}

extension View {
    func navigationChrome(_ apply: @escaping @MainActor (inout NavigationChrome, ResolveContext) -> Void) -> some View {
        modifier(NavigationChromeModifier(apply: apply))
    }

    func barSettings(_ bars: [ToolbarPlacement], _ apply: @escaping (inout NavigationChrome.BarSettings) -> Void) -> some View {
        navigationChrome { chrome, _ in
            for bar in bars {
                // `.automatic` targets the bars of the current context: the navigation bar here.
                let kind = bar.kind == .automatic ? ToolbarPlacement.Kind.navigationBar : bar.kind
                apply(&chrome.bars[kind, default: .init()])
            }
        }
    }

    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return navigationChrome { chrome, ctx in
            var outer: [ToolbarEntry] = []
            ViewToolbarContent(placement: .automatic, content: content).collect(ctx.child("toolbar"), into: &outer)
            chrome.addOuterToolbarItems(outer)
        }
    }
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        let content = content()
        return navigationChrome { chrome, ctx in
            var outer: [ToolbarEntry] = []
            collectToolbar(content, ctx.child("toolbar"), into: &outer)
            chrome.addOuterToolbarItems(outer)
        }
    }
    public func toolbar<Content: CustomizableToolbarContent>(id: String, @ToolbarContentBuilder content: () -> Content) -> some View {
        let content = content()
        return navigationChrome { chrome, ctx in
            var outer: [ToolbarEntry] = []
            collectToolbar(content, ctx.child("toolbar"), into: &outer)
            chrome.addOuterToolbarItems(outer)
        }
    }

    public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        barSettings(bars) { $0.visibility = visibility }
    }
    public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        barSettings(bars) { $0.visibility = visibility }
    }
    public func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> some View {
        let style = AnyShapeStyle(style)
        return barSettings(bars) { $0.backgroundStyle = style }
    }
    public func toolbarBackground(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        barSettings(bars) { $0.backgroundVisibility = visibility }
    }
    public func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        barSettings(bars) { $0.backgroundVisibility = visibility }
    }
    public func toolbarColorScheme(_ colorScheme: ColorScheme?, for bars: ToolbarPlacement...) -> some View {
        barSettings(bars) { $0.colorScheme = colorScheme }
    }
    public func toolbarTitleDisplayMode(_ mode: ToolbarTitleDisplayMode) -> some View {
        navigationChrome { chrome, _ in chrome.titleDisplayMode = mode.mode }
    }
    public func toolbarRole(_ role: ToolbarRole) -> some View { self }
    public func toolbarTitleMenu<C: View>(@ViewBuilder content: () -> C) -> some View { self }
    public func toolbarBackground<V: View>(@ViewBuilder content: () -> V) -> some View { self }
    public func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View { self }
    /// iOS 27: collapsing bars on scroll. A static frame shows the bars expanded.
    public func toolbarMinimizeBehavior(_ behavior: ToolbarMinimizeBehavior, for bars: ToolbarPlacement...) -> some View { self }
}
