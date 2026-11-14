// `import CoreSpotlight`: indexing succeeds and stores nothing; searching finds nothing.
@_exported import Foundation
@_exported import UniformTypeIdentifiers

public let CSSearchableItemActionType = "com.apple.corespotlightitem"
public let CSSearchableItemActivityIdentifier = "kCSSearchableItemActivityIdentifier"
public let CSQueryContinuationActionType = "com.apple.corespotlightquerycontinuation"
public let CSSearchQueryString = "kCSSearchQueryString"

open class CSSearchableItemAttributeSet: NSObject, @unchecked Sendable {
    public let contentType: String
    open var title: String?
    open var displayName: String?
    open var alternateNames: [String]?
    open var contentDescription: String?
    open var keywords: [String]?
    open var thumbnailData: Data?
    open var thumbnailURL: URL?
    open var contentURL: URL?
    open var url: URL?
    open var startDate: Date?
    open var endDate: Date?
    open var contentCreationDate: Date?
    open var contentModificationDate: Date?
    open var latitude: NSNumber?
    open var longitude: NSNumber?
    open var namedLocation: String?
    open var city: String?
    open var country: String?
    open var phoneNumbers: [String]?
    open var emailAddresses: [String]?
    open var rankingHint: NSNumber?
    open var domainIdentifier: String?
    open var relatedUniqueIdentifier: String?
    public init(contentType: UTType) { self.contentType = contentType.identifier; super.init() }
    public init(itemContentType: String) { contentType = itemContentType; super.init() }
}

open class CSSearchableItem: NSObject, @unchecked Sendable {
    open var uniqueIdentifier: String
    open var domainIdentifier: String?
    open var attributeSet: CSSearchableItemAttributeSet
    open var expirationDate: Date!
    public init(uniqueIdentifier: String?, domainIdentifier: String?, attributeSet: CSSearchableItemAttributeSet) {
        self.uniqueIdentifier = uniqueIdentifier ?? UUID().uuidString
        self.domainIdentifier = domainIdentifier
        self.attributeSet = attributeSet
        super.init()
    }
}

open class CSSearchableIndex: NSObject, @unchecked Sendable {
    private static let shared = CSSearchableIndex()
    open class func `default`() -> CSSearchableIndex { shared }
    open class func isIndexingAvailable() -> Bool { true }
    public override init() { super.init() }
    public init(name: String) { super.init() }
    open func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String], completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)? = nil) { completionHandler?(nil) }
    open func indexSearchableItems(_ items: [CSSearchableItem]) async throws {}
    open func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {}
    open func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {}
    open func deleteAllSearchableItems() async throws {}
}

open class CSSearchQuery: NSObject, @unchecked Sendable {
    open var foundItemsHandler: (([CSSearchableItem]) -> Void)?
    open var completionHandler: ((Error?) -> Void)?
    public init(queryString: String, attributes: [String]?) { super.init() }
    open func start() { completionHandler?(nil) }
    open func cancel() {}
}
