// `import ContactsUI`: the contact view controllers as shells (placeholders when wrapped).
@_exported import Contacts
import UIKit

public protocol CNContactViewControllerDelegate: AnyObject {}
public protocol CNContactPickerDelegate: AnyObject {}

open class CNContactViewController: UIViewController {
    public let contact: CNContact
    open var contactStore: CNContactStore?
    open weak var delegate: CNContactViewControllerDelegate?
    open var displayedPropertyKeys: [Any]?
    open var allowsEditing = true
    open var allowsActions = true
    open var shouldShowLinkedContacts = false
    open var alternateName: String?
    open var message: String?
    public init(for contact: CNContact) { self.contact = contact; super.init(nibName: nil, bundle: nil) }
    public init(forNewContact contact: CNContact?) { self.contact = contact ?? CNContact(); super.init(nibName: nil, bundle: nil) }
    public init(forUnknownContact contact: CNContact) { self.contact = contact; super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { contact = CNContact(); super.init(coder: coder) }
    public class func descriptorForRequiredKeys() -> CNKeyDescriptor { "all" }
}
open class CNContactPickerViewController: UIViewController {
    open weak var delegate: CNContactPickerDelegate?
    open var displayedPropertyKeys: [String]?
    open var predicateForEnablingContact: NSPredicate?
}
