// List and Form styles, the environment they read, and the per-row modifiers (traits) a List
// consumes when it lays out its rows.

// MARK: - Styles

/// The concrete look a List is drawn with.
enum ListStyleKind: Hashable {
    case insetGrouped, grouped, plain, inset

    var hasCards: Bool { self == .insetGrouped || self == .grouped }
    var isGroupedFamily: Bool { self == .insetGrouped || self == .grouped }
}

public protocol ListStyle {}
extension ListStyle {
    /// nil means "automatic" (inset grouped on iPhone).
    var _kind: ListStyleKind? {
        switch self {
        case is InsetGroupedListStyle, is SidebarListStyle: return .insetGrouped
        case is GroupedListStyle: return .grouped
        case is PlainListStyle: return .plain
        case is InsetListStyle: return .inset
        default: return nil
        }
    }
}

public struct DefaultListStyle: ListStyle { public init() {} }
public struct InsetGroupedListStyle: ListStyle { public init() {} }
public struct GroupedListStyle: ListStyle { public init() {} }
public struct PlainListStyle: ListStyle { public init() {} }
public struct InsetListStyle: ListStyle { public init() {} }
public struct SidebarListStyle: ListStyle { public init() {} }

extension ListStyle where Self == DefaultListStyle { public static var automatic: DefaultListStyle { DefaultListStyle() } }
extension ListStyle where Self == InsetGroupedListStyle { public static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() } }
extension ListStyle where Self == GroupedListStyle { public static var grouped: GroupedListStyle { GroupedListStyle() } }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { PlainListStyle() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { InsetListStyle() } }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { SidebarListStyle() } }

public protocol FormStyle {}
public struct AutomaticFormStyle: FormStyle { public init() {} }
public struct GroupedFormStyle: FormStyle { public init() {} }
public struct ColumnsFormStyle: FormStyle { public init() {} }
extension FormStyle where Self == AutomaticFormStyle { public static var automatic: AutomaticFormStyle { AutomaticFormStyle() } }
extension FormStyle where Self == GroupedFormStyle { public static var grouped: GroupedFormStyle { GroupedFormStyle() } }
extension FormStyle where Self == ColumnsFormStyle { public static var columns: ColumnsFormStyle { ColumnsFormStyle() } }

public enum Prominence: Hashable, Sendable { case standard, increased }

public struct ListSectionSpacing: Sendable {
    let value: CGFloat?
    public static let `default` = ListSectionSpacing(value: nil)
    public static let compact = ListSectionSpacing(value: ListMetrics.compactSectionSpacing)
    public static func custom(_ spacing: CGFloat) -> ListSectionSpacing { ListSectionSpacing(value: spacing) }
}

public struct ListItemTint: Sendable {
    let color: Color?
    public static func fixed(_ tint: Color) -> ListItemTint { ListItemTint(color: tint) }
    public static func preferred(_ tint: Color) -> ListItemTint { ListItemTint(color: tint) }
    public static let monochrome = ListItemTint(color: nil)
}

// MARK: - Environment

enum ListStyleKey: EnvironmentKey { static let defaultValue: ListStyleKind? = nil }
enum ListContentStyleKey: EnvironmentKey { static let defaultValue: ListStyleKind? = nil }
enum DefaultMinListRowHeightKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
enum DefaultMinListHeaderHeightKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
enum HeaderProminenceKey: EnvironmentKey { static let defaultValue = Prominence.standard }
enum ListRowSpacingKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
enum ListSectionSpacingKey: EnvironmentKey { static let defaultValue = ListSectionSpacing.default }
enum ElevatedPresentationKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Style set with `.listStyle` (nil = automatic).
    var listStyleKind: ListStyleKind? {
        get { self[ListStyleKey.self] }
        set { self[ListStyleKey.self] = newValue }
    }
    /// Set by a List for its own content: lets a Section style its header for the enclosing list.
    var listContentStyle: ListStyleKind? {
        get { self[ListContentStyleKey.self] }
        set { self[ListContentStyleKey.self] = newValue }
    }
    public var defaultMinListRowHeight: CGFloat {
        get { self[DefaultMinListRowHeightKey.self] ?? ListMetrics.forDesign(designLanguage).minRowHeight }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }
    /// The minimum row height set with `.environment(\.defaultMinListRowHeight, ...)`, if any.
    var explicitMinListRowHeight: CGFloat? { self[DefaultMinListRowHeightKey.self] }
    public var defaultMinListHeaderHeight: CGFloat? {
        get { self[DefaultMinListHeaderHeightKey.self] }
        set { self[DefaultMinListHeaderHeightKey.self] = newValue }
    }
    public var headerProminence: Prominence {
        get { self[HeaderProminenceKey.self] }
        set { self[HeaderProminenceKey.self] = newValue }
    }
    var listRowSpacing: CGFloat? {
        get { self[ListRowSpacingKey.self] }
        set { self[ListRowSpacingKey.self] = newValue }
    }
    var listSectionSpacing: ListSectionSpacing {
        get { self[ListSectionSpacingKey.self] }
        set { self[ListSectionSpacingKey.self] = newValue }
    }
    /// True inside a sheet/popover: iOS then uses the "elevated" dark backgrounds.
    var isElevatedPresentation: Bool {
        get { self[ElevatedPresentationKey.self] }
        set { self[ElevatedPresentationKey.self] = newValue }
    }
}

// MARK: - Row traits (read by the List)

enum ListRowInsetsTraitKey: TraitKey { typealias Value = EdgeInsets }
enum ListRowBackgroundTraitKey: TraitKey { typealias Value = Node }
enum ListRowPartialInsetsTraitKey: TraitKey { typealias Value = PartialRowInsets }

/// Per-edge row insets from `.listRowInsets(_:_:)`; nil edges keep the default.
struct PartialRowInsets {
    var top: CGFloat?, leading: CGFloat?, bottom: CGFloat?, trailing: CGFloat?
}
enum ListRowSeparatorTraitKey: TraitKey { typealias Value = SeparatorSetting }
enum ListRowSeparatorTintTraitKey: TraitKey { typealias Value = TintSetting }
enum ListSectionSeparatorTraitKey: TraitKey { typealias Value = SeparatorSetting }
enum ListSectionSeparatorTintTraitKey: TraitKey { typealias Value = TintSetting }

struct SeparatorSetting {
    var visibility: Visibility
    var edges: VerticalEdge.Set
    func hides(_ edge: VerticalEdge.Set) -> Bool { visibility == .hidden && edges.contains(edge) }
}
struct TintSetting {
    var color: RGBA
    var edges: VerticalEdge.Set
}

/// Resolves a view per row and stores the resulting node as a trait.
struct ListRowBackgroundModifier<Background: View>: ViewModifier, PrimitiveModifier {
    let background: Background?
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, node) in content.nodes(ctx).enumerated() {
            if let background {
                let bgCtx = ctx.child("listRowBackground\(i)").with { $0.stackAxis = nil; $0.isInListRow = false }
                node.traits[ListRowBackgroundTraitKey.self] = resolveSingle(background, bgCtx)
            }
            out.append(node)
        }
    }
}

extension View {
    public func listStyle<S: ListStyle>(_ style: S) -> some View { env { $0.listStyleKind = style._kind } }
    public func formStyle<S: FormStyle>(_ style: S) -> some View { self }

    public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        modifier(PrimitiveTraitModifier { node in node.traits[ListRowInsetsTraitKey.self] = insets })
    }
    /// Sets the inset of the given edges only; the other edges keep the style's default.
    public func listRowInsets(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View {
        modifier(PrimitiveTraitModifier { node in
            var partial = node.traits[ListRowPartialInsetsTraitKey.self] ?? PartialRowInsets()
            if edges.contains(.top) { partial.top = length }
            if edges.contains(.leading) { partial.leading = length }
            if edges.contains(.bottom) { partial.bottom = length }
            if edges.contains(.trailing) { partial.trailing = length }
            node.traits[ListRowPartialInsetsTraitKey.self] = partial
        })
    }
    /// Section margins have no effect on a static frame at the default geometry.
    public func listSectionMargins(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View { self }
    public func sectionIndexLabel(_ label: Text?) -> some View { self }
    public func listSectionIndexVisibility(_ visibility: Visibility) -> some View { self }
    public func listRowBackground<V: View>(_ view: V?) -> some View { modifier(ListRowBackgroundModifier(background: view)) }
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        trait(ListRowSeparatorTraitKey.self, SeparatorSetting(visibility: visibility, edges: edges))
    }
    public func listRowSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        modifier(EnvReadingTraitModifier { node, env in
            node.traits[ListRowSeparatorTintTraitKey.self] = color.map { TintSetting(color: $0.rgba(in: env), edges: edges) }
        })
    }
    public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        trait(ListSectionSeparatorTraitKey.self, SeparatorSetting(visibility: visibility, edges: edges))
    }
    public func listSectionSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        modifier(EnvReadingTraitModifier { node, env in
            node.traits[ListSectionSeparatorTintTraitKey.self] = color.map { TintSetting(color: $0.rgba(in: env), edges: edges) }
        })
    }
    public func listRowSpacing(_ spacing: CGFloat?) -> some View { env { $0.listRowSpacing = spacing } }
    public func listSectionSpacing(_ spacing: ListSectionSpacing) -> some View { env { $0.listSectionSpacing = spacing } }
    public func listSectionSpacing(_ spacing: CGFloat) -> some View { env { $0.listSectionSpacing = .custom(spacing) } }
    public func listItemTint(_ tint: ListItemTint?) -> some View { self }
    public func listItemTint(_ tint: Color?) -> some View { self }
    public func headerProminence(_ prominence: Prominence) -> some View { env { $0.headerProminence = prominence } }
    public func badgeProminence(_ prominence: BadgeProminence) -> some View { self }

    public func moveDisabled(_ isDisabled: Bool) -> some View { self }
    public func deleteDisabled(_ isDisabled: Bool) -> some View { self }
    public func selectionDisabled(_ isDisabled: Bool = true) -> some View { self }
}

public struct BadgeProminence: Hashable, Sendable {
    let level: Int
    public static let decreased = BadgeProminence(level: 0)
    public static let standard = BadgeProminence(level: 1)
    public static let increased = BadgeProminence(level: 2)
}

/// Mutates each resolved node (no extra node).
struct PrimitiveTraitModifier: ViewModifier, PrimitiveModifier {
    let apply: @MainActor (Node) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) { apply(node); out.append(node) }
    }
}

struct EnvReadingTraitModifier: ViewModifier, PrimitiveModifier {
    let apply: @MainActor (Node, EnvironmentValues) -> Void
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for node in content.nodes(ctx) { apply(node, ctx.env); out.append(node) }
    }
}

// MARK: - ForEach editing (inert in a static frame)

public protocol DynamicViewContent: View {
    associatedtype Data: Collection
    var data: Data { get }
}

extension ForEach: DynamicViewContent where Content: View {}

extension DynamicViewContent {
    public func onDelete(perform action: Optional<(IndexSet) -> Void>) -> some DynamicViewContent { self }
    public func onMove(perform action: Optional<(IndexSet, Int) -> Void>) -> some DynamicViewContent { self }
}

/// The "Edit" button of a list's toolbar.
public struct EditButton: View {
    private let _tvOSCheck = tvOSUnavailable("EditButton")
    public init() {}
    public var body: some View { Text("Edit").foregroundStyle(.tint) }
}
