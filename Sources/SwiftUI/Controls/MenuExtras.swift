// Menu initialisers with a primary action, menu indicator and order, and the deprecated ContextMenu.
// A menu is always drawn closed: its label, plus the indicator when one is asked for.

extension Menu where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { Text(titleKey) }, primaryAction: primaryAction)
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { Text(title) }, primaryAction: primaryAction)
    }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content,
                primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { SwiftUI.Label(titleKey, systemImage: systemImage) }, primaryAction: primaryAction)
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content,
                                   primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { SwiftUI.Label(title, systemImage: systemImage) }, primaryAction: primaryAction)
    }
}

// MARK: - Indicator

enum MenuIndicatorKey: EnvironmentKey { static let defaultValue = Visibility.automatic }
extension EnvironmentValues {
    var menuIndicatorVisibility: Visibility {
        get { self[MenuIndicatorKey.self] }
        set { self[MenuIndicatorKey.self] = newValue }
    }
}

extension View {
    /// `.hidden` removes the chevrons of a menu picker; `.visible` adds the indicator to a menu's label.
    /// Automatic is the platform default: shown on menu pickers, not on menus.
    public func menuIndicator(_ visibility: Visibility) -> some View {
        env { $0.menuIndicatorVisibility = visibility }
    }
}

/// The label of a closed menu, with the indicator after it when `.menuIndicator(.visible)` is set.
struct _MenuLabel<Label: View>: View, PrimitiveView {
    typealias Body = Never
    let label: Label
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        guard ctx.env.menuIndicatorVisibility == .visible else { return resolveView(label, ctx, into: &out) }
        let view = HStack(spacing: 5) {
            label
            UpDownChevron()
        }
        resolveView(view, ctx.child("indicator"), into: &out)
    }
}

// MARK: - Order and dismissal (only matter while a menu is open)

public struct MenuOrder: Equatable, Hashable, Sendable {
    let raw: Int
    public static let automatic = MenuOrder(raw: 0)
    public static let priority = MenuOrder(raw: 1)
    public static let fixed = MenuOrder(raw: 2)
}

public struct MenuActionDismissBehavior: Equatable {
    let raw: Int
    public static let automatic = MenuActionDismissBehavior(raw: 0)
    public static let enabled = MenuActionDismissBehavior(raw: 1)
    public static let disabled = MenuActionDismissBehavior(raw: 2)
}

enum MenuOrderKey: EnvironmentKey { static let defaultValue = MenuOrder.automatic }
extension EnvironmentValues {
    public var menuOrder: MenuOrder {
        get { self[MenuOrderKey.self] }
        set { self[MenuOrderKey.self] = newValue }
    }
}

extension View {
    public func menuOrder(_ order: MenuOrder) -> some View { env { $0.menuOrder = order } }
    public func menuActionDismissBehavior(_ behavior: MenuActionDismissBehavior) -> some View { self }
}

// MARK: - ContextMenu

@available(*, deprecated, message: "Use `contextMenu(menuItems:)` instead.")
public struct ContextMenu<MenuItems: View> {
    let menuItems: MenuItems
    public init(@ViewBuilder menuItems: () -> MenuItems) { self.menuItems = menuItems() }
}

extension View {
    /// A context menu only shows while it is open, which a static frame never is.
    @available(*, deprecated, message: "Use `contextMenu(menuItems:)` instead.")
    public func contextMenu<MenuItems: View>(_ contextMenu: ContextMenu<MenuItems>?) -> some View { self }
}
