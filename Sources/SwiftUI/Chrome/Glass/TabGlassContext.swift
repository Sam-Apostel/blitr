// Contracts between the tab bar and the views it hosts.

enum HasEnclosingTabBarKey: EnvironmentKey { static let defaultValue = false }
enum TabViewBottomAccessoryKey: EnvironmentKey { static let defaultValue: NodeResolver? = nil }

extension EnvironmentValues {
    /// True while resolving the content of a tab in a `TabView` that shows a tab bar (any style but
    /// `.page`). Bottom-placed chrome such as the iOS 26 bottom search field reads it: with a tab bar the
    /// search field belongs to the tab bar instead. (A tab that hides the bar with
    /// `.toolbar(.hidden, for: .tabBar)` still sees `true`: that is only known after its content resolves.)
    var hasEnclosingTabBar: Bool {
        get { self[HasEnclosingTabBarKey.self] }
        set { self[HasEnclosingTabBarKey.self] = newValue }
    }
    /// `.tabViewBottomAccessory { ... }` waiting for the TabView it was applied to.
    var tabViewBottomAccessory: NodeResolver? {
        get { self[TabViewBottomAccessoryKey.self] }
        set { self[TabViewBottomAccessoryKey.self] = newValue }
    }
}

/// Where the bottom accessory is shown (iOS 26). A still frame always shows it expanded above the bar.
public enum TabViewBottomAccessoryPlacement: Hashable, Sendable { case inline, expanded }

enum TabViewBottomAccessoryPlacementKey: EnvironmentKey { static let defaultValue: TabViewBottomAccessoryPlacement? = nil }

extension EnvironmentValues {
    public var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement? {
        get { self[TabViewBottomAccessoryPlacementKey.self] }
        set { self[TabViewBottomAccessoryPlacementKey.self] = newValue }
    }
}

extension View {
    public func tabViewBottomAccessory<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let accessory = content()
        return env { $0.tabViewBottomAccessory = nodeResolver(accessory) }
    }
    public func tabViewBottomAccessory<Content: View>(isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        let accessory = content()
        return env { $0.tabViewBottomAccessory = isEnabled ? nodeResolver(accessory) : nil }
    }
}
