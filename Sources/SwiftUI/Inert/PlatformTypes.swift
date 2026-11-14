// Types from Foundation, UniformTypeIdentifiers and CoreTransferable that SwiftUI APIs mention
// but that do not exist on Linux. They only need to exist as types so signatures compile.

// used by onDrag/onDrop/draggable/dropDestination/fileImporter/userActivity.
open class NSItemProvider: NSObject {
    public override init() { super.init() }
    public convenience init(object: Any) { self.init() }
}

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

// UTType is in the UniformTypeIdentifiers module, which SwiftUI re-exports.

// Foundation's FileWrapper is missing on Linux.
open class FileWrapper: NSObject {
    open var regularFileContents: Data?
    open var fileWrappers: [String: FileWrapper]?
    open var preferredFilename: String?
    public init(regularFileWithContents contents: Data) { regularFileContents = contents; super.init() }
    public init(directoryWithFileWrappers wrappers: [String: FileWrapper]) { fileWrappers = wrappers; super.init() }
}

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
