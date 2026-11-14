// macOS scenes and scene modifiers that a render never shows: menu bar extras, utility windows, window
// styles and placement, background tasks, window actions. They are accepted; the first window group's
// content is what is rendered (see App.swift).

// MARK: - Scenes

/// macOS: an item in the menu bar. Not part of a window, so never rendered.
public struct MenuBarExtra<Label: View, Content: View>: Scene {
    public typealias Body = Never
    public init(isInserted: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
}
extension MenuBarExtra where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {}
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
}
extension MenuBarExtra where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {}
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {}
    public init(_ titleKey: LocalizedStringKey, image: String, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {}
    public init(_ titleKey: LocalizedStringKey, image: String, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, @ViewBuilder content: () -> Content) {}
}

/// macOS: a floating utility panel. Never the launch window.
public struct UtilityWindow<Content: View>: Scene {
    public typealias Body = Never
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) {}
}

extension WindowGroup {
    public init<D: Hashable & Codable>(for type: D.Type, @ViewBuilder content: @escaping (Binding<D>) -> Content, defaultValue: @escaping () -> D) {
        self.init(content: { content(.constant(defaultValue())) })
    }
    public init<D: Hashable & Codable>(id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D>) -> Content,
                                       defaultValue: @escaping () -> D) {
        self.init(content: { content(.constant(defaultValue())) })
    }
    public init<D: Hashable & Codable>(_ titleKey: LocalizedStringKey, id: String, for type: D.Type,
                                       @ViewBuilder content: @escaping (Binding<D>) -> Content, defaultValue: @escaping () -> D) {
        self.init(content: { content(.constant(defaultValue())) })
    }
    @_disfavoredOverload
    public init<S: StringProtocol, D: Hashable & Codable>(_ title: S, id: String, for type: D.Type,
                                                          @ViewBuilder content: @escaping (Binding<D>) -> Content, defaultValue: @escaping () -> D) {
        self.init(content: { content(.constant(defaultValue())) })
    }
    public init<D: Hashable & Codable>(_ titleKey: LocalizedStringKey, id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> Content) {
        self.init(content: { content(.constant(nil)) })
    }
    @_disfavoredOverload
    public init<S: StringProtocol, D: Hashable & Codable>(_ title: S, id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> Content) {
        self.init(content: { content(.constant(nil)) })
    }
}

extension CommandGroupPlacement {
    public static let appSettings = CommandGroupPlacement(name: "appSettings")
}

extension FileDocument {
    public typealias ReadConfiguration = FileDocumentReadConfiguration
    public typealias WriteConfiguration = FileDocumentWriteConfiguration
}

// MARK: - Styles

public protocol WindowStyle {}
public struct DefaultWindowStyle: WindowStyle { public init() {} }
public struct HiddenTitleBarWindowStyle: WindowStyle { public init() {} }
public struct PlainWindowStyle: WindowStyle { public init() {} }
public struct TitleBarWindowStyle: WindowStyle { public init(showsTitle: Bool = true) {} }
public struct VolumetricWindowStyle: WindowStyle { public init() {} }
extension WindowStyle where Self == DefaultWindowStyle { public static var automatic: DefaultWindowStyle { .init() } }
extension WindowStyle where Self == HiddenTitleBarWindowStyle { public static var hiddenTitleBar: HiddenTitleBarWindowStyle { .init() } }
extension WindowStyle where Self == PlainWindowStyle { public static var plain: PlainWindowStyle { .init() } }
extension WindowStyle where Self == TitleBarWindowStyle { public static var titleBar: TitleBarWindowStyle { .init() } }
extension WindowStyle where Self == VolumetricWindowStyle { public static var volumetric: VolumetricWindowStyle { .init() } }

public protocol WindowToolbarStyle {}
public struct DefaultWindowToolbarStyle: WindowToolbarStyle { public init() {} }
public struct ExpandedWindowToolbarStyle: WindowToolbarStyle { public init() {} }
public struct UnifiedWindowToolbarStyle: WindowToolbarStyle { public init() {}; public init(showsTitle: Bool) {} }
public struct UnifiedCompactWindowToolbarStyle: WindowToolbarStyle { public init() {}; public init(showsTitle: Bool) {} }
extension WindowToolbarStyle where Self == DefaultWindowToolbarStyle { public static var automatic: DefaultWindowToolbarStyle { .init() } }
extension WindowToolbarStyle where Self == ExpandedWindowToolbarStyle { public static var expanded: ExpandedWindowToolbarStyle { .init() } }
extension WindowToolbarStyle where Self == UnifiedWindowToolbarStyle {
    public static var unified: UnifiedWindowToolbarStyle { .init() }
    public static func unified(showsTitle: Bool) -> UnifiedWindowToolbarStyle { .init(showsTitle: showsTitle) }
}
extension WindowToolbarStyle where Self == UnifiedCompactWindowToolbarStyle {
    public static var unifiedCompact: UnifiedCompactWindowToolbarStyle { .init() }
    public static func unifiedCompact(showsTitle: Bool) -> UnifiedCompactWindowToolbarStyle { .init(showsTitle: showsTitle) }
}

public protocol MenuBarExtraStyle {}
public struct AutomaticMenuBarExtraStyle: MenuBarExtraStyle { public init() {} }
public struct PullDownMenuBarExtraStyle: MenuBarExtraStyle { public init() {} }
public struct WindowMenuBarExtraStyle: MenuBarExtraStyle { public init() {} }
extension MenuBarExtraStyle where Self == AutomaticMenuBarExtraStyle { public static var automatic: AutomaticMenuBarExtraStyle { .init() } }
extension MenuBarExtraStyle where Self == PullDownMenuBarExtraStyle { public static var menu: PullDownMenuBarExtraStyle { .init() } }
extension MenuBarExtraStyle where Self == WindowMenuBarExtraStyle { public static var window: WindowMenuBarExtraStyle { .init() } }

public struct WindowInteractionBehavior: Hashable, Sendable {
    let raw: Int
    public static let automatic = WindowInteractionBehavior(raw: 0)
    public static let enabled = WindowInteractionBehavior(raw: 1)
    public static let disabled = WindowInteractionBehavior(raw: 2)
}

// MARK: - Background tasks

/// Work the system wakes the app for. Never scheduled here.
public struct BackgroundTask<Request, Response>: Sendable {
    let name: String
}
extension BackgroundTask where Request == Void, Response == Void {
    public static func appRefresh(_ identifier: String) -> BackgroundTask<Void, Void> { .init(name: identifier) }
    public static func urlSession(_ identifier: String) -> BackgroundTask<Void, Void> { .init(name: identifier) }
    public static func processingTask(_ identifier: String) -> BackgroundTask<Void, Void> { .init(name: identifier) }
    public static var watchConnectivity: BackgroundTask<Void, Void> { .init(name: "watchConnectivity") }
    public static var bluetoothAlert: BackgroundTask<Void, Void> { .init(name: "bluetoothAlert") }
    public static var snapshot: BackgroundTask<Void, Void> { .init(name: "snapshot") }
    public static var relevantShortcut: BackgroundTask<Void, Void> { .init(name: "relevantShortcut") }
}
extension BackgroundTask where Request == String, Response == Void {
    public static var appRefresh: BackgroundTask<String, Void> { .init(name: "appRefresh") }
    public static var urlSession: BackgroundTask<String, Void> { .init(name: "urlSession") }
    public static func urlSession(matching: @escaping @Sendable (String) -> Bool) -> BackgroundTask<String, Void> { .init(name: "urlSession") }
}

// MARK: - Scene modifiers

extension Scene {
    public func windowStyle<S: WindowStyle>(_ style: S) -> some Scene { self }
    public func windowToolbarStyle<S: WindowToolbarStyle>(_ style: S) -> some Scene { self }
    public func windowToolbarLabelStyle(fixed: ToolbarLabelStyle) -> some Scene { self }
    public func defaultPosition(_ position: UnitPoint) -> some Scene { self }
    public func defaultLaunchBehavior(_ behavior: SceneLaunchBehavior) -> some Scene { self }
    public func restorationBehavior(_ behavior: SceneRestorationBehavior) -> some Scene { self }
    public func windowIdealSize(_ idealSize: WindowIdealSize) -> some Scene { self }
    public func windowManagerRole(_ role: WindowManagerRole) -> some Scene { self }
    public func windowLevel(_ level: WindowLevel) -> some Scene { self }
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some Scene { self }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some Scene { self }
    public func menuBarExtraStyle<S: MenuBarExtraStyle>(_ style: S) -> some Scene { self }
    public func backgroundTask<D: Sendable, R: Sendable>(_ task: BackgroundTask<D, R>, action: @escaping @Sendable (D) async -> R) -> some Scene { self }
    public func defaultWindowPlacement(_ placement: @escaping (WindowLayoutRoot, WindowPlacementContext) -> WindowPlacement) -> some Scene { self }
}

public struct ToolbarLabelStyle: Sendable {
    public static let automatic = ToolbarLabelStyle()
    public static let iconOnly = ToolbarLabelStyle()
    public static let titleOnly = ToolbarLabelStyle()
    public static let titleAndIcon = ToolbarLabelStyle()
}
public struct SceneLaunchBehavior: Sendable {
    public static let automatic = SceneLaunchBehavior()
    public static let presented = SceneLaunchBehavior()
    public static let suppressed = SceneLaunchBehavior()
}
public struct SceneRestorationBehavior: Sendable {
    public static let automatic = SceneRestorationBehavior()
    public static let disabled = SceneRestorationBehavior()
}
public struct WindowIdealSize: Sendable {
    public static let automatic = WindowIdealSize()
    public static let maximum = WindowIdealSize()
    public static func fitToContent() -> WindowIdealSize { WindowIdealSize() }
}
public struct WindowManagerRole: Sendable {
    public static let automatic = WindowManagerRole()
    public static let principal = WindowManagerRole()
    public static let associated = WindowManagerRole()
}
public struct WindowLevel: Sendable {
    public static let automatic = WindowLevel()
    public static let desktop = WindowLevel()
    public static let floating = WindowLevel()
    public static let normal = WindowLevel()
}
public struct WindowPlacement {
    public struct Position: Sendable {
        public static let center = Position()
        public static let leading = Position()
        public static let trailing = Position()
    }
    public init(_ position: Position? = nil, size: CGSize? = nil) {}
    public init(_ position: Position? = nil, width: CGFloat? = nil, height: CGFloat? = nil) {}
    public init(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {}
}
public struct WindowLayoutRoot {
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { .zero }
}
public struct WindowPlacementContext {
    public var windows: [String] { [] }
}

// MARK: - Window actions

/// Opens a window. There is one window here, so the action does nothing (and warns).
@MainActor @preconcurrency
public struct OpenWindowAction {
    public enum SharingBehavior: Sendable { case automatic, required }
    public func callAsFunction(id: String) { warn(id) }
    public func callAsFunction<D: Hashable & Codable>(id: String, value: D) { warn(id) }
    public func callAsFunction<D: Hashable & Codable>(value: D) { warn("\(D.self)") }
    public func callAsFunction(id: String, sharingBehavior: SharingBehavior) { warn(id) }
    private func warn(_ what: String) { Runtime.current?.warn("openWindow(\(what)) opens another window, which a render does not show") }
}
@MainActor @preconcurrency
public struct DismissWindowAction {
    public func callAsFunction() {}
    public func callAsFunction(id: String) {}
    public func callAsFunction<D: Hashable & Codable>(id: String, value: D) {}
    public func callAsFunction<D: Hashable & Codable>(value: D) {}
}
@MainActor @preconcurrency
public struct OpenSettingsAction {
    public func callAsFunction() { Runtime.current?.warn("openSettings() opens the Settings window, which a render does not show") }
}

enum OpenWindowKey: EnvironmentKey { static let defaultValue = MainActor.assumeIsolated { OpenWindowAction() } }
enum DismissWindowKey: EnvironmentKey { static let defaultValue = MainActor.assumeIsolated { DismissWindowAction() } }
enum OpenSettingsKey: EnvironmentKey { static let defaultValue = MainActor.assumeIsolated { OpenSettingsAction() } }
extension EnvironmentValues {
    public var openWindow: OpenWindowAction { self[OpenWindowKey.self] }
    public var dismissWindow: DismissWindowAction { self[DismissWindowKey.self] }
    public var openSettings: OpenSettingsAction { self[OpenSettingsKey.self] }
}
