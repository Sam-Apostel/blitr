// `import Contacts`: the contact store of a fresh install (access not determined, requests answered no,
// no contacts) and the contact value types.
@_exported import Foundation

public enum CNAuthorizationStatus: Int, Sendable { case notDetermined, restricted, denied, authorized, limited }
public enum CNEntityType: Int, Sendable { case contacts }
public enum CNContactType: Int, Sendable { case person, organization }
public struct CNError: Error, Sendable {
    public enum Code: Int, Sendable { case communicationError = 1, dataAccessAuthorizationDenied = 100, authorizationDenied, recordDoesNotExist = 200 }
    public let code: Code
}

public let CNLabelHome = "_$!<Home>!$_"
public let CNLabelWork = "_$!<Work>!$_"
public let CNLabelSchool = "_$!<School>!$_"
public let CNLabelOther = "_$!<Other>!$_"
public let CNLabelEmailiCloud = "iCloud"
public let CNLabelURLAddressHomePage = "_$!<HomePage>!$_"
public let CNLabelPhoneNumberMobile = "_$!<Mobile>!$_"
public let CNLabelPhoneNumberiPhone = "iPhone"
public let CNLabelPhoneNumberMain = "_$!<Main>!$_"
public let CNContactGivenNameKey = "givenName"
public let CNContactFamilyNameKey = "familyName"
public let CNContactOrganizationNameKey = "organizationName"
public let CNContactEmailAddressesKey = "emailAddresses"
public let CNContactPhoneNumbersKey = "phoneNumbers"
public let CNContactImageDataKey = "imageData"
public let CNContactThumbnailImageDataKey = "thumbnailImageData"
public protocol CNKeyDescriptor {}
extension NSString: CNKeyDescriptor {}
extension String: CNKeyDescriptor {}

public final class CNLabeledValue<ValueType: NSObject>: NSObject, @unchecked Sendable {
    public let identifier = UUID().uuidString
    public let label: String?
    public let value: ValueType
    public init(label: String?, value: ValueType) { self.label = label; self.value = value; super.init() }
    public func settingLabel(_ label: String?) -> CNLabeledValue<ValueType> { CNLabeledValue(label: label, value: value) }
    public func settingValue(_ value: ValueType) -> CNLabeledValue<ValueType> { CNLabeledValue(label: label, value: value) }
    public class func localizedString(forLabel label: String) -> String {
        label.replacingOccurrences(of: "_$!<", with: "").replacingOccurrences(of: ">!$_", with: "").lowercased()
    }
}
public final class CNPhoneNumber: NSObject, @unchecked Sendable {
    public let stringValue: String
    public init(stringValue: String) { self.stringValue = stringValue; super.init() }
}
public final class CNPostalAddress: NSObject, @unchecked Sendable {
    public internal(set) var street = "", city = "", state = "", postalCode = "", country = "", isoCountryCode = ""
}
public final class CNMutablePostalAddress: NSObject, @unchecked Sendable {
    public var street = "", city = "", state = "", postalCode = "", country = "", isoCountryCode = ""
}

open class CNContact: NSObject, @unchecked Sendable {
    open internal(set) var identifier = UUID().uuidString
    open internal(set) var contactType = CNContactType.person
    open internal(set) var namePrefix = ""
    open internal(set) var givenName = ""
    open internal(set) var middleName = ""
    open internal(set) var familyName = ""
    open internal(set) var nameSuffix = ""
    open internal(set) var nickname = ""
    open internal(set) var organizationName = ""
    open internal(set) var departmentName = ""
    open internal(set) var jobTitle = ""
    open internal(set) var note = ""
    open internal(set) var imageData: Data?
    open internal(set) var thumbnailImageData: Data?
    open internal(set) var birthday: DateComponents?
    open internal(set) var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] = []
    open internal(set) var emailAddresses: [CNLabeledValue<NSString>] = []
    open internal(set) var urlAddresses: [CNLabeledValue<NSString>] = []
    open internal(set) var postalAddresses: [CNLabeledValue<CNPostalAddress>] = []
    public override init() { super.init() }
    open var imageDataAvailable: Bool { imageData != nil }
    open func isKeyAvailable(_ key: String) -> Bool { true }
    open func areKeysAvailable(_ keyDescriptors: [CNKeyDescriptor]) -> Bool { true }
}
open class CNMutableContact: CNContact, @unchecked Sendable {
    open override var contactType: CNContactType { get { super.contactType } set { super.contactType = newValue } }
    open override var namePrefix: String { get { super.namePrefix } set { super.namePrefix = newValue } }
    open override var givenName: String { get { super.givenName } set { super.givenName = newValue } }
    open override var middleName: String { get { super.middleName } set { super.middleName = newValue } }
    open override var familyName: String { get { super.familyName } set { super.familyName = newValue } }
    open override var nameSuffix: String { get { super.nameSuffix } set { super.nameSuffix = newValue } }
    open override var nickname: String { get { super.nickname } set { super.nickname = newValue } }
    open override var organizationName: String { get { super.organizationName } set { super.organizationName = newValue } }
    open override var departmentName: String { get { super.departmentName } set { super.departmentName = newValue } }
    open override var jobTitle: String { get { super.jobTitle } set { super.jobTitle = newValue } }
    open override var note: String { get { super.note } set { super.note = newValue } }
    open override var imageData: Data? { get { super.imageData } set { super.imageData = newValue } }
    open override var birthday: DateComponents? { get { super.birthday } set { super.birthday = newValue } }
    open override var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] { get { super.phoneNumbers } set { super.phoneNumbers = newValue } }
    open override var emailAddresses: [CNLabeledValue<NSString>] { get { super.emailAddresses } set { super.emailAddresses = newValue } }
    open override var urlAddresses: [CNLabeledValue<NSString>] { get { super.urlAddresses } set { super.urlAddresses = newValue } }
    open override var postalAddresses: [CNLabeledValue<CNPostalAddress>] { get { super.postalAddresses } set { super.postalAddresses = newValue } }
}

open class CNContactFormatter: NSObject, @unchecked Sendable {
    public enum Style: Int, Sendable { case fullName, phoneticFullName }
    public class func string(from contact: CNContact, style: Style) -> String? {
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (contact.organizationName.isEmpty ? nil : contact.organizationName) : name
    }
    public class func descriptorForRequiredKeys(for style: Style) -> CNKeyDescriptor { "fullName" }
    open func string(from contact: CNContact) -> String? { CNContactFormatter.string(from: contact, style: .fullName) }
}

open class CNSaveRequest: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open func add(_ contact: CNMutableContact, toContainerWithIdentifier identifier: String?) {}
    open func update(_ contact: CNMutableContact) {}
    open func delete(_ contact: CNMutableContact) {}
}
open class CNContactFetchRequest: NSObject, @unchecked Sendable {
    public init(keysToFetch: [CNKeyDescriptor]) { super.init() }
}

open class CNContactStore: NSObject, @unchecked Sendable {
    public static let didChangeNotification = Notification.Name("CNContactStoreDidChangeNotification")
    public class func authorizationStatus(for entityType: CNEntityType) -> CNAuthorizationStatus { .notDetermined }
    public override init() { super.init() }
    /// Answered no.
    open func requestAccess(for entityType: CNEntityType, completionHandler: @escaping (Bool, Error?) -> Void) { completionHandler(false, nil) }
    open func requestAccess(for entityType: CNEntityType) async throws -> Bool { false }
    open func unifiedContacts(matching predicate: NSPredicate, keysToFetch keys: [CNKeyDescriptor]) throws -> [CNContact] {
        throw CNError(code: .authorizationDenied)
    }
    open func unifiedContact(withIdentifier identifier: String, keysToFetch keys: [CNKeyDescriptor]) throws -> CNContact {
        throw CNError(code: .authorizationDenied)
    }
    open func enumerateContacts(with fetchRequest: CNContactFetchRequest, usingBlock block: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        throw CNError(code: .authorizationDenied)
    }
    open func execute(_ saveRequest: CNSaveRequest) throws { throw CNError(code: .authorizationDenied) }
    open func defaultContainerIdentifier() -> String { "local" }
}
