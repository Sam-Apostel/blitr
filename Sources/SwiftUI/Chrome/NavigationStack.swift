// NavigationStack / NavigationView / NavigationSplitView and the navigation bar they draw.
//
// Content describes its bar through the `NavigationChromeKey` preference (title, display mode,
// toolbar items, search, bar visibility/background). The stack consumes it, draws the bar at the
// top of the safe area (and a bottom toolbar if asked), and lays the content out below it with a
// shrunken `safeRect` and the original `container`, so backgrounds still bleed under the bar.

/// Every metric of the navigation bar, in points (iOS 18, compact width).
enum NavigationBarMetrics {
    /// 44pt; 32pt on a landscape iPhone (compact height).
    static var barHeight: CGFloat {
        let device = _currentConfiguration().device
        return device.idiom == .phone && device.orientation.isLandscape ? 32 : ChromeMetrics.navigationBarHeight
    }
    static let largeTitleHeight = ChromeMetrics.largeTitleHeight        // 52
    /// Large title baseline, measured up from the bottom of the large title region.
    static let largeTitleBaselineInset: CGFloat = 8
    static let inlineTitleFont = Font.system(size: 17, weight: .semibold)
    static let largeTitleFont = Font.system(size: 34, weight: .bold)
    static let itemFont = Font.body
    static let itemSpacing: CGFloat = 16
    /// Minimum gap between the inline title / principal item and the bar items.
    static let titleItemGap: CGFloat = 8
    // Back button: chevron + previous title.
    static let backChevronLeading: CGFloat = 8
    static let backChevronSize = CGSize(width: 11, height: 19)
    static let backChevronLineWidth: CGFloat = 2.6
    static let backTitleLeading: CGFloat = 28
    /// A back title wider than this fraction of the bar collapses to "Back".
    static let backTitleMaxFraction: CGFloat = 0.32
    // Bottom toolbar.
    static let bottomBarHeight = ChromeMetrics.toolbarHeight            // 44
}

// MARK: - Display mode

public struct NavigationBarItem: Sendable {
    public enum TitleDisplayMode: Hashable, Sendable { case automatic, inline, large }
}

// MARK: - Chrome preference

struct NavigationTitle {
    let plain: String
    /// Builds the title node with the bar's environment adjustments applied.
    let make: @MainActor ((inout EnvironmentValues) -> Void) -> Node
}

struct NavigationChrome {
    struct BarSettings {
        var visibility: Visibility?
        var backgroundVisibility: Visibility?
        var backgroundStyle: AnyShapeStyle?
        var colorScheme: ColorScheme??

        mutating func fill(from other: BarSettings) {
            visibility = visibility ?? other.visibility
            backgroundVisibility = backgroundVisibility ?? other.backgroundVisibility
            backgroundStyle = backgroundStyle ?? other.backgroundStyle
            colorScheme = colorScheme ?? other.colorScheme
        }
    }

    var title: NavigationTitle?
    /// `navigationSubtitle` (iOS 26): shown by Liquid Glass bars only.
    var subtitle: NavigationTitle?
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode?
    var toolbarItems: [ToolbarEntry] = []
    var backButtonHidden: Bool?
    var search: SearchConfiguration?
    var destinations: [ObjectIdentifier: (AnyHashable) -> AnyView?] = [:]
    /// Destinations pushed by `navigationDestination(isPresented:)`, `(item:)` or an active NavigationLink.
    var presented: [AnyView] = []
    var bars: [ToolbarPlacement.Kind: BarSettings] = [:]
    /// `scrollEdgeEffectStyle` / `scrollEdgeEffectHidden` for the top and bottom bars.
    var topEdgeEffectStyle: ScrollEdgeEffectStyle?
    var bottomEdgeEffectStyle: ScrollEdgeEffectStyle?
    var topEdgeEffectHidden: Bool?
    var bottomEdgeEffectHidden: Bool?

    /// Siblings: the first one to say something wins; items and destinations accumulate.
    mutating func merge(_ next: NavigationChrome) {
        title = title ?? next.title
        subtitle = subtitle ?? next.subtitle
        topEdgeEffectStyle = topEdgeEffectStyle ?? next.topEdgeEffectStyle
        bottomEdgeEffectStyle = bottomEdgeEffectStyle ?? next.bottomEdgeEffectStyle
        topEdgeEffectHidden = topEdgeEffectHidden ?? next.topEdgeEffectHidden
        bottomEdgeEffectHidden = bottomEdgeEffectHidden ?? next.bottomEdgeEffectHidden
        titleDisplayMode = titleDisplayMode ?? next.titleDisplayMode
        toolbarItems += next.toolbarItems
        backButtonHidden = backButtonHidden ?? next.backButtonHidden
        search = search ?? next.search
        destinations.merge(next.destinations) { mine, _ in mine }
        presented += next.presented
        for (kind, settings) in next.bars { bars[kind, default: .init()].fill(from: settings) }
    }

    /// What a navigation stack lets through to its ancestors (a TabView reads the tab bar settings).
    var passthrough: NavigationChrome {
        var result = NavigationChrome()
        result.bars = bars.filter { $0.key == .tabBar }
        return result
    }
}

enum NavigationChromeKey: PreferenceKey {
    static let defaultValue = NavigationChrome()
    static func reduce(value: inout NavigationChrome, nextValue: () -> NavigationChrome) { value.merge(nextValue()) }
}

// MARK: - NavigationPath

public struct NavigationPath: Equatable {
    var elements: [AnyHashable]
    public init() { elements = [] }
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable { self.elements = elements.map { AnyHashable($0) } }
    public init(_ codable: CodableRepresentation) { elements = [] }
    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }
    public var codable: CodableRepresentation? { nil }
    public mutating func append<V: Hashable>(_ value: V) { elements.append(AnyHashable(value)) }
    public mutating func removeLast(_ k: Int = 1) { elements.removeLast(Swift.min(k, elements.count)) }

    public struct CodableRepresentation: Codable, Equatable {
        public init(from decoder: Decoder) throws {}
        public func encode(to encoder: Encoder) throws {}
    }
}

// MARK: - Public containers

public struct NavigationStack<Data, Root: View>: View, PrimitiveView {
    public typealias Body = Never
    let root: Root
    let path: () -> [AnyHashable]

    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        path = { [] }
    }
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.path = { path.wrappedValue.elements }
    }
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.root = root()
        self.path = { path.wrappedValue.map { AnyHashable($0) } }
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let root = self.root
        out.append(makeNavigationStack(ctx, path: path()) { resolveSingle(root, $0) })
    }
}

public struct NavigationView<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let content = self.content
        // On a compact-width device only the first column (the stack root) is visible.
        out.append(makeNavigationStack(ctx, path: []) { ctx in
            let nodes = resolveNodes(content, ctx)
            if nodes.count > 1 { Runtime.current?.warn("NavigationView with several columns: only the first is shown on iPhone") }
            return nodes.first ?? EmptyNode()
        })
    }
}

public struct NavigationSplitViewVisibility: Hashable, Sendable {
    let raw: Int
    public static let automatic = NavigationSplitViewVisibility(raw: 0)
    public static let all = NavigationSplitViewVisibility(raw: 1)
    public static let doubleColumn = NavigationSplitViewVisibility(raw: 2)
    public static let detailOnly = NavigationSplitViewVisibility(raw: 3)
}

public enum NavigationSplitViewColumn: Hashable, Sendable { case sidebar, content, detail }

public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View, PrimitiveView {
    public typealias Body = Never
    let sidebar: Sidebar
    let content: Content?
    let detail: Detail
    let compactColumn: NavigationSplitViewColumn

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); compactColumn = .sidebar
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar, content: content, detail: detail)
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>,
                @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); compactColumn = preferredCompactColumn.wrappedValue
    }
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); self.content = nil; self.detail = detail(); compactColumn = .sidebar
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(sidebar: sidebar, detail: detail)
    }
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); self.content = nil; self.detail = detail(); compactColumn = preferredCompactColumn.wrappedValue
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>,
                @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(preferredCompactColumn: preferredCompactColumn, sidebar: sidebar, detail: detail)
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        // Regular width on an iPad shows the columns side by side.
        if _currentConfiguration().device.idiom == .pad, ctx.env.horizontalSizeClass == .regular {
            out.append(resolveColumns(ctx))
            return
        }
        // Compact width collapses the split view into one stack showing the preferred column.
        let (sidebar, content, detail, column) = (self.sidebar, self.content, self.detail, compactColumn)
        out.append(makeNavigationStack(ctx, path: []) { ctx in
            switch column {
            case .detail: return resolveSingle(detail, ctx.child("detail"))
            case .content: if let content { return resolveSingle(content, ctx.child("content")) }
            case .sidebar: break
            }
            return resolveSingle(sidebar, ctx.child("sidebar"))
        })
    }
}

public protocol NavigationSplitViewStyle {}
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle { public init() {} }
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle { public init() {} }
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle { public init() {} }
extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle { public static var automatic: Self { .init() } }
extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle { public static var balanced: Self { .init() } }
extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle { public static var prominentDetail: Self { .init() } }

public protocol NavigationViewStyle {}
public struct DefaultNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct StackNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct DoubleColumnNavigationViewStyle: NavigationViewStyle { public init() {} }
extension NavigationViewStyle where Self == DefaultNavigationViewStyle { public static var automatic: Self { .init() } }
extension NavigationViewStyle where Self == StackNavigationViewStyle { public static var stack: Self { .init() } }
extension NavigationViewStyle where Self == DoubleColumnNavigationViewStyle { public static var columns: Self { .init() } }

final class EmptyNode: Node {}

// MARK: - Building the stack

enum NavigationSearchKey: EnvironmentKey { static let defaultValue: SearchConfiguration? = nil }
extension EnvironmentValues {
    /// `.searchable` applied outside a NavigationStack reaches the stack through the environment.
    var navigationSearch: SearchConfiguration? {
        get { self[NavigationSearchKey.self] }
        set { self[NavigationSearchKey.self] = newValue }
    }
}

@MainActor
func makeNavigationStack(_ ctx: ResolveContext, path: [AnyHashable], root: (ResolveContext) -> Node) -> Node {
    let outerSearch = ctx.env.navigationSearch
    let contentCtx = ctx.with { $0.navigationSearch = nil; $0.navigationStackIdentity = ctx.path }

    // Root, then each path element through its registered destination, then presented destinations.
    var pages: [(node: Node, chrome: NavigationChrome)] = []
    let rootNode = root(contentCtx.child("root"))
    pages.append((rootNode, rootNode.preferences[NavigationChromeKey.self]))
    var destinations = pages[0].chrome.destinations
    for (i, element) in path.enumerated() {
        guard let make = destinations[ObjectIdentifier(type(of: element.base))], let view = make(element) else {
            Runtime.current?.warn("NavigationStack path contains a \(type(of: element.base)) with no matching navigationDestination; showing the last resolvable screen")
            break
        }
        let node = resolveSingle(view, contentCtx.child("path\(i)"))
        let chrome = node.preferences[NavigationChromeKey.self]
        destinations.merge(chrome.destinations) { mine, _ in mine }
        pages.append((node, chrome))
    }
    var depth = 0
    while let view = pages.last?.chrome.presented.first, depth < 8 {
        let node = resolveSingle(view, contentCtx.child("presented\(depth)"))
        pages.append((node, node.preferences[NavigationChromeKey.self]))
        depth += 1
    }
    // Screens pushed by remote `select` on a NavigationLink (focus engine), on top of everything else.
    for (i, push) in (ctx.runtime.focus.pushes[ctx.path] ?? []).enumerated() {
        let view: AnyView
        switch push {
        case .view(let v): view = v
        case .value(let value):
            for page in pages { destinations.merge(page.chrome.destinations) { mine, _ in mine } }
            guard let make = destinations[ObjectIdentifier(type(of: value.base))], let v = make(value) else {
                ctx.runtime.warn("NavigationLink value of type \(type(of: value.base)) has no matching navigationDestination; select cannot push it")
                continue
            }
            view = v
        }
        let node = resolveSingle(view, contentCtx.child("pushed\(i)"))
        pages.append((node, node.preferences[NavigationChromeKey.self]))
    }

    // The title display mode is inherited down the stack; `.automatic` at the root means large.
    var mode = NavigationBarItem.TitleDisplayMode.large
    for page in pages {
        if let m = page.chrome.titleDisplayMode, m != .automatic { mode = m }
    }
    let top = pages[pages.count - 1]
    var chrome = top.chrome
    if pages.count == 1, chrome.search == nil { chrome.search = outerSearch }
    let previousTitle: String? = pages.count > 1 ? (pages[pages.count - 2].chrome.title?.plain ?? "") : nil
    let node = NavigationStackNode(content: top.node, chrome: chrome, displayMode: mode, previousTitle: previousTitle, ctx: ctx)
    return node
}

// MARK: - Bar parts

/// The back button of a pushed screen: accent chevron + previous title (or "Back").
final class BackButtonNode: Node {
    let color: _Paint
    /// Liquid Glass: a chevron only, drawn on the glass circle of its `ToolbarGlassGroupNode`.
    let glass: NavigationGlassMetrics?
    var title: Node? { children.first }
    init(title: Node?, color: _Paint, glass: NavigationGlassMetrics? = nil) {
        self.color = color
        self.glass = glass
        super.init(children: title.map { [$0] } ?? [])
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        if let g = glass { return CGSize(width: g.backChevronSize.height + 4, height: g.backChevronSize.height + 4) }
        let m = NavigationBarMetrics.self
        let t = title?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: title == nil ? m.backChevronLeading + m.backChevronSize.width + 4 : m.backTitleLeading + t.width,
                      height: m.barHeight)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        guard let title, glass == nil else { return }
        let t = title.sizeThatFits(.unspecified)
        title.place(at: CGPoint(x: NavigationBarMetrics.backTitleLeading, y: (size.height - t.height) / 2), size: t, ctx)
    }
    override func drawContent(_ p: Painter) {
        if let g = glass {
            let (w, h) = (g.backChevronSize.width, g.backChevronSize.height)
            let cx = frame.width / 2 + g.backChevronOffsetX, cy = frame.height / 2
            var chevron = Path()
            chevron.move(to: CGPoint(x: cx + w / 2, y: cy - h / 2))
            chevron.addLine(to: CGPoint(x: cx - w / 2, y: cy))
            chevron.addLine(to: CGPoint(x: cx + w / 2, y: cy + h / 2))
            p.stroke(chevron, with: color, style: StrokeStyle(lineWidth: g.backChevronLineWidth, lineCap: .round, lineJoin: .round),
                     in: CGRect(origin: .zero, size: frame.size))
            return
        }
        let m = NavigationBarMetrics.self
        let midY = frame.height / 2
        let x0 = m.backChevronLeading + m.backChevronLineWidth / 2
        var chevron = Path()
        chevron.move(to: CGPoint(x: x0 + m.backChevronSize.width, y: midY - m.backChevronSize.height / 2))
        chevron.addLine(to: CGPoint(x: x0, y: midY))
        chevron.addLine(to: CGPoint(x: x0 + m.backChevronSize.width, y: midY + m.backChevronSize.height / 2))
        p.stroke(chevron, with: color, style: StrokeStyle(lineWidth: m.backChevronLineWidth, lineCap: .round, lineJoin: .round),
                 in: CGRect(origin: .zero, size: frame.size))
        drawChildren(p)
    }
}

/// The overflow button `.secondaryAction` items collapse into.
final class EllipsisCircleNode: Node {
    let color: _Paint
    /// Liquid Glass: three dots (`ellipsis`) on the item's glass instead of a ringed glyph.
    let onGlass: Bool
    init(color: _Paint, onGlass: Bool = false) { self.color = color; self.onGlass = onGlass; super.init() }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { CGSize(width: 23, height: 23) }
    override func drawContent(_ p: Painter) {
        if onGlass {
            let mid = CGPoint(x: frame.width / 2, y: frame.height / 2)
            for i in -1...1 {
                let dot = CGRect(x: mid.x + CGFloat(i) * 7 - 1.9, y: mid.y - 1.9, width: 3.8, height: 3.8)
                p.fill(Path(ellipseIn: dot), with: color, in: dot)
            }
            return
        }
        let r = CGRect(origin: .zero, size: frame.size).insetBy(dx: 1.5, dy: 1.5)
        p.stroke(Path(ellipseIn: r), with: color, style: StrokeStyle(lineWidth: 1.7), in: r)
        for i in -1...1 {
            let c = CGPoint(x: r.midX + CGFloat(i) * 5, y: r.midY)
            let dot = CGRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)
            p.fill(Path(ellipseIn: dot), with: color, in: dot)
        }
    }
}

// MARK: - The stack node

final class NavigationStackNode: Node {
    let content: Node
    let barVisible: Bool
    let showsLargeTitle: Bool
    let inlineTitle: Node?
    let largeTitle: Node?
    let principal: Node?
    let leading: [Node]
    let trailing: [Node]
    let search: SearchFieldNode?
    let bottomItems: Node?
    let statusItem: Node?
    /// Nav bar background when shown (nil = transparent, the iOS 15+ scroll-edge look).
    let barBackground: _Paint?
    let hairline: _Paint
    let bottomBackground: _Paint
    let bottomBackgroundVisibility: Visibility
    /// `navigationSubtitle`, shown by Liquid Glass bars only.
    let subtitle: Node?
    /// Liquid Glass bar metrics; nil draws the iOS 18 bar.
    let glass: NavigationGlassMetrics?
    /// Glass: the search field may go to the bottom bar (iPhone, automatic/toolbar placement).
    private let searchPrefersBottom: Bool
    private let tabBarHostsContent: Bool
    private let topEdgeHard: Bool, bottomEdgeHard: Bool
    private let topEdgeHidden: Bool, bottomEdgeHidden: Bool
    /// Wash laid into the soft scroll edge; bar material of the hard one.
    private let edgeTint: RGBA
    private let edgeMaterial: _Paint
    private var showsTopEdge = false
    private var showsBottomEdge = false

    // Computed in layout (local coordinates).
    private var barTop: CGFloat = 0
    private var barRegionBottom: CGFloat = 0
    private var backgroundTop: CGFloat = 0
    /// Bars extend under the side safe areas (a landscape iPhone), like the container does.
    private var backgroundX: CGFloat = 0
    private var backgroundWidth: CGFloat = 0
    private var bottomBarTop: CGFloat?
    private var bottomBackgroundBottom: CGFloat = 0
    private var showsBottomBackground = false

    init(content: Node, chrome: NavigationChrome, displayMode: NavigationBarItem.TitleDisplayMode,
         previousTitle: String?, ctx: ResolveContext) {
        let env = ctx.env
        let navBar = chrome.bars[.navigationBar] ?? .init()
        let bottomBar = chrome.bars[.bottomBar] ?? .init()
        let barScheme = (navBar.colorScheme ?? nil) ?? env.colorScheme
        self.content = content
        barVisible = navBar.visibility != .hidden

        let glass: NavigationGlassMetrics? = env.designLanguage.isGlass ? .forDesign(env.designLanguage) : nil
        self.glass = glass

        // Environment every bar element is resolved with.
        let barAdjust: (inout EnvironmentValues) -> Void
        if let glass {
            // Liquid Glass: medium-weight 17pt labels, monochrome (an item's own `.tint` still applies),
            // buttons report their role, labels show their icon.
            barAdjust = { e in
                e.colorScheme = barScheme
                e.font = glass.itemFont
                e.imageScale = .medium
                e.stackAxis = .horizontal
                e.isInListRow = false
                e.lineLimit = 1
                e.accentColor = Color.primary
                e.buttonStyleBox = .toolbarGlass
                e.labelStyleBox = .toolbarIconOnly
            }
        } else {
            barAdjust = { e in
                e.colorScheme = barScheme
                e.font = NavigationBarMetrics.itemFont
                e.imageScale = .large
                e.stackAxis = .horizontal
                e.isInListRow = false
                e.lineLimit = 1
            }
        }
        var barEnv = env
        barAdjust(&barEnv)
        let accent = _Paint.color(Color.accentColor.rgba(in: barEnv))

        // Items, by placement.
        var leading: [Node] = [], trailing: [Node] = [], bottom: [Node] = []
        var principal: Node?, status: Node?, hasSecondary = false
        var glassRow: ToolbarGlassRowNode?
        if let glass {
            var schemeEnv = env
            schemeEnv.colorScheme = barScheme
            let items = NavigationStackNode.glassItems(chrome, glass: glass, barAdjust: barAdjust, accent: accent,
                                                       hasBack: previousTitle != nil && chrome.backButtonHidden != true, env: schemeEnv)
            (leading, trailing, principal, status) = (items.leading, items.trailing, items.principal, items.status)
            glassRow = items.bottom
        }
        for entry in chrome.toolbarItems where glass == nil && !entry.isGlassOnly {
            switch entry.placement {
            case .leading: leading += entry.resolve(barAdjust)
            case .trailing, .pinnedTrailing: trailing += entry.resolve(barAdjust)
            case .confirmation: trailing += entry.resolve { barAdjust(&$0); $0.font = NavigationBarMetrics.itemFont.weight(.semibold) }
            case .principal:
                let nodes = entry.resolve(barAdjust)
                principal = principal ?? (nodes.count == 1 ? nodes.first : StackNode(axis: .horizontal, alignment: .center, spacing: nil, children: nodes))
            case .bottom: bottom += entry.resolve(barAdjust)
            case .status:
                let nodes = entry.resolve(barAdjust)
                status = status ?? (nodes.count == 1 ? nodes.first : StackNode(axis: .horizontal, alignment: .center, spacing: nil, children: nodes))
            case .secondary: hasSecondary = true
            case .hidden: break
            }
        }
        if hasSecondary { trailing.append(EllipsisCircleNode(color: accent)) }
        if glass == nil, let previousTitle, chrome.backButtonHidden != true {
            var titleEnv = barEnv
            titleEnv.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(accent))
            let backTitle = previousTitle.isEmpty ? nil : Text(verbatim: previousTitle).makeNode(titleEnv)
            leading.insert(BackButtonNode(title: backTitle, color: accent), at: 0)
        }
        self.leading = leading
        self.trailing = trailing
        self.principal = principal
        statusItem = status

        // Titles.
        showsLargeTitle = displayMode == .large && chrome.title.map { !$0.plain.isEmpty } ?? false
        let titleAdjust: (inout EnvironmentValues) -> Void = { e in
            barAdjust(&e)
            e.foregroundStyle = nil
            e.foregroundStyleLevels = nil
            e.fontWeight = nil
            e.truncationMode = .tail
        }
        let subtitleSource = glass == nil ? nil : chrome.subtitle.flatMap { $0.plain.isEmpty ? nil : $0 }
        let inlineFont = glass.map { subtitleSource == nil ? $0.inlineTitleFont : $0.inlineTitleWithSubtitleFont }
            ?? NavigationBarMetrics.inlineTitleFont
        if let title = chrome.title, !title.plain.isEmpty || principal == nil {
            if showsLargeTitle {
                largeTitle = title.make { titleAdjust(&$0); $0.font = NavigationBarMetrics.largeTitleFont }
                inlineTitle = nil
            } else {
                inlineTitle = principal == nil ? title.make { titleAdjust(&$0); $0.font = inlineFont } : nil
                largeTitle = nil
            }
        } else {
            inlineTitle = nil
            largeTitle = nil
        }
        if let glass, let subtitleSource, largeTitle != nil || inlineTitle != nil {
            let secondary = _Paint.color(SystemColor.secondaryLabel.resolve(barScheme))
            let large = largeTitle != nil
            subtitle = subtitleSource.make { e in
                titleAdjust(&e)
                e.font = large ? glass.largeSubtitleFont : glass.inlineSubtitleFont
                e.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(secondary))
            }
        } else {
            subtitle = nil
        }

        search = chrome.search.map { SearchFieldNode(configuration: $0, env: barEnv) }
        searchPrefersBottom = glass != nil && _currentConfiguration().device.idiom == .phone
            && [.automatic, .toolbar].contains(chrome.search?.placement ?? .navigationBarDrawer)
        tabBarHostsContent = env.hasEnclosingTabBar

        // Bottom toolbar: the items' own Spacers distribute them; without any, spread them out.
        if glass != nil {
            bottomItems = glassRow
        } else if !bottom.isEmpty {
            var items = bottom
            if !items.contains(where: { $0 is SpacerNode }) && items.count > 1 {
                items = Array(items.map { [$0, SpacerNode(axis: .horizontal, minLength: 8)] }.joined().dropLast())
            } else if items.count == 1 && status == nil {
                items.append(SpacerNode(axis: .horizontal, minLength: 0))
            }
            bottomItems = StackNode(axis: .horizontal, alignment: .center, spacing: NavigationBarMetrics.itemSpacing, children: items)
        } else {
            bottomItems = nil
        }

        // Backgrounds: at the scroll edge (all a screenshot shows) iOS 15+ draws none unless forced visible.
        var schemeEnv = env
        schemeEnv.colorScheme = barScheme
        if barVisible, navBar.backgroundVisibility == .visible {
            barBackground = navBar.backgroundStyle?._paint(in: schemeEnv) ?? Material.bar._paint(in: schemeEnv)
        } else {
            barBackground = nil
        }
        var bottomEnv = env
        bottomEnv.colorScheme = (bottomBar.colorScheme ?? nil) ?? env.colorScheme
        bottomBackground = bottomBar.backgroundStyle?._paint(in: bottomEnv) ?? Material.bar._paint(in: bottomEnv)
        bottomBackgroundVisibility = bottomBar.backgroundVisibility ?? .automatic
        hairline = .color(SystemColor.separator.resolve(barScheme))

        // Scroll edge effect of glass bars: iOS 26 defaults to soft, iOS 27 to hard.
        func isHard(_ style: ScrollEdgeEffectStyle?) -> Bool {
            let style = style ?? .automatic
            return style == .hard || (style == .automatic && glass?.defaultScrollEdgeHard == true)
        }
        topEdgeHard = isHard(chrome.topEdgeEffectStyle)
        bottomEdgeHard = isHard(chrome.bottomEdgeEffectStyle)
        topEdgeHidden = chrome.topEdgeEffectHidden ?? false
        bottomEdgeHidden = chrome.bottomEdgeEffectHidden ?? false
        edgeTint = SystemColor.background.resolve(barScheme).opacity(glass?.softEdgeTintOpacity ?? 0)
        edgeMaterial = Material.bar._paint(in: schemeEnv)

        var children: [Node] = [content]
        children += [inlineTitle, subtitle, largeTitle, principal, statusItem, bottomItems].compactMap { $0 }
        children += leading + trailing
        if let search { children.append(search) }
        super.init(children: children)
        traits = content.traits

        // Ancestors only see what concerns them (tab bar settings) plus the status bar style.
        preferences = content.preferences
        preferences.set(NavigationChromeKey.self, chrome.passthrough)
        if barBackground != nil, let scheme = navBar.colorScheme ?? nil {
            preferences.set(StatusBarSchemeKey.self, scheme)
        }
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        if let glass {
            layoutGlass(glass, size: size, ctx)
            return
        }
        let m = NavigationBarMetrics.self
        let margin = ChromeMetrics.layoutMargin(forWidth: ctx.container.width)
        barTop = max(0, ctx.safeRect.minY - ctx.origin.y)
        backgroundTop = ctx.container.minY - ctx.origin.y
        backgroundX = ctx.container.minX - ctx.origin.x
        backgroundWidth = ctx.container.width
        var y = barTop
        if barVisible {
            y += m.barHeight
            if showsLargeTitle { y += m.largeTitleHeight }
            if search != nil { y += SearchFieldMetrics.regionHeight }
        }
        barRegionBottom = y

        let safeBottom = min(size.height, ctx.safeRect.maxY - ctx.origin.y)
        var contentBottom = safeBottom
        if bottomItems != nil || statusItem != nil {
            bottomBarTop = safeBottom - m.bottomBarHeight
            contentBottom = safeBottom - m.bottomBarHeight
        } else {
            bottomBarTop = nil
        }

        // Content: proposed the area between the bars and centred in it, like a hosting controller.
        let contentRect = CGRect(x: 0, y: barRegionBottom, width: size.width, height: max(0, contentBottom - barRegionBottom))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + contentRect.minY,
                                width: ctx.safeRect.width, height: contentRect.height)
        let c = content.sizeThatFits(ProposedViewSize(contentRect.size))
        content.place(at: CGPoint(x: contentRect.midX - c.width / 2, y: contentRect.midY - c.height / 2), size: c, inner)

        guard barVisible else { placeBottomBar(size: size, margin: margin, ctx); return }

        // Leading items.
        let itemProposal = ProposedViewSize(width: nil, height: m.barHeight)
        var x = margin
        var leadingEnd: CGFloat = margin
        for (i, item) in leading.enumerated() {
            let s = item.sizeThatFits(itemProposal)
            let isBack = item is BackButtonNode
            let ix = isBack ? 0 : x
            item.place(at: CGPoint(x: ix, y: barTop + (m.barHeight - s.height) / 2), size: s, ctx)
            x = ix + s.width + m.itemSpacing
            leadingEnd = ix + s.width
            _ = i
        }
        // Trailing items, laid out from the right edge in reading order.
        let trailingSizes = trailing.map { $0.sizeThatFits(itemProposal) }
        let trailingWidth = trailingSizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, trailing.count - 1)) * m.itemSpacing
        x = size.width - margin - trailingWidth
        let trailingStart = trailing.isEmpty ? size.width - margin : x
        for (item, s) in zip(trailing, trailingSizes) {
            item.place(at: CGPoint(x: x, y: barTop + (m.barHeight - s.height) / 2), size: s, ctx)
            x += s.width + m.itemSpacing
        }

        // Centre element: principal item or inline title, centred on the bar if it fits.
        if let center = principal ?? inlineTitle {
            let left = leading.isEmpty ? margin : leadingEnd + m.titleItemGap
            let right = trailing.isEmpty ? size.width - margin : trailingStart - m.titleItemGap
            let half = min(size.width / 2 - left, right - size.width / 2)
            var maxWidth = max(0, half * 2)
            var s = center.sizeThatFits(ProposedViewSize(width: maxWidth, height: m.barHeight))
            var cx = size.width / 2 - s.width / 2
            if s.width > maxWidth || cx < left || cx + s.width > right {
                // Does not fit centred: use the free space between the items.
                maxWidth = max(0, right - left)
                s = center.sizeThatFits(ProposedViewSize(width: maxWidth, height: m.barHeight))
                s.width = min(s.width, maxWidth)
                cx = min(max(left, size.width / 2 - s.width / 2), right - s.width)
            }
            center.place(at: CGPoint(x: cx, y: barTop + (m.barHeight - s.height) / 2), size: s, ctx)
        }

        if let largeTitle {
            let width = size.width - margin * 2
            let s = largeTitle.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let baseline = largeTitle.explicitAlignment(VerticalAlignment.firstTextBaseline.key, size: s) ?? s.height
            let baselineY = barTop + m.barHeight + m.largeTitleHeight - m.largeTitleBaselineInset
            largeTitle.place(at: CGPoint(x: margin, y: baselineY - baseline), size: CGSize(width: min(s.width, width), height: s.height), ctx)
        }

        if let search {
            let top = barTop + m.barHeight + (showsLargeTitle ? m.largeTitleHeight : 0) + SearchFieldMetrics.topGap
            search.place(at: CGPoint(x: margin, y: top), size: CGSize(width: size.width - margin * 2, height: SearchFieldMetrics.height), ctx)
        }
        placeBottomBar(size: size, margin: margin, ctx)
    }

    private func placeBottomBar(size: CGSize, margin: CGFloat, _ ctx: PlaceContext) {
        guard let barY = bottomBarTop else { return }
        let h = NavigationBarMetrics.bottomBarHeight
        if let bottomItems {
            let width = size.width - margin * 2
            let s = bottomItems.sizeThatFits(ProposedViewSize(width: width, height: h))
            bottomItems.place(at: CGPoint(x: margin, y: barY + (h - s.height) / 2), size: CGSize(width: width, height: s.height), ctx)
        }
        if let statusItem {
            let s = statusItem.sizeThatFits(ProposedViewSize(width: size.width / 2, height: h))
            statusItem.place(at: CGPoint(x: (size.width - s.width) / 2, y: barY + (h - s.height) / 2), size: s, ctx)
        }
        bottomBackgroundBottom = ctx.container.maxY - ctx.origin.y
        switch bottomBackgroundVisibility {
        case .visible: showsBottomBackground = true
        case .hidden: showsBottomBackground = false
        case .automatic:
            showsBottomBackground = contentExtendsBelow(content, y: ctx.origin.y + barY, container: ctx.container)
        }
    }

    override func drawContent(_ p: Painter) {
        if glass != nil {
            drawGlass(p)
            return
        }
        content.draw(p)
        if barVisible, let barBackground {
            let rect = CGRect(x: backgroundX, y: backgroundTop, width: backgroundWidth, height: barRegionBottom - backgroundTop)
            p.fill(Path(rect), with: barBackground, in: rect)
            let line = CGRect(x: backgroundX, y: barRegionBottom, width: backgroundWidth, height: ChromeMetrics.hairline)
            p.fill(Path(line), with: hairline, in: line)
        }
        if let barY = bottomBarTop, showsBottomBackground {
            let rect = CGRect(x: backgroundX, y: barY, width: backgroundWidth, height: bottomBackgroundBottom - barY)
            p.fill(Path(rect), with: bottomBackground, in: rect)
            let line = CGRect(x: backgroundX, y: barY - ChromeMetrics.hairline, width: backgroundWidth, height: ChromeMetrics.hairline)
            p.fill(Path(line), with: hairline, in: line)
        }
        for child in children.dropFirst() { child.draw(p) }
    }
}

// MARK: - Liquid Glass bar (iOS 26 / 27)

extension NavigationStackNode {
    /// Groups a stack's toolbar items onto glass capsules: navigation bar leading and trailing
    /// groups, and the floating bottom bar.
    static func glassItems(_ chrome: NavigationChrome, glass: NavigationGlassMetrics, barAdjust: @escaping (inout EnvironmentValues) -> Void,
                           accent: _Paint, hasBack: Bool, env: EnvironmentValues)
    -> (leading: [Node], trailing: [Node], principal: Node?, status: Node?, bottom: ToolbarGlassRowNode?) {
        let neutral = GlassAppearance.system(.regular, scheme: env.colorScheme, design: env.designLanguage)
        // Prominent glass takes the app's accent color (the bar's own environment made labels monochrome).
        let prominent = GlassAppearance.resolve(Glass.regular.tint(Color.accentColor), in: env)
        var lead: [ToolbarGlassToken] = [], trail: [ToolbarGlassToken] = [], pinned: [ToolbarGlassToken] = [], bottom: [ToolbarGlassToken] = []
        var principal: Node?, status: Node?, hasSecondary = false
        func add(_ token: ToolbarGlassToken, _ placement: ToolbarItemPlacement.Kind) {
            switch placement {
            case .leading: lead.append(token)
            case .trailing, .confirmation: trail.append(token)
            case .pinnedTrailing: pinned.append(token)
            case .bottom: bottom.append(token)
            default: break
            }
        }
        for entry in chrome.toolbarItems {
            if let sizing = entry.spacer { add(.spacer(flexible: sizing == .flexible), entry.placement); continue }
            if entry.isSearchSlot { if entry.placement == .bottom { bottom.append(.searchSlot) }; continue }
            let shares = entry.sharedBackground != .hidden
            switch entry.placement {
            case .leading, .trailing, .pinnedTrailing, .bottom:
                for node in entry.resolve(barAdjust) { add(.item(node, prominent: false, sharesBackground: shares), entry.placement) }
            case .confirmation:
                let nodes = entry.resolve { e in
                    barAdjust(&e)
                    e.font = glass.prominentItemFont
                    e.accentColor = Color.white
                }
                for node in nodes { add(.item(node, prominent: true, sharesBackground: shares), .confirmation) }
            case .principal:
                let nodes = entry.resolve(barAdjust)
                principal = principal ?? (nodes.count == 1 ? nodes.first : StackNode(axis: .horizontal, alignment: .center, spacing: nil, children: nodes))
            case .status:
                let nodes = entry.resolve(barAdjust)
                status = status ?? (nodes.count == 1 ? nodes.first : StackNode(axis: .horizontal, alignment: .center, spacing: nil, children: nodes))
            case .secondary: hasSecondary = true
            case .hidden: break
            }
        }
        if hasSecondary { trail.append(.item(EllipsisCircleNode(color: accent, onGlass: true), prominent: false, sharesBackground: true)) }

        func groups(_ tokens: [ToolbarGlassToken]) -> [Node] {
            makeToolbarGlassSlots(tokens, height: glass.itemHeight, metrics: glass, neutral: neutral, prominent: prominent)
                .compactMap { if case .group(let g) = $0 { return g } else { return nil } }
        }
        var leading: [Node] = []
        if hasBack {
            // The back button: its own glass circle with a chevron, no title.
            leading.append(ToolbarGlassGroupNode(items: [BackButtonNode(title: nil, color: accent, glass: glass)], kinds: [.icon],
                                                 appearance: neutral, height: glass.itemHeight, metrics: glass))
        }
        leading += groups(lead)
        let trailing = groups(trail) + groups(pinned)
        var row: ToolbarGlassRowNode?
        if !bottom.isEmpty || chrome.search != nil {
            let slots = makeToolbarGlassSlots(bottom, height: glass.bottomBarHeight, metrics: glass, neutral: neutral, prominent: prominent)
            row = ToolbarGlassRowNode(slots: slots, metrics: glass)
        }
        return (leading, trailing, principal, status, row)
    }

    fileprivate func layoutGlass(_ g: NavigationGlassMetrics, size: CGSize, _ ctx: PlaceContext) {
        let margin = ChromeMetrics.layoutMargin(forWidth: ctx.container.width)
        let itemMargin = _currentConfiguration().device.idiom == .pad ? margin : g.horizontalMargin
        barTop = max(0, ctx.safeRect.minY - ctx.origin.y)
        backgroundTop = ctx.container.minY - ctx.origin.y
        backgroundX = ctx.container.minX - ctx.origin.x
        backgroundWidth = ctx.container.width
        bottomBackgroundBottom = ctx.container.maxY - ctx.origin.y

        // Where the search field goes: the bottom bar on iPhone, unless a tab bar is already there.
        let barBelow = tabBarHostsContent || NavigationGlass.barBelow(ctx)
        var searchStyle: GlassSearchStyle?
        if let search {
            if searchPrefersBottom && !barBelow {
                searchStyle = search.configuration.toolbarBehavior == .minimize ? .minimized : .bottom
            } else {
                searchStyle = .drawer
            }
            search.glassStyle = searchStyle
        }

        let largeTitleRegion = NavigationBarMetrics.largeTitleHeight + (subtitle != nil && showsLargeTitle ? g.largeSubtitleHeight : 0)
        var y = barTop
        if barVisible {
            y += g.barHeight
            if showsLargeTitle { y += largeTitleRegion }
            if searchStyle == .drawer { y += g.drawerSearchRegion }
        }
        barRegionBottom = y

        // Floating bottom bar.
        let safeBottom = min(size.height, ctx.safeRect.maxY - ctx.origin.y)
        var contentBottom = safeBottom
        let row = bottomItems as? ToolbarGlassRowNode
        row?.searchActive = searchStyle == .bottom || searchStyle == .minimized
        row?.searchWidth = searchStyle == .minimized ? NavigationGlassMetrics.search.bottomHeight : nil
        if (row.map { !$0.isEmpty } ?? false) || statusItem != nil {
            let barBottom: CGFloat
            if barBelow {
                barBottom = safeBottom - g.bottomBarBottomInsetNoIndicator
            } else {
                let screenBottom = min(size.height, ctx.container.maxY - ctx.origin.y)
                let indicator = _currentConfiguration().device.safeArea.bottom > 0 && ctx.container.maxY - ctx.safeRect.maxY > 0.5
                barBottom = screenBottom - (indicator ? g.bottomBarBottomInset : g.bottomBarBottomInsetNoIndicator)
            }
            bottomBarTop = barBottom - g.bottomBarHeight
            contentBottom = min(safeBottom, barBottom - g.bottomBarHeight)
        } else {
            bottomBarTop = nil
        }

        let contentRect = CGRect(x: 0, y: barRegionBottom, width: size.width, height: max(0, contentBottom - barRegionBottom))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + contentRect.minY, width: ctx.safeRect.width, height: contentRect.height)
        let c = content.sizeThatFits(ProposedViewSize(contentRect.size))
        content.place(at: CGPoint(x: contentRect.midX - c.width / 2, y: contentRect.midY - c.height / 2), size: c, inner)

        if barVisible { placeGlassBar(g, size: size, margin: margin, itemMargin: itemMargin, largeTitleRegion: largeTitleRegion, ctx) }

        if let barY = bottomBarTop {
            let side = g.bottomBarSideInset
            if let row, !row.isEmpty {
                row.place(at: CGPoint(x: side, y: barY), size: CGSize(width: size.width - side * 2, height: g.bottomBarHeight), ctx)
                if let f = row.searchFrame, let search {
                    search.place(at: CGPoint(x: side + f.minX, y: barY + f.minY), size: f.size, ctx)
                }
            }
            if let statusItem {
                let s = statusItem.sizeThatFits(ProposedViewSize(width: size.width / 2, height: g.bottomBarHeight))
                statusItem.place(at: CGPoint(x: (size.width - s.width) / 2, y: barY + (g.bottomBarHeight - s.height) / 2), size: s, ctx)
            }
            showsBottomEdge = !bottomEdgeHidden
                && NavigationGlass.contentOverlaps(content, minY: ctx.origin.y + barY, maxY: ctx.container.maxY, container: ctx.container)
        } else {
            showsBottomEdge = false
        }
        showsTopEdge = barVisible && barBackground == nil && !topEdgeHidden
            && NavigationGlass.contentOverlaps(content, minY: ctx.container.minY, maxY: ctx.origin.y + barRegionBottom, container: ctx.container)
    }

    private func placeGlassBar(_ g: NavigationGlassMetrics, size: CGSize, margin: CGFloat, itemMargin: CGFloat,
                               largeTitleRegion: CGFloat, _ ctx: PlaceContext) {
        let h = g.barHeight
        // Leading groups from the leading edge, trailing groups from the trailing edge.
        var x = itemMargin
        var leadingEnd = itemMargin
        for group in leading {
            let s = group.sizeThatFits(.unspecified)
            group.place(at: CGPoint(x: x, y: barTop + (h - s.height) / 2), size: s, ctx)
            leadingEnd = x + s.width
            x = leadingEnd + g.groupSpacing
        }
        let sizes = trailing.map { $0.sizeThatFits(.unspecified) }
        let total = sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, trailing.count - 1)) * g.groupSpacing
        x = size.width - itemMargin - total
        let trailingStart = trailing.isEmpty ? size.width - itemMargin : x
        for (group, s) in zip(trailing, sizes) {
            group.place(at: CGPoint(x: x, y: barTop + (h - s.height) / 2), size: s, ctx)
            x += s.width + g.groupSpacing
        }

        // Centre: principal item, or the inline title (with its subtitle under it).
        let left = leading.isEmpty ? margin : leadingEnd + g.titleItemGap
        let right = trailing.isEmpty ? size.width - margin : trailingStart - g.titleItemGap
        func centred(_ node: Node) -> (x: CGFloat, size: CGSize) {
            let half = min(size.width / 2 - left, right - size.width / 2)
            var maxWidth = max(0, half * 2)
            var s = node.sizeThatFits(ProposedViewSize(width: maxWidth, height: h))
            var cx = size.width / 2 - s.width / 2
            if s.width > maxWidth || cx < left || cx + s.width > right {
                maxWidth = max(0, right - left)
                s = node.sizeThatFits(ProposedViewSize(width: maxWidth, height: h))
                s.width = min(s.width, maxWidth)
                cx = min(max(left, size.width / 2 - s.width / 2), right - s.width)
            }
            return (cx, s)
        }
        if let principal {
            let (cx, s) = centred(principal)
            principal.place(at: CGPoint(x: cx, y: barTop + (h - s.height) / 2), size: s, ctx)
        } else if let inlineTitle {
            let t = centred(inlineTitle)
            if let subtitle {
                let st = centred(subtitle)
                let stack = t.size.height + g.inlineSubtitleSpacing + st.size.height
                let top = barTop + (h - stack) / 2
                inlineTitle.place(at: CGPoint(x: t.x, y: top), size: t.size, ctx)
                subtitle.place(at: CGPoint(x: st.x, y: top + t.size.height + g.inlineSubtitleSpacing), size: st.size, ctx)
            } else {
                inlineTitle.place(at: CGPoint(x: t.x, y: barTop + (h - t.size.height) / 2), size: t.size, ctx)
            }
        }

        let m = NavigationBarMetrics.self
        if let largeTitle {
            let width = size.width - margin * 2
            let s = largeTitle.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let baseline = largeTitle.explicitAlignment(VerticalAlignment.firstTextBaseline.key, size: s) ?? s.height
            let baselineY = barTop + h + m.largeTitleHeight - m.largeTitleBaselineInset
            largeTitle.place(at: CGPoint(x: margin, y: baselineY - baseline), size: CGSize(width: min(s.width, width), height: s.height), ctx)
            if let subtitle {
                let ss = subtitle.sizeThatFits(ProposedViewSize(width: width, height: nil))
                subtitle.place(at: CGPoint(x: margin, y: barTop + h + m.largeTitleHeight), size: CGSize(width: min(ss.width, width), height: ss.height), ctx)
            }
        }

        if let search, search.glassStyle == .drawer {
            let top = barTop + h + (showsLargeTitle ? largeTitleRegion : 0) + g.drawerSearchTopGap
            search.place(at: CGPoint(x: itemMargin, y: top),
                         size: CGSize(width: size.width - itemMargin * 2, height: NavigationGlassMetrics.search.drawerHeight), ctx)
        }
    }

    fileprivate func drawGlass(_ p: Painter) {
        guard let g = glass else { return }
        content.draw(p)
        if barVisible, let barBackground {
            // `toolbarBackground(.visible)`: the bar keeps its background.
            let rect = CGRect(x: backgroundX, y: backgroundTop, width: backgroundWidth, height: barRegionBottom - backgroundTop)
            p.fill(Path(rect), with: barBackground, in: rect)
            let line = CGRect(x: backgroundX, y: barRegionBottom, width: backgroundWidth, height: ChromeMetrics.hairline)
            p.fill(Path(line), with: hairline, in: line)
        } else if showsTopEdge {
            if topEdgeHard {
                let rect = CGRect(x: backgroundX, y: backgroundTop, width: backgroundWidth, height: barRegionBottom - backgroundTop)
                p.fill(Path(rect), with: edgeMaterial, in: rect)
                let line = CGRect(x: backgroundX, y: barRegionBottom, width: backgroundWidth, height: ChromeMetrics.hairline)
                p.fill(Path(line), with: hairline, in: line)
            } else {
                let rect = CGRect(x: backgroundX, y: backgroundTop, width: backgroundWidth, height: barRegionBottom + g.softEdgeFade - backgroundTop)
                p.fillSoftScrollEdge(rect, edge: .top, solidFraction: (barRegionBottom - g.softEdgeFade - backgroundTop) / rect.height,
                                     tint: edgeTint, blurRadius: g.softEdgeBlurRadius)
            }
        }
        if let barY = bottomBarTop, showsBottomEdge {
            if bottomEdgeHard {
                let top = barY - g.drawerSearchBottomGap
                let rect = CGRect(x: backgroundX, y: top, width: backgroundWidth, height: bottomBackgroundBottom - top)
                p.fill(Path(rect), with: edgeMaterial, in: rect)
                let line = CGRect(x: backgroundX, y: top - ChromeMetrics.hairline, width: backgroundWidth, height: ChromeMetrics.hairline)
                p.fill(Path(line), with: hairline, in: line)
            } else {
                let top = barY - g.softEdgeFade
                let rect = CGRect(x: backgroundX, y: top, width: backgroundWidth, height: bottomBackgroundBottom - top)
                p.fillSoftScrollEdge(rect, edge: .bottom, solidFraction: (bottomBackgroundBottom - barY - g.softEdgeFade) / rect.height,
                                     tint: edgeTint, blurRadius: g.softEdgeBlurRadius)
            }
        }
        for child in children.dropFirst() { child.draw(p) }
    }
}

// MARK: - Title modifiers

extension View {
    func setNavigationTitle(_ text: Text, mode: NavigationBarItem.TitleDisplayMode? = nil) -> some View {
        navigationChrome { chrome, ctx in
            let env = ctx.env
            chrome.title = NavigationTitle(plain: text.plainString) { adjust in
                var e = env
                adjust(&e)
                return text.makeNode(e)
            }
            if let mode { chrome.titleDisplayMode = mode }
        }
    }

    public func navigationTitle(_ title: Text) -> some View { setNavigationTitle(title) }
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { setNavigationTitle(Text(titleKey)) }
    @_disfavoredOverload
    public func navigationTitle<S: StringProtocol>(_ title: S) -> some View { setNavigationTitle(Text(title)) }
    public func navigationTitle(_ title: Binding<String>) -> some View { setNavigationTitle(Text(verbatim: title.wrappedValue)) }
    public func navigationTitle<V: View>(@ViewBuilder _ title: () -> V) -> some View {
        let view = title()
        return navigationChrome { chrome, ctx in
            let ctx = ctx.child("navigationTitle")
            var probe: [Node] = []
            resolveView(view, ctx, into: &probe)
            let plain = (probe.first?.firstDescendant(TextNode.self)?.runs.map(\.text).joined()) ?? " "
            chrome.title = NavigationTitle(plain: plain.isEmpty ? " " : plain) { adjust in resolveSingle(view, ctx.with(adjust)) }
        }
    }

    /// iOS 26: a secondary line under the title. Liquid Glass bars show it; the iOS 18 bar has no subtitle.
    public func navigationSubtitle(_ subtitle: Text) -> some View {
        navigationChrome { chrome, ctx in
            let env = ctx.env
            chrome.subtitle = NavigationTitle(plain: subtitle.plainString) { adjust in
                var e = env
                adjust(&e)
                return subtitle.makeNode(e)
            }
        }
    }
    public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { navigationSubtitle(Text(subtitleKey)) }
    @_disfavoredOverload
    public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View { navigationSubtitle(Text(subtitle)) }

    @available(*, deprecated, renamed: "navigationTitle(_:)")
    public func navigationBarTitle(_ title: Text) -> some View { setNavigationTitle(title) }
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    public func navigationBarTitle(_ titleKey: LocalizedStringKey) -> some View { setNavigationTitle(Text(titleKey)) }
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    @_disfavoredOverload
    public func navigationBarTitle<S: StringProtocol>(_ title: S) -> some View { setNavigationTitle(Text(title)) }
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    public func navigationBarTitle(_ title: Text, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        setNavigationTitle(title, mode: displayMode)
    }
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    public func navigationBarTitle(_ titleKey: LocalizedStringKey, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        setNavigationTitle(Text(titleKey), mode: displayMode)
    }
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    @_disfavoredOverload
    public func navigationBarTitle<S: StringProtocol>(_ title: S, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        setNavigationTitle(Text(title), mode: displayMode)
    }

    public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationChrome { chrome, _ in chrome.titleDisplayMode = displayMode }
    }
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        navigationChrome { chrome, _ in chrome.backButtonHidden = hidesBackButton }
    }
    @available(*, deprecated, message: "Use toolbar(.hidden)")
    public func navigationBarHidden(_ hidden: Bool) -> some View {
        navigationChrome { chrome, _ in chrome.bars[.navigationBar, default: .init()].visibility = hidden ? .hidden : .visible }
    }

    @available(*, deprecated, message: "Use toolbar(_:) with navigationBarLeading or navigationBarTrailing placement")
    public func navigationBarItems<L: View, T: View>(leading: L, trailing: T) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leading }
            ToolbarItem(placement: .navigationBarTrailing) { trailing }
        }
    }
    @available(*, deprecated, message: "Use toolbar(_:) with navigationBarLeading placement")
    public func navigationBarItems<L: View>(leading: L) -> some View {
        toolbar { ToolbarItem(placement: .navigationBarLeading) { leading } }
    }
    @available(*, deprecated, message: "Use toolbar(_:) with navigationBarTrailing placement")
    public func navigationBarItems<T: View>(trailing: T) -> some View {
        toolbar { ToolbarItem(placement: .navigationBarTrailing) { trailing } }
    }

    // MARK: Destinations

    public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        navigationChrome { chrome, _ in
            chrome.destinations[ObjectIdentifier(D.self)] = { value in (value.base as? D).map { AnyView(destination($0)) } }
        }
    }
    public func navigationDestination<V: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> V) -> some View {
        let shown = isPresented.wrappedValue
        let view = AnyView(destination())
        return navigationChrome { chrome, _ in if shown { chrome.presented.append(view) } }
    }
    public func navigationDestination<D: Hashable, C: View>(item: Binding<D?>, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        let item = item.wrappedValue
        return navigationChrome { chrome, _ in if let item { chrome.presented.append(AnyView(destination(item))) } }
    }

    public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View { self }
    public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View { self }
    public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View { self }
    @available(*, deprecated)
    public func navigationViewStyle<S: NavigationViewStyle>(_ style: S) -> some View { self }
}
