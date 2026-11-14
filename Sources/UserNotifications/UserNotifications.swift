// `import UserNotifications`: the notification center of a fresh install. Authorization is not
// determined, a request for it is answered no, and scheduled requests are kept (and listed) but never
// delivered.
@_exported import Foundation

public enum UNAuthorizationStatus: Int, Sendable { case notDetermined, denied, authorized, provisional, ephemeral }
public enum UNNotificationSetting: Int, Sendable { case notSupported, disabled, enabled }
public enum UNAlertStyle: Int, Sendable { case none, banner, alert }
public enum UNShowPreviewsSetting: Int, Sendable { case always, whenAuthenticated, never }
public enum UNNotificationInterruptionLevel: UInt, Sendable { case passive, active, timeSensitive, critical }

public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
    public static let timeSensitive = UNAuthorizationOptions(rawValue: 1 << 8)
}
public struct UNNotificationPresentationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

public let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
public let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

open class UNNotificationSettings: NSObject, @unchecked Sendable {
    open var authorizationStatus: UNAuthorizationStatus { .notDetermined }
    open var alertSetting: UNNotificationSetting { .disabled }
    open var soundSetting: UNNotificationSetting { .disabled }
    open var badgeSetting: UNNotificationSetting { .disabled }
    open var lockScreenSetting: UNNotificationSetting { .disabled }
    open var notificationCenterSetting: UNNotificationSetting { .disabled }
    open var timeSensitiveSetting: UNNotificationSetting { .disabled }
    open var alertStyle: UNAlertStyle { .none }
    open var showPreviewsSetting: UNShowPreviewsSetting { .always }
}

open class UNNotificationSound: NSObject, @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name; super.init() }
    open class var `default`: UNNotificationSound { UNNotificationSound(name: "default") }
    open class var defaultCritical: UNNotificationSound { UNNotificationSound(name: "critical") }
    public convenience init(named name: UNNotificationSoundName) { self.init(name: name.rawValue) }
}
public struct UNNotificationSoundName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

open class UNNotificationAttachment: NSObject, @unchecked Sendable {
    public let identifier: String
    public let url: URL
    init(identifier: String, url: URL) { self.identifier = identifier; self.url = url; super.init() }
    public class func attachment(withIdentifier identifier: String, url: URL, options: [AnyHashable: Any]? = nil) throws -> UNNotificationAttachment {
        UNNotificationAttachment(identifier: identifier, url: url)
    }
}

open class UNNotificationContent: NSObject, @unchecked Sendable {
    open internal(set) var title = ""
    open internal(set) var subtitle = ""
    open internal(set) var body = ""
    open internal(set) var badge: NSNumber?
    open internal(set) var sound: UNNotificationSound?
    open internal(set) var userInfo: [AnyHashable: Any] = [:]
    open internal(set) var categoryIdentifier = ""
    open internal(set) var threadIdentifier = ""
    open internal(set) var targetContentIdentifier: String?
    open internal(set) var attachments: [UNNotificationAttachment] = []
    open internal(set) var interruptionLevel = UNNotificationInterruptionLevel.active
    open internal(set) var relevanceScore: Double = 0
    open internal(set) var launchImageName = ""
    public override init() { super.init() }
    open override func mutableCopy() -> Any {
        let copy = UNMutableNotificationContent()
        copy.title = title; copy.subtitle = subtitle; copy.body = body; copy.badge = badge; copy.sound = sound
        copy.userInfo = userInfo; copy.categoryIdentifier = categoryIdentifier; copy.threadIdentifier = threadIdentifier
        return copy
    }
}
open class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    open override var title: String { get { super.title } set { super.title = newValue } }
    open override var subtitle: String { get { super.subtitle } set { super.subtitle = newValue } }
    open override var body: String { get { super.body } set { super.body = newValue } }
    open override var badge: NSNumber? { get { super.badge } set { super.badge = newValue } }
    open override var sound: UNNotificationSound? { get { super.sound } set { super.sound = newValue } }
    open override var userInfo: [AnyHashable: Any] { get { super.userInfo } set { super.userInfo = newValue } }
    open override var categoryIdentifier: String { get { super.categoryIdentifier } set { super.categoryIdentifier = newValue } }
    open override var threadIdentifier: String { get { super.threadIdentifier } set { super.threadIdentifier = newValue } }
    open override var targetContentIdentifier: String? { get { super.targetContentIdentifier } set { super.targetContentIdentifier = newValue } }
    open override var attachments: [UNNotificationAttachment] { get { super.attachments } set { super.attachments = newValue } }
    open override var interruptionLevel: UNNotificationInterruptionLevel { get { super.interruptionLevel } set { super.interruptionLevel = newValue } }
    open override var relevanceScore: Double { get { super.relevanceScore } set { super.relevanceScore = newValue } }
}

open class UNNotificationTrigger: NSObject, @unchecked Sendable {
    public let repeats: Bool
    init(repeats: Bool) { self.repeats = repeats; super.init() }
}
open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public init(timeInterval: TimeInterval, repeats: Bool) { self.timeInterval = timeInterval; super.init(repeats: repeats) }
    open func nextTriggerDate() -> Date? { Date(timeIntervalSinceNow: timeInterval) }
}
open class UNCalendarNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let dateComponents: DateComponents
    public init(dateMatching dateComponents: DateComponents, repeats: Bool) { self.dateComponents = dateComponents; super.init(repeats: repeats) }
    open func nextTriggerDate() -> Date? { Calendar.current.nextDate(after: Date(), matching: dateComponents, matchingPolicy: .nextTime) }
}
open class UNPushNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {}

open class UNNotificationRequest: NSObject, @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = (content.mutableCopy() as? UNNotificationContent) ?? content
        self.trigger = trigger
        super.init()
    }
}
open class UNNotification: NSObject, @unchecked Sendable {
    public let request: UNNotificationRequest
    public let date: Date
    init(request: UNNotificationRequest, date: Date) { self.request = request; self.date = date; super.init() }
}
open class UNNotificationResponse: NSObject, @unchecked Sendable {
    public let notification: UNNotification
    public let actionIdentifier: String
    init(notification: UNNotification, actionIdentifier: String) { self.notification = notification; self.actionIdentifier = actionIdentifier; super.init() }
}
open class UNTextInputNotificationResponse: UNNotificationResponse, @unchecked Sendable {
    open var userText: String { "" }
}

public struct UNNotificationActionOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1)
    public static let destructive = UNNotificationActionOptions(rawValue: 2)
    public static let foreground = UNNotificationActionOptions(rawValue: 4)
}
public struct UNNotificationCategoryOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1)
    public static let allowInCarPlay = UNNotificationCategoryOptions(rawValue: 2)
    public static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 4)
}
open class UNNotificationAction: NSObject, @unchecked Sendable {
    public let identifier: String
    public let title: String
    public let options: UNNotificationActionOptions
    public init(identifier: String, title: String, options: UNNotificationActionOptions = []) {
        self.identifier = identifier; self.title = title; self.options = options; super.init()
    }
}
open class UNTextInputNotificationAction: UNNotificationAction, @unchecked Sendable {
    public init(identifier: String, title: String, options: UNNotificationActionOptions = [], textInputButtonTitle: String, textInputPlaceholder: String) {
        super.init(identifier: identifier, title: title, options: options)
    }
}
open class UNNotificationCategory: NSObject, @unchecked Sendable {
    public let identifier: String
    public let actions: [UNNotificationAction]
    public init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.identifier = identifier; self.actions = actions; super.init()
    }
    public init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], hiddenPreviewsBodyPlaceholder: String,
                options: UNNotificationCategoryOptions = []) {
        self.identifier = identifier; self.actions = actions; super.init()
    }
}

/// Delegate methods are the app's own; nothing is delivered here to call them.
public protocol UNUserNotificationCenterDelegate: AnyObject {}

open class UNUserNotificationCenter: NSObject, @unchecked Sendable {
    private static let shared = UNUserNotificationCenter()
    open class func current() -> UNUserNotificationCenter { shared }
    open weak var delegate: UNUserNotificationCenterDelegate?
    open var supportsContentExtensions: Bool { false }
    private let lock = NSLock()
    private var pending: [UNNotificationRequest] = []
    private var categories: Set<UNNotificationCategory> = []

    /// Answered no: nobody is there to allow notifications.
    open func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, Error?) -> Void) {
        completionHandler(false, nil)
    }
    open func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool { false }
    open func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) { completionHandler(UNNotificationSettings()) }
    open func notificationSettings() async -> UNNotificationSettings { UNNotificationSettings() }

    open func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
        lock.lock()
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
        lock.unlock()
        completionHandler?(nil)
    }
    open func add(_ request: UNNotificationRequest) async throws { add(request, withCompletionHandler: nil) }
    open func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        lock.lock(); let list = pending; lock.unlock()
        completionHandler(list)
    }
    open func pendingNotificationRequests() async -> [UNNotificationRequest] { lock.withLock { pending } }
    open func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.lock(); pending.removeAll { identifiers.contains($0.identifier) }; lock.unlock()
    }
    open func removeAllPendingNotificationRequests() { lock.lock(); pending = []; lock.unlock() }
    open func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) { completionHandler([]) }
    open func deliveredNotifications() async -> [UNNotification] { [] }
    open func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    open func removeAllDeliveredNotifications() {}
    open func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { lock.lock(); self.categories = categories; lock.unlock() }
    open func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) { completionHandler(categories) }
    open func notificationCategories() async -> Set<UNNotificationCategory> { categories }
    open func setBadgeCount(_ newBadgeCount: Int, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func setBadgeCount(_ newBadgeCount: Int) async throws {}
}
