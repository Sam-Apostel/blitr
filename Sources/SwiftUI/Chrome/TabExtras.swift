// The rest of the iOS 18 Tab API: the Tab initialisers without a label or value, tab content modifiers
// that only matter during interaction or in the sidebar, and TabViewCustomization.
// The sidebar of a sidebar-adaptable tab view is not drawn (an iPad starts on the top tab bar), so its
// header, footer and bottom bar, section expansion and customization have nothing to change on screen.
import Foundation

extension Tab where Value == Never, Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(tag: nil, content: content(), label: EmptyView())
    }
}
extension Tab where Label == EmptyView {
    public init(value: Value, @ViewBuilder content: () -> Content) {
        self.init(tag: AnyHashable(value), content: content(), label: EmptyView())
    }
}
extension Tab where Value == Never {
    public init(role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(tag: nil, content: content(), label: label(), role: role)
    }
}

extension ForEach where Content: TabContent {
    public init<V>(_ data: Data, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content)
    where ID == Data.Element.ID, V == Content.TabValue, Data.Element: Identifiable {
        self.data = data
        self.content = content
        self.idGetter = { $0.id }
    }
}

public struct TabSectionExpansion: Hashable, Sendable {
    let raw: Int
    public static let automatic = TabSectionExpansion(raw: 0)
    public static let expanded = TabSectionExpansion(raw: 1)
    public static let collapsed = TabSectionExpansion(raw: 2)
}

public struct SpringLoadingBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = SpringLoadingBehavior(raw: 0)
    public static let enabled = SpringLoadingBehavior(raw: 1)
    public static let disabled = SpringLoadingBehavior(raw: 2)
}

public struct TabSearchActivation: Hashable, Sendable {
    let raw: Int
    public static let automatic = TabSearchActivation(raw: 0)
    public static let searchTabSelection = TabSearchActivation(raw: 1)
}

extension TabContent {
    public func defaultSectionExpansion(_ expansion: TabSectionExpansion) -> some TabContent<TabValue> { self }
    public func springLoadingBehavior(_ behavior: SpringLoadingBehavior) -> some TabContent<TabValue> { self }
    public func help(_ textKey: LocalizedStringKey) -> some TabContent<TabValue> { self }
    public func help(_ text: Text) -> some TabContent<TabValue> { self }
    @_disfavoredOverload
    public func help<S: StringProtocol>(_ text: S) -> some TabContent<TabValue> { self }
    public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> some TabContent<TabValue> { self }
    public func swipeActions<T: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                                      @ViewBuilder content: () -> T) -> some TabContent<TabValue> { self }
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some TabContent<TabValue> { self }
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void) -> some TabContent<TabValue> { self }
    public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                       arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> Content) -> some TabContent<TabValue> { self }
    public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                           arrowEdge: Edge? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some TabContent<TabValue> { self }

    // Accessibility of the tab bar item. The tab bar's accessibility elements come from the tab's label.
    public func accessibilityIdentifier(_ identifier: String, isEnabled: Bool) -> some TabContent<TabValue> { self }
    public func accessibilityLabel(_ labelKey: LocalizedStringKey, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityLabel(_ label: Text, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    @_disfavoredOverload
    public func accessibilityLabel<S: StringProtocol>(_ label: S, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityHint(_ hintKey: LocalizedStringKey, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityHint(_ hint: Text, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    @_disfavoredOverload
    public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityValue(_ valueKey: LocalizedStringKey, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityValue(_ value: Text, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    @_disfavoredOverload
    public func accessibilityValue<S: StringProtocol>(_ value: S, isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityInputLabels(_ inputLabelKeys: [LocalizedStringKey], isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    public func accessibilityInputLabels(_ inputLabels: [Text], isEnabled: Bool = true) -> some TabContent<TabValue> { self }
    @_disfavoredOverload
    public func accessibilityInputLabels<S: StringProtocol>(_ inputLabels: [S], isEnabled: Bool = true) -> some TabContent<TabValue> { self }
}

extension View {
    public func defaultAdaptableTabBarPlacement(_ defaultPlacement: AdaptableTabBarPlacement = .automatic) -> some View { self }
    public func tabViewSearchActivation(_ activation: TabSearchActivation) -> some View { self }
}

// MARK: - Customization

/// What the person changed in a sidebar-adaptable tab view: tab visibility and section order, by customization id.
public struct TabViewCustomization: Codable, Hashable, Sendable {
    public struct TabCustomization: Codable, Hashable, Sendable {
        var tabBarVisible: Bool?
        var sidebarVisible: Bool?
        public var tabBarVisibility: Visibility { tabBarVisible.map { $0 ? .visible : .hidden } ?? .automatic }
        public var sidebarVisibility: Visibility {
            get { sidebarVisible.map { $0 ? .visible : .hidden } ?? .automatic }
            set { sidebarVisible = newValue == .automatic ? nil : newValue == .visible }
        }
    }
    public struct SectionCustomization: Codable, Hashable, Sendable {
        public var tabOrder: [String]?
        public mutating func resetTabOrder() { tabOrder = nil }
    }

    var tabs: [String: TabCustomization] = [:]
    var sections: [String: SectionCustomization] = [:]

    public init() {}
    public mutating func resetVisibility() { tabs = [:] }
    public mutating func resetSectionOrder() { sections = [:] }
    public mutating func resetSectionOrder(for sectionID: String) { sections[sectionID] = nil }

    public subscript(tab id: String) -> TabCustomization {
        get { tabs[id] ?? TabCustomization() }
        set { tabs[id] = newValue }
    }
    public subscript(section id: String) -> SectionCustomization {
        get { sections[id] ?? SectionCustomization() }
        set { sections[id] = newValue }
    }
    public subscript(sectionID id: String) -> [String]? { sections[id]?.tabOrder }
    public subscript(sidebarVisibility id: String) -> Visibility {
        get { self[tab: id].sidebarVisibility }
        set { self[tab: id].sidebarVisibility = newValue }
    }
    public subscript(tabBarVisibility id: String) -> Visibility { self[tab: id].tabBarVisibility }
}

extension AppStorage where Value == TabViewCustomization {
    public init(wrappedValue: Value = TabViewCustomization(), _ key: String, store: UserDefaults? = nil) {
        self.init(key: key, defaultValue: wrappedValue)
    }
}
