// The UIKit singletons and system services app code touches next to SwiftUI: responder chain,
// screen, device, application and scenes, pasteboard, accessibility settings, haptics.
// Everything is non-isolated so it can be called from any closure the app writes, and nothing
// has an effect outside the process: URLs are not opened, haptics do not play.

import Foundation
import SwiftUI

open class UIEvent: NSObject {
    public enum EventType: Int, Sendable { case touches, motion, remoteControl, presses, scroll = 10, hover = 11, transform = 14 }
    public enum EventSubtype: Int, Sendable {
        case none = 0, motionShake = 1
        case remoteControlPlay = 100, remoteControlPause, remoteControlStop, remoteControlTogglePlayPause
        case remoteControlNextTrack, remoteControlPreviousTrack
    }
    open var type: EventType { .touches }
    open var subtype: EventSubtype { .none }
    open var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
    open var allTouches: Set<UITouch>? { nil }
    public override init() { super.init() }
}

open class UITouch: NSObject {
    public enum Phase: Int, Sendable { case began, moved, stationary, ended, cancelled, regionEntered, regionMoved, regionExited }
    public enum TouchType: Int, Sendable { case direct, indirect, pencil, indirectPointer }
    open var phase: Phase { .ended }
    open var tapCount: Int { 1 }
    open var type: TouchType { .direct }
    open weak var view: UIView?
    open var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
    open var force: CGFloat { 0 }
    open func location(in view: UIView?) -> CGPoint { .zero }
    open func previousLocation(in view: UIView?) -> CGPoint { .zero }
    public override init() { super.init() }
}

open class UIPress: NSObject {
    public enum PressType: Int, Sendable { case upArrow, downArrow, leftArrow, rightArrow, select, menu, playPause, pageUp = 30, pageDown = 31 }
    open var type: PressType { .select }
    open var phase: UITouch.Phase { .ended }
    public override init() { super.init() }
}
open class UIPressesEvent: UIEvent {}

open class UIResponder: NSObject {
    public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
    public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
    public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
    public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
    public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
    public static let keyboardDidChangeFrameNotification = Notification.Name("UIKeyboardDidChangeFrameNotification")
    public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    public static let keyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"
    public static let keyboardIsLocalUserInfoKey = "UIKeyboardIsLocalUserInfoKey"

    public override init() { super.init() }

    /// The next responder up the chain (a view's superview or controller, a controller's parent...).
    open var next: UIResponder? { nil }
    open var isFirstResponder: Bool { false }
    open var canBecomeFirstResponder: Bool { false }
    open var canResignFirstResponder: Bool { true }
    open var undoManager: UndoManager? { nil }
    open var inputView: UIView? { nil }
    open var inputAccessoryView: UIView? { nil }
    open var userActivity: NSUserActivity? { get { nil } set {} }
    @discardableResult open func becomeFirstResponder() -> Bool { true }
    @discardableResult open func resignFirstResponder() -> Bool { true }
    open func reloadInputViews() {}
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    open func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {}
    open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {}
    open func motionCancelled(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {}
    open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    open func target(forAction action: Selector, withSender sender: Any?) -> Any? { nil }
}

/// Foundation's UndoManager is missing on Linux: a registry that records nothing.
open class UndoManager: NSObject {
    public override init() { super.init() }
    open var canUndo: Bool { false }
    open var canRedo: Bool { false }
    open var isUndoing: Bool { false }
    open var isRedoing: Bool { false }
    open var undoActionName: String { "" }
    open var redoActionName: String { "" }
    open var undoMenuItemTitle: String { "Undo" }
    open var redoMenuItemTitle: String { "Redo" }
    open var levelsOfUndo = 0
    open var groupsByEvent = true
    open var isUndoRegistrationEnabled: Bool { true }
    open func undo() {}
    open func redo() {}
    open func beginUndoGrouping() {}
    open func endUndoGrouping() {}
    open func disableUndoRegistration() {}
    open func enableUndoRegistration() {}
    open func removeAllActions() {}
    open func removeAllActions(withTarget target: Any) {}
    open func setActionName(_ actionName: String) {}
    open func registerUndo<TargetType: AnyObject>(withTarget target: TargetType, handler: @escaping (TargetType) -> Void) {}
}
extension NSNotification.Name {
    public static let NSUndoManagerDidUndoChange = Notification.Name("NSUndoManagerDidUndoChangeNotification")
    public static let NSUndoManagerDidRedoChange = Notification.Name("NSUndoManagerDidRedoChangeNotification")
    public static let NSUndoManagerCheckpoint = Notification.Name("NSUndoManagerCheckpointNotification")
    public static let NSUndoManagerDidCloseUndoGroup = Notification.Name("NSUndoManagerDidCloseUndoGroupNotification")
    public static let NSUndoManagerWillUndoChange = Notification.Name("NSUndoManagerWillUndoChangeNotification")
    public static let NSUndoManagerWillRedoChange = Notification.Name("NSUndoManagerWillRedoChangeNotification")
}

// MARK: - Screen / device

public enum UIInterfaceOrientation: Int, Sendable {
    case unknown, portrait, portraitUpsideDown, landscapeRight, landscapeLeft
    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}
public struct UIInterfaceOrientationMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let portrait = UIInterfaceOrientationMask(rawValue: 1 << 1)
    public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 1 << 2)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 1 << 3)
    public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 1 << 4)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    public static let allButUpsideDown: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
}

func _currentInterfaceOrientation() -> UIInterfaceOrientation {
    switch _currentConfiguration().device.orientation {
    case .portrait: return .portrait
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    }
}

public protocol UICoordinateSpace: AnyObject {
    var bounds: CGRect { get }
}

open class UIScreen: NSObject, UICoordinateSpace, UITraitEnvironment {
    public static let main = UIScreen()
    public static var screens: [UIScreen] { [main] }
    public var bounds: CGRect { CGRect(origin: .zero, size: _currentCanvasSize()) }
    public var nativeBounds: CGRect {
        let s = scale
        return CGRect(x: 0, y: 0, width: bounds.width * s, height: bounds.height * s)
    }
    public var scale: CGFloat { let c = _currentConfiguration(); return c.scale ?? c.device.scale }
    public var nativeScale: CGFloat { scale }
    /// Settable, with no effect on the picture.
    public var brightness: CGFloat = 0.5
    public var maximumFramesPerSecond: Int { 60 }
    public var isCaptured: Bool { false }
    public var coordinateSpace: UICoordinateSpace { self }
    public var fixedCoordinateSpace: UICoordinateSpace { self }
    public var traitCollection: UITraitCollection { .current }
    public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
    public static let brightnessDidChangeNotification = Notification.Name("UIScreenBrightnessDidChangeNotification")
    public static let capturedDidChangeNotification = Notification.Name("UIScreenCapturedDidChangeNotification")
    public static let didConnectNotification = Notification.Name("UIScreenDidConnectNotification")
    public static let didDisconnectNotification = Notification.Name("UIScreenDidDisconnectNotification")
}

open class UIDevice: NSObject {
    public enum BatteryState: Int, Sendable { case unknown, unplugged, charging, full }
    public enum Orientation: Int, Sendable {
        case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
        public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
        public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
        public var isFlat: Bool { self == .faceUp || self == .faceDown }
        public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
    }
    public static let current = UIDevice()
    public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChangeNotification")
    public static let batteryStateDidChangeNotification = Notification.Name("UIDeviceBatteryStateDidChangeNotification")
    public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")
    public static let proximityStateDidChangeNotification = Notification.Name("UIDeviceProximityStateDidChangeNotification")

    public var userInterfaceIdiom: UIUserInterfaceIdiom {
        switch _currentConfiguration().device.idiom { case .pad: return .pad; case .tv: return .tv; case .phone: return .phone }
    }
    public var name: String { model }
    public var model: String { userInterfaceIdiom == .pad ? "iPad" : userInterfaceIdiom == .tv ? "Apple TV" : "iPhone" }
    public var localizedModel: String { model }
    public var systemName: String { userInterfaceIdiom == .pad ? "iPadOS" : userInterfaceIdiom == .tv ? "tvOS" : "iOS" }
    public var systemVersion: String { [27, 26, 18].first { RenderedPlatform.isAtLeast(iOS: $0) }.map { "\($0).0" } ?? "18.0" }
    public var orientation: Orientation {
        switch _currentConfiguration().device.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        }
    }
    public var isBatteryMonitoringEnabled = false
    public var batteryLevel: Float { isBatteryMonitoringEnabled ? 1 : -1 }
    public var batteryState: BatteryState { isBatteryMonitoringEnabled ? .full : .unknown }
    public var isProximityMonitoringEnabled = false
    public var proximityState: Bool { false }
    public var isMultitaskingSupported: Bool { true }
    public var isGeneratingDeviceOrientationNotifications: Bool { false }
    public var identifierForVendor: UUID? { UUID(uuidString: "00000000-0000-0000-0000-000000000000") }
    public func beginGeneratingDeviceOrientationNotifications() {}
    public func endGeneratingDeviceOrientationNotifications() {}
    public func playInputClick() {}
}

// MARK: - Scenes and the application

open class UISceneSession: NSObject {
    public struct Role: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let windowApplication = Role(rawValue: "UIWindowSceneSessionRoleApplication")
        public static let windowExternalDisplayNonInteractive = Role(rawValue: "UIWindowSceneSessionRoleExternalDisplayNonInteractive")
    }
    public var role: Role { .windowApplication }
    public var persistentIdentifier: String { "main" }
    public var userInfo: [String: Any]?
    public var configuration: UISceneConfiguration { UISceneConfiguration(name: nil, sessionRole: role) }
}
open class UISceneConfiguration: NSObject {
    public var name: String?
    public var role: UISceneSession.Role
    public var delegateClass: AnyClass?
    public var sceneClass: AnyClass?
    public init(name: String?, sessionRole: UISceneSession.Role) { self.name = name; role = sessionRole; super.init() }
}

open class UIScene: UIResponder {
    public enum ActivationState: Int, Sendable { case unattached = -1, foregroundActive, foregroundInactive, background }
    public struct ConnectionOptions {
        public var urlContexts: Set<UIOpenURLContext> { [] }
        public var userActivities: Set<NSUserActivity> { [] }
        public var shortcutItem: UIApplicationShortcutItem? { nil }
    }
    public static let didActivateNotification = Notification.Name("UISceneDidActivateNotification")
    public static let willDeactivateNotification = Notification.Name("UISceneWillDeactivateNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UISceneDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UISceneWillEnterForegroundNotification")
    public static let willConnectNotification = Notification.Name("UISceneWillConnectNotification")
    public static let didDisconnectNotification = Notification.Name("UISceneDidDisconnectNotification")

    public var activationState: ActivationState { .foregroundActive }
    public var title: String! = ""
    public var session: UISceneSession { UISceneSession() }
    public weak var delegate: UISceneDelegate?
    public func open(_ url: URL, options: OpenExternalURLOptions?, completionHandler completion: ((Bool) -> Void)? = nil) { completion?(false) }
    open class OpenExternalURLOptions: NSObject { public var universalLinksOnly = false }
}
open class UIOpenURLContext: NSObject { public var url: URL { URL(fileURLWithPath: "/") } }
open class UIApplicationShortcutItem: NSObject {
    public let type: String
    public let localizedTitle: String
    public init(type: String, localizedTitle: String) { self.type = type; self.localizedTitle = localizedTitle; super.init() }
}
public protocol UISceneDelegate: NSObjectProtocol {}
public protocol UIWindowSceneDelegate: UISceneDelegate {}

open class UIStatusBarManager: NSObject {
    public var statusBarStyle: UIStatusBarStyle { .default }
    public var isStatusBarHidden: Bool { false }
    public var statusBarFrame: CGRect { CGRect(x: 0, y: 0, width: _currentCanvasSize().width, height: _currentSafeInsets().top) }
}
public enum UIStatusBarStyle: Int, Sendable { case `default` = 0, lightContent = 1, darkContent = 3 }
public enum UIStatusBarAnimation: Int, Sendable { case none, fade, slide }

open class UIWindowScene: UIScene {
    public enum DismissalAnimation: Int, Sendable { case standard = 1, commit, decline }
    open class GeometryPreferences: NSObject {
        open class iOS: GeometryPreferences {
            public var interfaceOrientations: UIInterfaceOrientationMask = .all
            public init(interfaceOrientations: UIInterfaceOrientationMask) { self.interfaceOrientations = interfaceOrientations; super.init() }
            public override init() { super.init() }
        }
    }
    let window = UIWindow(frame: CGRect(origin: .zero, size: _currentCanvasSize()))
    public var windows: [UIWindow] { [window] }
    public var keyWindow: UIWindow? { window }
    public var screen: UIScreen { .main }
    public var interfaceOrientation: UIInterfaceOrientation { _currentInterfaceOrientation() }
    public var coordinateSpace: UICoordinateSpace { UIScreen.main }
    public var traitCollection: UITraitCollection { .current }
    public var statusBarManager: UIStatusBarManager? { UIStatusBarManager() }
    public var sizeRestrictions: UISceneSizeRestrictions? { nil }
    public var isFullScreen: Bool { true }
    public func requestGeometryUpdate(_ preferences: GeometryPreferences, errorHandler: ((Error) -> Void)? = nil) {}
}
open class UISceneSizeRestrictions: NSObject {
    public var minimumSize = CGSize.zero
    public var maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
}

func _currentSafeInsets() -> UIEdgeInsets {
    let a = _currentConfiguration().device.safeArea
    return UIEdgeInsets(top: a.top, left: a.leading, bottom: a.bottom, right: a.trailing)
}

public struct UIBackgroundTaskIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}
public enum UIBackgroundRefreshStatus: Int, Sendable { case restricted, denied, available }
public enum UIBackgroundFetchResult: UInt, Sendable { case newData, noData, failed }

open class UIApplication: UIResponder {
    public struct OpenExternalURLOptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let universalLinksOnly = OpenExternalURLOptionsKey(rawValue: "UIApplicationOpenURLOptionUniversalLinksOnly")
    }
    public struct OpenURLOptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let sourceApplication = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsSourceApplicationKey")
        public static let annotation = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsAnnotationKey")
        public static let openInPlace = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsOpenInPlaceKey")
    }
    public struct LaunchOptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
        public static let remoteNotification = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsRemoteNotificationKey")
        public static let sourceApplication = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsSourceApplicationKey")
        public static let userActivityDictionary = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsUserActivityDictionaryKey")
        public static let shortcutItem = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsShortcutItemKey")
        public static let location = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsLocationKey")
    }
    public enum State: Int, Sendable { case active, inactive, background }

    public static let shared = UIApplication()
    public static let openSettingsURLString = "app-settings:"
    public static let openNotificationSettingsURLString = "app-settings:notifications"
    public static let openDefaultApplicationsSettingsURLString = "app-settings:default-apps"
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
    public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
    public static let didFinishLaunchingNotification = Notification.Name("UIApplicationDidFinishLaunchingNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")
    public static let significantTimeChangeNotification = Notification.Name("UIApplicationSignificantTimeChangeNotification")
    public static let userDidTakeScreenshotNotification = Notification.Name("UIApplicationUserDidTakeScreenshotNotification")
    public static let protectedDataDidBecomeAvailableNotification = Notification.Name("UIApplicationProtectedDataDidBecomeAvailable")
    public static let protectedDataWillBecomeUnavailableNotification = Notification.Name("UIApplicationProtectedDataWillBecomeUnavailable")
    public static let backgroundRefreshStatusDidChangeNotification = Notification.Name("UIApplicationBackgroundRefreshStatusDidChangeNotification")
    public static let backgroundFetchIntervalMinimum: TimeInterval = 0
    public static let backgroundFetchIntervalNever: TimeInterval = .greatestFiniteMagnitude

    private let scene = UIWindowScene()
    /// One foreground scene with one window, the size of the render.
    public var connectedScenes: Set<UIScene> { [scene] }
    public var openSessions: Set<UISceneSession> { [] }
    public var windows: [UIWindow] { scene.windows }
    public var keyWindow: UIWindow? { scene.keyWindow }
    public weak var delegate: UIApplicationDelegate?
    public var applicationState: State { .active }
    public var applicationIconBadgeNumber = 0
    public var isIdleTimerDisabled = false
    public var supportsMultipleScenes: Bool { false }
    public var supportsAlternateIcons: Bool { false }
    public var alternateIconName: String? { nil }
    public var isRegisteredForRemoteNotifications: Bool { false }
    public var isProtectedDataAvailable: Bool { true }
    public var backgroundTimeRemaining: TimeInterval { .greatestFiniteMagnitude }
    public var backgroundRefreshStatus: UIBackgroundRefreshStatus { .available }
    public var userInterfaceLayoutDirection: UIUserInterfaceLayoutDirection { .leftToRight }
    public var preferredContentSizeCategory: UIContentSizeCategory { UITraitCollection.current.preferredContentSizeCategory }
    public var statusBarOrientation: UIInterfaceOrientation { _currentInterfaceOrientation() }
    public var statusBarFrame: CGRect { UIStatusBarManager().statusBarFrame }
    public var shortcutItems: [UIApplicationShortcutItem]?

    /// Nothing is opened; the completion handler reports failure.
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {
        completion?(false)
    }
    @discardableResult
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:]) async -> Bool { false }
    public func canOpenURL(_ url: URL) -> Bool { false }
    public func registerForRemoteNotifications() {}
    public func unregisterForRemoteNotifications() {}
    @discardableResult
    public func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool { false }
    public func beginBackgroundTask(expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier { UIBackgroundTaskIdentifier(rawValue: 1) }
    public func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        UIBackgroundTaskIdentifier(rawValue: 1)
    }
    public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
    public func setAlternateIconName(_ alternateIconName: String?, completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    public func setAlternateIconName(_ alternateIconName: String?) async throws {}
    public func setMinimumBackgroundFetchInterval(_ minimumBackgroundFetchInterval: TimeInterval) {}
    public func requestSceneSessionActivation(_ sceneSession: UISceneSession?, userActivity: NSUserActivity?, options: UIScene.ActivationRequestOptions?,
                                              errorHandler: ((Error) -> Void)? = nil) {}
    public func requestSceneSessionDestruction(_ sceneSession: UISceneSession, options: UISceneDestructionRequestOptions?, errorHandler: ((Error) -> Void)? = nil) {}
    public func beginIgnoringInteractionEvents() {}
    public func endIgnoringInteractionEvents() {}
    public func beginReceivingRemoteControlEvents() {}
    public func endReceivingRemoteControlEvents() {}
    public func completeStateRestoration() {}
}
extension UIScene {
    open class ActivationRequestOptions: NSObject { public var requestingScene: UIScene? }
}
open class UISceneDestructionRequestOptions: NSObject {}

/// App delegate callbacks are never called: there is no app launch, only views to render.
public protocol UIApplicationDelegate: NSObjectProtocol {}

// MARK: - Pasteboard

/// An in-memory pasteboard: what is copied can be read back, and never leaves the process.
open class UIPasteboard: NSObject {
    public struct Name: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let general = Name("com.apple.UIKit.pboard.general")
    }
    public struct OptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let expirationDate = OptionsKey(rawValue: "UIPasteboardOptionExpirationDate")
        public static let localOnly = OptionsKey(rawValue: "UIPasteboardOptionLocalOnly")
    }
    public static let changedNotification = Notification.Name("UIPasteboardChangedNotification")
    public static let general = UIPasteboard()
    public static func withUniqueName() -> UIPasteboard { UIPasteboard() }
    public convenience init?(name: Name, create: Bool) { self.init() }

    public private(set) var changeCount = 0
    public var items: [[String: Any]] = [] { didSet { changeCount += 1 } }

    public var strings: [String]? {
        get { let list = items.compactMap { $0["public.utf8-plain-text"] as? String }; return list.isEmpty ? nil : list }
        set { items = (newValue ?? []).map { ["public.utf8-plain-text": $0] } }
    }
    public var string: String? {
        get { strings?.first }
        set { strings = newValue.map { [$0] } }
    }
    public var urls: [URL]? {
        get { let list = items.compactMap { $0["public.url"] as? URL }; return list.isEmpty ? nil : list }
        set { items = (newValue ?? []).map { ["public.url": $0] } }
    }
    public var url: URL? {
        get { urls?.first }
        set { urls = newValue.map { [$0] } }
    }
    public var images: [UIImage]? {
        get { let list = items.compactMap { $0["public.image"] as? UIImage }; return list.isEmpty ? nil : list }
        set { items = (newValue ?? []).map { ["public.image": $0] } }
    }
    public var image: UIImage? {
        get { images?.first }
        set { images = newValue.map { [$0] } }
    }
    public var colors: [UIColor]? {
        get { let list = items.compactMap { $0["com.apple.uikit.color"] as? UIColor }; return list.isEmpty ? nil : list }
        set { items = (newValue ?? []).map { ["com.apple.uikit.color": $0] } }
    }
    public var color: UIColor? {
        get { colors?.first }
        set { colors = newValue.map { [$0] } }
    }
    public var hasStrings: Bool { strings != nil }
    public var hasURLs: Bool { urls != nil }
    public var hasImages: Bool { images != nil }
    public var hasColors: Bool { colors != nil }
    public var numberOfItems: Int { items.count }
    public var types: [String] { items.first.map { Array($0.keys) } ?? [] }

    public func setItems(_ items: [[String: Any]], options: [OptionsKey: Any] = [:]) { self.items = items }
    public func addItems(_ items: [[String: Any]]) { self.items += items }
    public func setValue(_ value: Any, forPasteboardType pasteboardType: String) { items = [[pasteboardType: value]] }
    public func setData(_ data: Data, forPasteboardType pasteboardType: String) { items = [[pasteboardType: data]] }
    public func value(forPasteboardType pasteboardType: String) -> Any? { items.first?[pasteboardType] }
    public func data(forPasteboardType pasteboardType: String) -> Data? { items.first?[pasteboardType] as? Data }
    public func contains(pasteboardTypes: [String]) -> Bool { pasteboardTypes.contains { type in items.contains { $0[type] != nil } } }
    public func setObjects<T>(_ objects: [T]) {
        items = objects.map { object in
            if let s = object as? String { return ["public.utf8-plain-text": s] }
            if let u = object as? URL { return ["public.url": u] }
            if let i = object as? UIImage { return ["public.image": i] }
            return ["public.data": object]
        }
    }
}

// MARK: - Accessibility settings (all at their defaults)

public enum UIAccessibility {
    public struct Notification: RawRepresentable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let screenChanged = Notification(rawValue: 1000)
        public static let layoutChanged = Notification(rawValue: 1001)
        public static let announcement = Notification(rawValue: 1008)
        public static let pageScrolled = Notification(rawValue: 1009)
        public static let pauseAssistiveTechnology = Notification(rawValue: 1019)
        public static let resumeAssistiveTechnology = Notification(rawValue: 1020)
    }
    public static func post(notification: Notification, argument: Any?) {}
    public static func requestGuidedAccessSession(enabled enable: Bool, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
    public static func focusedElement(using assistiveTechnologyIdentifier: String?) -> Any? { nil }
    public static func convertToScreenCoordinates(_ rect: CGRect, in view: UIView) -> CGRect { rect }

    public static var isVoiceOverRunning: Bool { false }
    public static var isSwitchControlRunning: Bool { false }
    public static var isAssistiveTouchRunning: Bool { false }
    public static var isReduceMotionEnabled: Bool { false }
    public static var isReduceTransparencyEnabled: Bool { false }
    public static var isBoldTextEnabled: Bool { false }
    public static var isDarkerSystemColorsEnabled: Bool { false }
    public static var isGrayscaleEnabled: Bool { false }
    public static var isInvertColorsEnabled: Bool { false }
    public static var isMonoAudioEnabled: Bool { false }
    public static var isClosedCaptioningEnabled: Bool { false }
    public static var isGuidedAccessEnabled: Bool { false }
    public static var isShakeToUndoEnabled: Bool { true }
    public static var isSpeakSelectionEnabled: Bool { false }
    public static var isSpeakScreenEnabled: Bool { false }
    public static var isVideoAutoplayEnabled: Bool { true }
    public static var isOnOffSwitchLabelsEnabled: Bool { false }
    public static var shouldDifferentiateWithoutColor: Bool { false }
    public static var prefersCrossFadeTransitions: Bool { false }
    public static var buttonShapesEnabled: Bool { false }

    public static let voiceOverStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityVoiceOverStatusDidChangeNotification")
    public static let reduceMotionStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityReduceMotionStatusDidChangeNotification")
    public static let reduceTransparencyStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityReduceTransparencyStatusDidChangeNotification")
    public static let boldTextStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityBoldTextStatusDidChangeNotification")
    public static let darkerSystemColorsStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityDarkerSystemColorsStatusDidChangeNotification")
    public static let invertColorsStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityInvertColorsStatusDidChangeNotification")
    public static let grayscaleStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilityGrayscaleStatusDidChangeNotification")
    public static let switchControlStatusDidChangeNotification = Foundation.Notification.Name("UIAccessibilitySwitchControlStatusDidChangeNotification")
    public static let differentiateWithoutColorDidChangeNotification = Foundation.Notification.Name("UIAccessibilityShouldDifferentiateWithoutColorDidChangeNotification")
    public static let announcementDidFinishNotification = Foundation.Notification.Name("UIAccessibilityAnnouncementDidFinishNotification")
}

public struct UIAccessibilityTraits: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let none: UIAccessibilityTraits = []
    public static let button = UIAccessibilityTraits(rawValue: 1 << 0)
    public static let link = UIAccessibilityTraits(rawValue: 1 << 1)
    public static let image = UIAccessibilityTraits(rawValue: 1 << 2)
    public static let selected = UIAccessibilityTraits(rawValue: 1 << 3)
    public static let playsSound = UIAccessibilityTraits(rawValue: 1 << 4)
    public static let keyboardKey = UIAccessibilityTraits(rawValue: 1 << 5)
    public static let staticText = UIAccessibilityTraits(rawValue: 1 << 6)
    public static let summaryElement = UIAccessibilityTraits(rawValue: 1 << 7)
    public static let notEnabled = UIAccessibilityTraits(rawValue: 1 << 8)
    public static let updatesFrequently = UIAccessibilityTraits(rawValue: 1 << 9)
    public static let searchField = UIAccessibilityTraits(rawValue: 1 << 10)
    public static let header = UIAccessibilityTraits(rawValue: 1 << 16)
    public static let adjustable = UIAccessibilityTraits(rawValue: 1 << 12)
}

// MARK: - Haptics (no hardware)

open class UIFeedbackGenerator: NSObject {
    public override init() { super.init() }
    public convenience init(view: UIView) { self.init() }
    open func prepare() {}
}
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int, Sendable { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) { super.init() }
    public convenience init(style: FeedbackStyle, view: UIView) { self.init(style: style) }
    public override init() { super.init() }
    public func impactOccurred() {}
    public func impactOccurred(intensity: CGFloat) {}
    public func impactOccurred(at location: CGPoint) {}
    public func impactOccurred(intensity: CGFloat, at location: CGPoint) {}
}
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int, Sendable { case success, warning, error }
    public override init() { super.init() }
    public func notificationOccurred(_ notificationType: FeedbackType) {}
    public func notificationOccurred(_ notificationType: FeedbackType, at location: CGPoint) {}
}
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    public override init() { super.init() }
    public func selectionChanged() {}
    public func selectionChanged(at location: CGPoint) {}
}

// MARK: - @UIApplicationDelegateAdaptor

@propertyWrapper
public struct UIApplicationDelegateAdaptor<DelegateType: NSObject & UIApplicationDelegate>: DynamicProperty {
    final class Box { var delegate: DelegateType? }
    let box = Box()
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {}

    public var wrappedValue: DelegateType {
        if let d = box.delegate { return d }
        // Swift cannot construct an arbitrary NSObject subclass from a metatype (its init() is not
        // `required`), so reading the delegate instance is the one thing this shim cannot do.
        fatalError("@UIApplicationDelegateAdaptor: the \(DelegateType.self) instance is not available when rendering")
    }
}
extension UIApplicationDelegateAdaptor where DelegateType: ObservableObject {
    public var projectedValue: ObservedObject<DelegateType>.Wrapper { ObservedObject<DelegateType>.Wrapper(_object: wrappedValue) }
}
