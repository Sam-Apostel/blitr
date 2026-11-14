// `import EventKit`: the calendar store of a fresh install. Access is not determined, requests for it
// are answered no, and there are no calendars or events. Events and reminders are value records.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import CoreLocation

public enum EKEntityType: UInt, Sendable { case event, reminder }
public struct EKEntityMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let event = EKEntityMask(rawValue: 1)
    public static let reminder = EKEntityMask(rawValue: 2)
}
public enum EKAuthorizationStatus: Int, Sendable {
    case notDetermined, restricted, denied, fullAccess, writeOnly
    @available(*, deprecated, renamed: "fullAccess")
    public static var authorized: EKAuthorizationStatus { .fullAccess }
}
public enum EKSpan: Int, Sendable { case thisEvent, futureEvents }
public enum EKCalendarType: Int, Sendable { case local, calDAV, exchange, subscription, birthday }
public enum EKSourceType: Int, Sendable { case local, exchange, calDAV, mobileMe, subscribed, birthdays }
public enum EKEventAvailability: Int, Sendable { case notSupported = -1, busy, free, tentative, unavailable }
public enum EKEventStatus: Int, Sendable { case none, confirmed, tentative, canceled }
public enum EKErrorCode: Int, Sendable { case eventNotMutable, noCalendar, noStartDate, noEndDate, datesInverted, internalFailure, calendarReadOnly }
public struct EKError: Error, Sendable { public let code: EKErrorCode }

open class EKObject: NSObject, @unchecked Sendable {
    open var hasChanges: Bool { true }
    open var isNew: Bool { true }
    open func reset() {}
    open func rollback() {}
    open func refresh() -> Bool { true }
}

open class EKSource: EKObject, @unchecked Sendable {
    open var sourceIdentifier: String = UUID().uuidString
    open var sourceType = EKSourceType.local
    open var title = "On My iPhone"
    open func calendars(for entityType: EKEntityType) -> Set<EKCalendar> { [] }
}

open class EKCalendar: EKObject, @unchecked Sendable {
    open var calendarIdentifier: String = UUID().uuidString
    open var title = ""
    open var type = EKCalendarType.local
    open var allowsContentModifications = true
    open var isSubscribed = false
    open var isImmutable = false
    open var cgColor: CGColor! = CGColor(srgbRed: 0.2, green: 0.5, blue: 0.95, alpha: 1)
    open var source: EKSource!
    open var allowedEntityTypes: EKEntityMask = .event
    public init(for entityType: EKEntityType, eventStore: EKEventStore) { super.init() }
}

open class EKStructuredLocation: EKObject, @unchecked Sendable {
    open var title: String?
    open var geoLocation: CLLocation?
    open var radius: Double = 0
    public init(title: String) { self.title = title; super.init() }
    public init(mapItem: AnyObject) { super.init() }
}

open class EKAlarm: EKObject, @unchecked Sendable {
    open var relativeOffset: TimeInterval = 0
    open var absoluteDate: Date?
    public init(relativeOffset offset: TimeInterval) { relativeOffset = offset; super.init() }
    public init(absoluteDate date: Date) { absoluteDate = date; super.init() }
}
open class EKRecurrenceRule: EKObject, @unchecked Sendable {}

open class EKCalendarItem: EKObject, @unchecked Sendable {
    open var calendarItemIdentifier: String = UUID().uuidString
    open var calendarItemExternalIdentifier: String!
    open var calendar: EKCalendar!
    open var title: String! = ""
    open var location: String?
    open var notes: String?
    open var url: URL?
    open var timeZone: TimeZone?
    open var creationDate: Date?
    open var lastModifiedDate: Date?
    open var alarms: [EKAlarm]?
    open var recurrenceRules: [EKRecurrenceRule]?
    open var hasAlarms: Bool { !(alarms ?? []).isEmpty }
    open var hasNotes: Bool { notes != nil }
    open var hasRecurrenceRules: Bool { !(recurrenceRules ?? []).isEmpty }
    open func addAlarm(_ alarm: EKAlarm) { alarms = (alarms ?? []) + [alarm] }
    open func removeAlarm(_ alarm: EKAlarm) { alarms?.removeAll { $0 === alarm } }
    open func addRecurrenceRule(_ rule: EKRecurrenceRule) { recurrenceRules = (recurrenceRules ?? []) + [rule] }
}

open class EKEvent: EKCalendarItem, @unchecked Sendable {
    open var eventIdentifier: String! { calendarItemIdentifier }
    open var startDate: Date! = Date()
    open var endDate: Date! = Date()
    open var isAllDay = false
    open var structuredLocation: EKStructuredLocation?
    open var availability = EKEventAvailability.busy
    open var status: EKEventStatus { .none }
    open var occurrenceDate: Date! { startDate }
    open var isDetached: Bool { false }
    public init(eventStore: EKEventStore) { super.init() }
    open func compareStartDate(with other: EKEvent) -> ComparisonResult { startDate.compare(other.startDate) }
}
open class EKReminder: EKCalendarItem, @unchecked Sendable {
    open var isCompleted = false
    open var completionDate: Date?
    open var dueDateComponents: DateComponents?
    open var startDateComponents: DateComponents?
    open var priority = 0
    public init(eventStore: EKEventStore) { super.init() }
}


open class EKEventStore: NSObject, @unchecked Sendable {
    public static let changedNotification = Notification.Name("EKEventStoreChangedNotification")
    public class func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus { .notDetermined }
    public override init() { super.init() }
    public init(sources: [EKSource]) { super.init() }

    open var eventStoreIdentifier: String { "local" }
    open var sources: [EKSource] { [] }
    open var delegateSources: [EKSource] { [] }
    open var defaultCalendarForNewEvents: EKCalendar? { nil }
    open func defaultCalendarForNewReminders() -> EKCalendar? { nil }

    /// Answered no.
    open func requestFullAccessToEvents() async throws -> Bool { false }
    open func requestFullAccessToEvents(completion: @escaping (Bool, Error?) -> Void) { completion(false, nil) }
    open func requestWriteOnlyAccessToEvents() async throws -> Bool { false }
    open func requestWriteOnlyAccessToEvents(completion: @escaping (Bool, Error?) -> Void) { completion(false, nil) }
    open func requestFullAccessToReminders() async throws -> Bool { false }
    open func requestFullAccessToReminders(completion: @escaping (Bool, Error?) -> Void) { completion(false, nil) }
    open func requestAccess(to entityType: EKEntityType) async throws -> Bool { false }
    open func requestAccess(to entityType: EKEntityType, completion: @escaping (Bool, Error?) -> Void) { completion(false, nil) }

    open func calendars(for entityType: EKEntityType) -> [EKCalendar] { [] }
    open func calendar(withIdentifier identifier: String) -> EKCalendar? { nil }
    open func event(withIdentifier identifier: String) -> EKEvent? { nil }
    open func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? { nil }
    open func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?) -> NSPredicate { NSPredicate(value: false) }
    open func predicateForReminders(in calendars: [EKCalendar]?) -> NSPredicate { NSPredicate(value: false) }
    open func events(matching predicate: NSPredicate) -> [EKEvent] { [] }
    open func enumerateEvents(matching predicate: NSPredicate, using block: (EKEvent, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    open func fetchReminders(matching predicate: NSPredicate, completion: @escaping ([EKReminder]?) -> Void) -> Any { completion([]); return 0 }

    /// Without access nothing can be written: these throw, as EventKit does.
    open func save(_ event: EKEvent, span: EKSpan, commit: Bool = true) throws { throw EKError(code: .noCalendar) }
    open func save(_ event: EKEvent, span: EKSpan) throws { throw EKError(code: .noCalendar) }
    open func remove(_ event: EKEvent, span: EKSpan, commit: Bool = true) throws { throw EKError(code: .noCalendar) }
    open func remove(_ event: EKEvent, span: EKSpan) throws { throw EKError(code: .noCalendar) }
    open func save(_ reminder: EKReminder, commit: Bool) throws { throw EKError(code: .noCalendar) }
    open func remove(_ reminder: EKReminder, commit: Bool) throws { throw EKError(code: .noCalendar) }
    open func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws { throw EKError(code: .noCalendar) }
    open func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws { throw EKError(code: .noCalendar) }
    open func commit() throws {}
    open func reset() {}
    open func refreshSourcesIfNecessary() {}
}
