// Environment values that app code commonly reads. In a still frame most are inert.

// MARK: - Actions

public struct DismissAction {
    public init() {}
    /// Inert in a still render; during an interaction capture or a remote press (`--press`: a button's action,
    /// `onExitCommand`) it dismisses the topmost presentation, or pops the top pushed screen.
    public func callAsFunction() {
        MainActor.assumeIsolated {
            if let session = InteractionSession.current { session.dismissFromEnvironment(); return }
            guard let runtime = Runtime.current, runtime.focus.handlingPress else { return }
            if let dismiss = runtime.focus.snapshot.dismissTop {
                dismiss()
            } else if let stack = runtime.focus.popTarget() {
                runtime.focus.pushes[stack]?.removeLast()
            }
            runtime.needsAnotherPass = true
        }
    }
}

public struct OpenURLAction {
    public struct Result: Sendable {
        enum Kind: Sendable { case handled, discarded, systemAction(URL?) }
        let kind: Kind
        public static let handled = Result(kind: .handled)
        public static let discarded = Result(kind: .discarded)
        public static let systemAction = Result(kind: .systemAction(nil))
        public static func systemAction(_ url: URL) -> Result { Result(kind: .systemAction(url)) }
    }
    let handler: @Sendable (URL) -> Result
    public init(handler: @escaping @Sendable (URL) -> Result) { self.handler = handler }
    public func callAsFunction(_ url: URL) { _ = handler(url) }
    public func callAsFunction(_ url: URL, completion: @escaping (Bool) -> Void) { completion(true) }
}

public struct RefreshAction {
    let action: @Sendable () async -> Void
    public func callAsFunction() async { await action() }
}

public struct DismissSearchAction {
    public init() {}
    public func callAsFunction() {}
}

public struct PresentationMode {
    public var isPresented: Bool { presented }
    let presented: Bool
    init(isPresented: Bool) { presented = isPresented }
    public mutating func dismiss() {}
}

// MARK: - Value types

public enum ScenePhase: Hashable, Comparable, Sendable {
    case background, inactive, active
    private var order: Int { switch self { case .background: return 0; case .inactive: return 1; case .active: return 2 } }
    public static func < (a: ScenePhase, b: ScenePhase) -> Bool { a.order < b.order }
}

public enum EditMode: Hashable, Sendable {
    case inactive, transient, active
    public var isEditing: Bool { self != .inactive }
}

// MARK: - Keys

enum DismissKey: EnvironmentKey { static let defaultValue = DismissAction() }
enum OpenURLKey: EnvironmentKey { static let defaultValue = OpenURLAction { _ in .systemAction } }
enum RefreshKey: EnvironmentKey { static let defaultValue: RefreshAction? = nil }
enum DismissSearchKey: EnvironmentKey { static let defaultValue = DismissSearchAction() }
enum PresentationModeKey: EnvironmentKey { static let defaultValue = Binding.constant(PresentationMode(isPresented: false)) }
enum ScenePhaseKey: EnvironmentKey { static let defaultValue = ScenePhase.active }
enum EditModeKey: EnvironmentKey { static let defaultValue: Binding<EditMode>? = nil }
enum IsPresentedKey: EnvironmentKey { static let defaultValue = false }
enum IsSearchingKey: EnvironmentKey { static let defaultValue = false }
enum IsFocusedKey: EnvironmentKey { static let defaultValue = false }
enum LayoutDirectionKey: EnvironmentKey { static let defaultValue = LayoutDirection.leftToRight }
enum ContrastKey: EnvironmentKey { static let defaultValue = ColorSchemeContrast.standard }

/// The size classes follow the render configuration: iPhone-sized canvases are compact wide, regular tall.
/// (Wrapped so an unset value is distinguishable from an explicit nil: `storage[...] as? T?` cannot tell.)
struct SizeClassOverride { let value: UserInterfaceSizeClass? }
enum HorizontalSizeClassKey: EnvironmentKey { static let defaultValue: SizeClassOverride? = nil }
enum VerticalSizeClassKey: EnvironmentKey { static let defaultValue: SizeClassOverride? = nil }

extension UserInterfaceSizeClass {
    static func forCanvas(_ pick: (CGSize) -> UserInterfaceSizeClass) -> UserInterfaceSizeClass {
        pick(_currentCanvasSize())
    }
}

/// The device profile's size class, unless the canvas was resized with --width/--height (then the canvas decides).
package func _currentSizeClass(horizontal: Bool) -> UserInterfaceSizeClass {
    let config = _currentConfiguration()
    if config.width != nil || config.height != nil {
        return UserInterfaceSizeClass.forCanvas { horizontal ? ($0.width >= 700 ? .regular : .compact) : ($0.height >= 500 ? .regular : .compact) }
    }
    return horizontal ? config.device.horizontalSizeClass : config.device.verticalSizeClass
}

/// The canvas size of the render in progress (the default device when none is).
package func _currentCanvasSize() -> CGSize {
    let config = _currentConfiguration()
    return CGSize(width: config.width ?? config.device.size.width, height: config.height ?? config.device.size.height)
}

package func _currentConfiguration() -> RenderConfiguration {
    guard Thread.isMainThread else { return RenderConfiguration() }
    return MainActor.assumeIsolated { Runtime.current?.config ?? RenderConfiguration() }
}

enum LocaleKey: EnvironmentKey {
    static var defaultValue: Locale { Locale(identifier: _currentConfiguration().locale ?? "en_US") }
}
enum CalendarKey: EnvironmentKey {
    static var defaultValue: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = LocaleKey.defaultValue
        return calendar
    }
}
enum TimeZoneKey: EnvironmentKey { static var defaultValue: TimeZone { TimeZone.current } }

enum AccessibilityFlagKey<Tag>: EnvironmentKey { static var defaultValue: Bool { false } }
enum ReduceMotionTag {}
enum ReduceTransparencyTag {}
enum DifferentiateTag {}
enum InvertColorsTag {}
enum ShowButtonShapesTag {}
enum VoiceOverTag {}
enum SwitchControlTag {}
enum AccessibilityEnabledTag {}
enum LuminanceReducedTag {}
enum MultipleWindowsTag {}

extension EnvironmentValues {
    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }
    public var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }
    public var refresh: RefreshAction? {
        get { self[RefreshKey.self] }
        set { self[RefreshKey.self] = newValue }
    }
    public var dismissSearch: DismissSearchAction {
        get { self[DismissSearchKey.self] }
        set { self[DismissSearchKey.self] = newValue }
    }
    public var presentationMode: Binding<PresentationMode> {
        get { self[PresentationModeKey.self] }
        set { self[PresentationModeKey.self] = newValue }
    }
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
    public var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
    public var isPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }
    public var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }
    public var isFocused: Bool {
        get { self[IsFocusedKey.self] }
        set { self[IsFocusedKey.self] = newValue }
    }
    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
    public var colorSchemeContrast: ColorSchemeContrast {
        get { self[ContrastKey.self] }
        set { self[ContrastKey.self] = newValue }
    }
    public var horizontalSizeClass: UserInterfaceSizeClass? {
        get { self[HorizontalSizeClassKey.self].map(\.value) ?? _currentSizeClass(horizontal: true) }
        set { self[HorizontalSizeClassKey.self] = SizeClassOverride(value: newValue) }
    }
    public var verticalSizeClass: UserInterfaceSizeClass? {
        get { self[VerticalSizeClassKey.self].map(\.value) ?? _currentSizeClass(horizontal: false) }
        set { self[VerticalSizeClassKey.self] = SizeClassOverride(value: newValue) }
    }
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
    public var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }
    public var timeZone: TimeZone {
        get { self[TimeZoneKey.self] }
        set { self[TimeZoneKey.self] = newValue }
    }
    public var accessibilityReduceMotion: Bool {
        get { self[AccessibilityFlagKey<ReduceMotionTag>.self] }
        set { self[AccessibilityFlagKey<ReduceMotionTag>.self] = newValue }
    }
    public var accessibilityReduceTransparency: Bool {
        get { self[AccessibilityFlagKey<ReduceTransparencyTag>.self] }
        set { self[AccessibilityFlagKey<ReduceTransparencyTag>.self] = newValue }
    }
    public var accessibilityDifferentiateWithoutColor: Bool {
        get { self[AccessibilityFlagKey<DifferentiateTag>.self] }
        set { self[AccessibilityFlagKey<DifferentiateTag>.self] = newValue }
    }
    public var accessibilityInvertColors: Bool {
        get { self[AccessibilityFlagKey<InvertColorsTag>.self] }
        set { self[AccessibilityFlagKey<InvertColorsTag>.self] = newValue }
    }
    public var accessibilityShowButtonShapes: Bool {
        get { self[AccessibilityFlagKey<ShowButtonShapesTag>.self] }
        set { self[AccessibilityFlagKey<ShowButtonShapesTag>.self] = newValue }
    }
    public var accessibilityVoiceOverEnabled: Bool {
        get { self[AccessibilityFlagKey<VoiceOverTag>.self] }
        set { self[AccessibilityFlagKey<VoiceOverTag>.self] = newValue }
    }
    public var accessibilitySwitchControlEnabled: Bool {
        get { self[AccessibilityFlagKey<SwitchControlTag>.self] }
        set { self[AccessibilityFlagKey<SwitchControlTag>.self] = newValue }
    }
    public var accessibilityEnabled: Bool {
        get { self[AccessibilityFlagKey<AccessibilityEnabledTag>.self] }
        set { self[AccessibilityFlagKey<AccessibilityEnabledTag>.self] = newValue }
    }
    public var isLuminanceReduced: Bool {
        get { self[AccessibilityFlagKey<LuminanceReducedTag>.self] }
        set { self[AccessibilityFlagKey<LuminanceReducedTag>.self] = newValue }
    }
    public var supportsMultipleWindows: Bool {
        get { self[AccessibilityFlagKey<MultipleWindowsTag>.self] }
        set { self[AccessibilityFlagKey<MultipleWindowsTag>.self] = newValue }
    }
}
