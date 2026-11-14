// `import EventKitUI`: the calendar view controllers as shells (placeholders when wrapped).
@_exported import EventKit
import UIKit

public enum EKCalendarChooserSelectionStyle: Int, Sendable { case single, multiple }
public enum EKCalendarChooserDisplayStyle: Int, Sendable { case allCalendars, writableCalendarsOnly }
public enum EKEventEditViewAction: Int, Sendable { case canceled, saved, deleted }
public enum EKEventViewAction: Int, Sendable { case done, responded, deleted }

open class EKCalendarChooser: UIViewController {
    open weak var delegate: EKCalendarChooserDelegate?
    open var selectedCalendars: Set<EKCalendar> = []
    open var showsDoneButton = false
    open var showsCancelButton = false
    open var selectionStyle: EKCalendarChooserSelectionStyle { .single }
    public init(selectionStyle: EKCalendarChooserSelectionStyle, displayStyle: EKCalendarChooserDisplayStyle, eventStore: EKEventStore) {
        super.init(nibName: nil, bundle: nil)
    }
    public init(selectionStyle: EKCalendarChooserSelectionStyle, displayStyle: EKCalendarChooserDisplayStyle, entityType: EKEntityType, eventStore: EKEventStore) {
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
public protocol EKCalendarChooserDelegate: AnyObject {}

open class EKEventEditViewController: UINavigationController {
    open weak var editViewDelegate: EKEventEditViewDelegate?
    open var eventStore: EKEventStore!
    open var event: EKEvent?
    open func cancelEditing() {}
}
public protocol EKEventEditViewDelegate: AnyObject {}
open class EKEventViewController: UIViewController {
    open var event: EKEvent!
    open var allowsEditing = false
    open var allowsCalendarPreview = false
    open weak var delegate: AnyObject?
}
