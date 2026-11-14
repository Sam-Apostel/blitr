// `import WatchKit`: the watch app's device, application and extension objects, as on a watch at rest:
// the app is active, haptics play nothing, the screen is the rendered canvas.
@_exported import Foundation
import SwiftUI

public enum WKHapticType: Int, Sendable {
    case notification, directionUp, directionDown, success, failure, retry, start, stop, click
    case navigationGenericManeuver, navigationLeftTurn, navigationRightTurn, underwaterDepthPrompt, underwaterDepthCriticalPrompt
}

public enum WKInterfaceDeviceWristLocation: Int, Sendable { case left, right }
public enum WKInterfaceDeviceCrownOrientation: Int, Sendable { case left, right }
public enum WKInterfaceDeviceBatteryState: Int, Sendable { case unknown, unplugged, charging, full }
public enum WKWaterResistanceRating: Int, Sendable { case ipx7, wr50, wr100 }
public enum WKInterfaceLayoutDirection: Int, Sendable { case leftToRight, rightToLeft }

public final class WKInterfaceDevice: @unchecked Sendable {
    private static let shared = WKInterfaceDevice()
    public static func current() -> WKInterfaceDevice { shared }

    public var screenBounds: CGRect { CGRect(origin: .zero, size: Thread.isMainThread ? MainActor.assumeIsolated { _currentCanvasSize() } : .zero) }
    public var screenScale: CGFloat { 2 }
    public var name: String { "Apple Watch" }
    public var model: String { "Apple Watch" }
    public var localizedModel: String { "Apple Watch" }
    public var systemName: String { "watchOS" }
    public var systemVersion: String { "11.0" }
    public var identifierForVendor: UUID? { UUID(uuidString: "00000000-0000-0000-0000-000000000000") }
    public var preferredContentSizeCategory: String { "UICTContentSizeCategoryL" }
    public var wristLocation: WKInterfaceDeviceWristLocation { .left }
    public var crownOrientation: WKInterfaceDeviceCrownOrientation { .right }
    public var layoutDirection: WKInterfaceLayoutDirection { .leftToRight }
    public var waterResistanceRating: WKWaterResistanceRating { .wr50 }
    public var supportsAudioStreaming: Bool { true }
    public var isWaterLockEnabled: Bool { false }
    public var isBatteryMonitoringEnabled = false
    public var batteryLevel: Float { isBatteryMonitoringEnabled ? 1 : -1 }
    public var batteryState: WKInterfaceDeviceBatteryState { isBatteryMonitoringEnabled ? .full : .unknown }

    public func play(_ type: WKHapticType) {}
    public func enableWaterLock() {}
}

public enum WKApplicationState: Int, Sendable { case active, inactive, background }

@MainActor
public protocol WKApplicationDelegate: AnyObject {
    func applicationDidFinishLaunching()
    func applicationDidBecomeActive()
    func applicationWillResignActive()
    func applicationWillEnterForeground()
    func applicationDidEnterBackground()
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data)
    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error)
}
extension WKApplicationDelegate {
    public func applicationDidFinishLaunching() {}
    public func applicationDidBecomeActive() {}
    public func applicationWillResignActive() {}
    public func applicationWillEnterForeground() {}
    public func applicationDidEnterBackground() {}
    public func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {}
    public func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}
}
public typealias WKExtensionDelegate = WKApplicationDelegate

@MainActor
public class WKApplication {
    private static let instance = WKApplication()
    public class func shared() -> WKApplication { instance }
    public weak var delegate: WKApplicationDelegate?
    public var applicationState: WKApplicationState { .active }
    public var isApplicationRunningInDock: Bool { false }
    public var isAutorotating = false
    public var isAutorotated: Bool { false }
    public var isFrontmostTimeoutExtended = false
    public var isRegisteredForRemoteNotifications: Bool { false }
    public var globalTintColor: Color? { nil }
    public func registerForRemoteNotifications() {}
    public func unregisterForRemoteNotifications() {}
    public func openSystemURL(_ url: URL) {}
    public func scheduleBackgroundRefresh(withPreferredDate preferredFireDate: Date, userInfo: (NSSecureCoding & NSObjectProtocol)?,
                                          scheduledCompletion: @escaping (Error?) -> Void) {
        scheduledCompletion(nil)
    }
    public func scheduleSnapshotRefresh(withPreferredDate preferredFireDate: Date, userInfo: (NSSecureCoding & NSObjectProtocol)?,
                                        scheduledCompletion: @escaping (Error?) -> Void) {
        scheduledCompletion(nil)
    }
}

/// The pre-watchOS 7 name of the application object.
@MainActor
public final class WKExtension: WKApplication {
    private static let instance = WKExtension()
    public override class func shared() -> WKExtension { instance }
}

/// `@WKApplicationDelegateAdaptor` / `@WKExtensionDelegateAdaptor`: the delegate is made when the app launches,
/// which a render does not do.
@propertyWrapper
public struct WKApplicationDelegateAdaptor<DelegateType: NSObject & WKApplicationDelegate>: DynamicProperty {
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {}
    public var wrappedValue: DelegateType {
        fatalError("@WKApplicationDelegateAdaptor: the \(DelegateType.self) instance is not available when rendering")
    }
}
public typealias WKExtensionDelegateAdaptor = WKApplicationDelegateAdaptor
