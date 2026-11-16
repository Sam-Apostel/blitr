// Types from Foundation, UniformTypeIdentifiers and CoreTransferable that SwiftUI APIs mention
// but that do not exist on Linux. They only need to exist as types so signatures compile.

// used by onDrag/onDrop/draggable/dropDestination/fileImporter/userActivity.
open class NSItemProvider: NSObject {
    public typealias CompletionHandler = (NSSecureCoding?, Error?) -> Void
    /// Registered representations (type identifier -> value); a provider made here holds what it was given.
    private var items: [String: Any] = [:]
    public override init() { super.init() }
    public convenience init(object: Any) {
        self.init()
        if let s = object as? String { items[UTType.plainText.identifier] = s }
        if let u = object as? URL { items[UTType.url.identifier] = u }
    }
    public convenience init(item: NSSecureCoding?, typeIdentifier: String?) {
        self.init()
        if let item, let typeIdentifier { items[typeIdentifier] = item }
    }
    public convenience init?(contentsOf fileURL: URL) {
        self.init()
        items[UTType.fileURL.identifier] = fileURL
    }
    open var registeredTypeIdentifiers: [String] { Array(items.keys) }
    open var suggestedName: String?
    open func registeredContentTypes(conformingTo contentType: UTType) -> [UTType] {
        items.keys.compactMap { UTType($0) }.filter { $0.conforms(to: contentType) }
    }
    open func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        let wanted = UTType(typeIdentifier)
        return items.keys.contains { $0 == typeIdentifier || (wanted != nil && UTType($0)?.conforms(to: wanted!) == true) }
    }
    open func hasRepresentationConforming(toTypeIdentifier typeIdentifier: String, fileOptions: Int = 0) -> Bool {
        hasItemConformingToTypeIdentifier(typeIdentifier)
    }
    open func registerDataRepresentation(forTypeIdentifier typeIdentifier: String, visibility: Int = 0,
                                         loadHandler: @escaping (@escaping (Data?, Error?) -> Void) -> Progress?) {}
    open func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: CompletionHandler? = nil) {
        completionHandler?(items[typeIdentifier] as? NSSecureCoding, nil)
    }
    open func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil) async throws -> NSSecureCoding {
        guard let item = items[typeIdentifier] as? NSSecureCoding else { throw CocoaError(.fileReadNoSuchFile) }
        return item
    }
    @discardableResult
    open func loadDataRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping (Data?, Error?) -> Void) -> Progress {
        completionHandler(items[typeIdentifier] as? Data, nil)
        return Progress(totalUnitCount: 0)
    }
    @discardableResult
    open func loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping (URL?, Error?) -> Void) -> Progress {
        completionHandler(items[typeIdentifier] as? URL, nil)
        return Progress(totalUnitCount: 0)
    }
    @discardableResult
    open func loadInPlaceFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping (URL?, Bool, Error?) -> Void) -> Progress {
        completionHandler(items[typeIdentifier] as? URL, false, nil)
        return Progress(totalUnitCount: 0)
    }
    open func canLoadObject(ofClass aClass: Any.Type) -> Bool { false }
    @discardableResult
    open func loadFileRepresentation(for contentType: UTType, openInPlace: Bool = false,
                                     completionHandler: @escaping (URL?, Bool, Error?) -> Void) -> Progress {
        loadInPlaceFileRepresentation(forTypeIdentifier: contentType.identifier, completionHandler: completionHandler)
    }
    @discardableResult
    open func loadDataRepresentation(for contentType: UTType, completionHandler: @escaping (Data?, Error?) -> Void) -> Progress {
        loadDataRepresentation(forTypeIdentifier: contentType.identifier, completionHandler: completionHandler)
    }
}

// Foundation's NSUserActivity is missing on Linux; on a Mac, Foundation's own is used (redeclaring it made
// `NSUserActivityTypeBrowsingWeb` ambiguous in apps that continue web activities).
#if !canImport(Darwin)
public let NSUserActivityTypeBrowsingWeb = "NSUserActivityTypeBrowsingWeb"

open class NSUserActivity: NSObject {
    public let activityType: String
    open var title: String?
    open var userInfo: [AnyHashable: Any]?
    open var webpageURL: URL?
    open var isEligibleForHandoff = true
    open var isEligibleForSearch = false
    open var isEligibleForPrediction = false
    open var targetContentIdentifier: String?
    public init(activityType: String) { self.activityType = activityType; super.init() }
    open func addUserInfoEntries(from other: [AnyHashable: Any]) {}
}
#endif

// UTType is in the UniformTypeIdentifiers module, which SwiftUI re-exports.

// Foundation's FileWrapper is missing on Linux.
#if !canImport(Darwin)
open class FileWrapper: NSObject {
    open var regularFileContents: Data?
    open var fileWrappers: [String: FileWrapper]?
    open var preferredFilename: String?
    public init(regularFileWithContents contents: Data) { regularFileContents = contents; super.init() }
    public init(directoryWithFileWrappers wrappers: [String: FileWrapper]) { fileWrappers = wrappers; super.init() }
}
#endif

// Document types used by fileExporter / fileImporter (DocumentGroup would also use them).
public struct FileDocumentReadConfiguration {
    public let contentType: UTType
    public let file: FileWrapper
}
public struct FileDocumentWriteConfiguration {
    public let contentType: UTType
    public let existingFile: FileWrapper?
}
public protocol FileDocument {
    static var readableContentTypes: [UTType] { get }
    static var writableContentTypes: [UTType] { get }
    init(configuration: FileDocumentReadConfiguration) throws
    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper
}
extension FileDocument {
    public static var writableContentTypes: [UTType] { readableContentTypes }
}
