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

public struct UTType: Hashable, Sendable {
    public let identifier: String
    public init?(_ identifier: String) { self.identifier = identifier }
    public init?(filenameExtension: String) { identifier = "public.\(filenameExtension)" }
    public init?(mimeType: String) { identifier = mimeType }
    public init(importedAs identifier: String) { self.identifier = identifier }
    public init(exportedAs identifier: String) { self.identifier = identifier }
    public static let item = UTType(importedAs: "public.item")
    public static let content = UTType(importedAs: "public.content")
    public static let data = UTType(importedAs: "public.data")
    public static let text = UTType(importedAs: "public.text")
    public static let plainText = UTType(importedAs: "public.plain-text")
    public static let utf8PlainText = UTType(importedAs: "public.utf8-plain-text")
    public static let commaSeparatedText = UTType(importedAs: "public.comma-separated-values-text")
    public static let json = UTType(importedAs: "public.json")
    public static let xml = UTType(importedAs: "public.xml")
    public static let html = UTType(importedAs: "public.html")
    public static let url = UTType(importedAs: "public.url")
    public static let fileURL = UTType(importedAs: "public.file-url")
    public static let image = UTType(importedAs: "public.image")
    public static let png = UTType(importedAs: "public.png")
    public static let jpeg = UTType(importedAs: "public.jpeg")
    public static let gif = UTType(importedAs: "com.compuserve.gif")
    public static let heic = UTType(importedAs: "public.heic")
    public static let pdf = UTType(importedAs: "com.adobe.pdf")
    public static let movie = UTType(importedAs: "public.movie")
    public static let audio = UTType(importedAs: "public.audio")
    public static let folder = UTType(importedAs: "public.folder")
    public static let zip = UTType(importedAs: "public.zip-archive")
}

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
