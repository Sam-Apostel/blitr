// `import UniformTypeIdentifiers`: UTType with the system's declared types, their tags (filename extensions,
// MIME types) and conformance. SwiftUI depends on this module and re-exports it (fileImporter, onDrop, ...).
@_exported import Foundation

public struct UTTagClass: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let filenameExtension = UTTagClass(rawValue: "public.filename-extension")
    public static let mimeType = UTTagClass(rawValue: "public.mime-type")
}

public struct UTType: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public let identifier: String
    /// Declared parents of a type not in the system table (`exportedAs:conformingTo:`).
    private let declaredParents: [String]
    private let declaredExtension: String?

    init(known identifier: String) { self.identifier = identifier; declaredParents = []; declaredExtension = nil }
    init(identifier: String, parents: [String], filenameExtension: String? = nil) {
        self.identifier = identifier; declaredParents = parents; declaredExtension = filenameExtension
    }

    /// A known (system-declared) type, or nil.
    public init?(_ identifier: String) {
        guard UTType.table[identifier.lowercased()] != nil || UTType.table[identifier] != nil else { return nil }
        self.init(known: UTType.table[identifier] != nil ? identifier : identifier.lowercased())
    }
    public init?(filenameExtension: String) { self.init(filenameExtension: filenameExtension, conformingTo: .data) }
    public init?(filenameExtension: String, conformingTo supertype: UTType) {
        let ext = filenameExtension.lowercased()
        if let match = UTType.table.first(where: { $0.value.extensions.contains(ext) && UTType(known: $0.key).conforms(to: supertype) }) {
            self.init(known: match.key)
        } else {
            self.init(identifier: "dyn.ext." + ext, parents: [supertype.identifier], filenameExtension: ext)
        }
    }
    public init?(mimeType: String) { self.init(mimeType: mimeType, conformingTo: .data) }
    public init?(mimeType: String, conformingTo supertype: UTType) {
        let mime = mimeType.lowercased()
        guard let match = UTType.table.first(where: { $0.value.mimes.contains(mime) }) else { return nil }
        self.init(known: match.key)
    }
    public init?(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) {
        if tagClass == .filenameExtension { self.init(filenameExtension: tag, conformingTo: supertype ?? .data) }
        else if tagClass == .mimeType { self.init(mimeType: tag, conformingTo: supertype ?? .data) }
        else { return nil }
    }
    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
        self.init(identifier: identifier, parents: parentType.map { [$0.identifier] } ?? ["public.data"])
    }
    public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
        self.init(identifier: identifier, parents: parentType.map { [$0.identifier] } ?? ["public.data"])
    }

    static let table: [String: (parents: [String], extensions: [String], mimes: [String])] = [
        "public.item": ([], [], []),
        "public.content": ([], [], []),
        "public.composite-content": (["public.content"], [], []),
        "public.data": (["public.item"], [], ["application/octet-stream"]),
        "public.directory": (["public.item"], [], []),
        "public.folder": (["public.directory"], [], []),
        "public.volume": (["public.folder"], [], []),
        "com.apple.package": (["public.directory"], [], []),
        "com.apple.bundle": (["public.directory"], [], []),
        "com.apple.application": (["public.data"], [], []),
        "com.apple.application-bundle": (["com.apple.application", "com.apple.bundle", "com.apple.package"], ["app"], []),
        "public.symlink": (["public.item"], [], []),
        "com.apple.alias-file": (["public.data"], [], []),
        "public.url": (["public.data"], [], []),
        "public.file-url": (["public.url"], [], []),
        "com.apple.bookmark": (["public.data"], [], []),
        "public.text": (["public.data", "public.content"], [], ["text/plain"]),
        "public.plain-text": (["public.text"], ["txt", "text"], ["text/plain"]),
        "public.utf8-plain-text": (["public.plain-text"], [], ["text/plain;charset=utf-8"]),
        "public.utf16-plain-text": (["public.plain-text"], [], []),
        "public.utf16-external-plain-text": (["public.plain-text"], [], []),
        "public.utf8-tab-separated-values-text": (["public.tab-separated-values-text"], [], []),
        "public.tab-separated-values-text": (["public.delimited-values-text"], ["tsv"], ["text/tab-separated-values"]),
        "public.delimited-values-text": (["public.text"], [], []),
        "public.comma-separated-values-text": (["public.delimited-values-text"], ["csv"], ["text/csv"]),
        "public.rtf": (["public.text"], ["rtf"], ["text/rtf"]),
        "public.html": (["public.text"], ["html", "htm"], ["text/html"]),
        "public.xml": (["public.text"], ["xml"], ["application/xml", "text/xml"]),
        "public.yaml": (["public.text"], ["yaml", "yml"], ["application/x-yaml"]),
        "public.source-code": (["public.plain-text"], [], []),
        "public.swift-source": (["public.source-code"], ["swift"], []),
        "public.script": (["public.source-code"], [], []),
        "com.netscape.javascript-source": (["public.script"], ["js"], ["text/javascript"]),
        "public.shell-script": (["public.script"], ["sh"], ["application/x-sh"]),
        "public.python-script": (["public.script"], ["py"], ["text/x-python-script"]),
        "public.json": (["public.text"], ["json"], ["application/json"]),
        "com.apple.property-list": (["public.data"], ["plist"], []),
        "com.apple.xml-property-list": (["public.xml", "com.apple.property-list"], [], []),
        "com.apple.binary-property-list": (["com.apple.property-list"], [], []),
        "com.adobe.pdf": (["public.data", "public.composite-content"], ["pdf"], ["application/pdf"]),
        "com.apple.rtfd": (["com.apple.package", "public.composite-content"], ["rtfd"], []),
        "com.apple.flat-rtfd": (["public.data", "public.composite-content"], [], []),
        "com.apple.webarchive": (["public.data", "public.composite-content"], ["webarchive"], ["application/x-webarchive"]),
        "public.image": (["public.data", "public.content"], [], []),
        "public.jpeg": (["public.image"], ["jpeg", "jpg", "jpe"], ["image/jpeg"]),
        "public.png": (["public.image"], ["png"], ["image/png"]),
        "com.compuserve.gif": (["public.image"], ["gif"], ["image/gif"]),
        "public.tiff": (["public.image"], ["tiff", "tif"], ["image/tiff"]),
        "com.microsoft.bmp": (["public.image"], ["bmp"], ["image/bmp"]),
        "com.microsoft.ico": (["public.image"], ["ico"], ["image/vnd.microsoft.icon"]),
        "com.apple.icns": (["public.image"], ["icns"], []),
        "public.svg-image": (["public.image"], ["svg"], ["image/svg+xml"]),
        "public.camera-raw-image": (["public.image"], [], []),
        "com.apple.live-photo": (["public.data"], [], []),
        "public.heic": (["public.heif-standard"], ["heic"], ["image/heic"]),
        "public.heif": (["public.heif-standard"], ["heif"], ["image/heif"]),
        "org.webmproject.webp": (["public.image"], ["webp"], ["image/webp"]),
        "public.audiovisual-content": (["public.data", "public.content"], [], []),
        "public.movie": (["public.audiovisual-content"], [], []),
        "public.video": (["public.movie"], [], []),
        "public.audio": (["public.audiovisual-content"], [], []),
        "com.apple.quicktime-movie": (["public.movie"], ["mov", "qt"], ["video/quicktime"]),
        "public.mpeg": (["public.movie"], ["mpg", "mpeg"], ["video/mpeg"]),
        "public.mpeg-4": (["public.movie"], ["mp4", "mp4v"], ["video/mp4"]),
        "public.mpeg-4-audio": (["public.mpeg-4", "public.audio"], ["m4a"], ["audio/mp4"]),
        "com.apple.protected-mpeg-4-audio": (["public.audio"], ["m4p"], []),
        "public.mp3": (["public.audio"], ["mp3"], ["audio/mpeg"]),
        "com.microsoft.waveform-audio": (["public.audio"], ["wav"], ["audio/wav"]),
        "public.aiff-audio": (["public.audio"], ["aiff", "aif"], ["audio/aiff"]),
        "public.archive": (["public.data"], [], []),
        "public.zip-archive": (["public.archive"], ["zip"], ["application/zip"]),
        "org.gnu.gnu-zip-archive": (["public.archive"], ["gz"], ["application/gzip"]),
        "public.bzip2-archive": (["public.archive"], ["bz2"], ["application/x-bzip2"]),
        "com.apple.archive": (["public.archive"], ["aar"], []),
        "public.spreadsheet": (["public.content"], [], []),
        "public.presentation": (["public.composite-content"], [], []),
        "public.database": (["public.data"], [], []),
        "public.message": (["public.item"], [], []),
        "com.apple.mail.email": (["public.message"], ["eml"], ["message/rfc822"]),
        "public.contact": (["public.item"], [], []),
        "public.vcard": (["public.text", "public.contact"], ["vcf", "vcard"], ["text/vcard"]),
        "public.calendar-event": (["public.item"], [], []),
        "public.to-do-item": (["public.item"], [], []),
        "com.apple.ical.ics": (["public.data", "public.calendar-event"], ["ics"], ["text/calendar"]),
        "com.apple.internet-location": (["public.data"], [], []),
        "public.executable": (["public.item"], [], []),
        "public.font": (["public.data", "public.content"], [], []),
        "org.idpf.epub-container": (["public.data", "public.composite-content"], ["epub"], ["application/epub+zip"]),
        "public.log": (["public.plain-text"], ["log"], []),
        "com.pixar.universal-scene-description-mobile": (["public.data"], ["usdz"], ["model/vnd.usdz+zip"]),
        "public.3d-content": (["public.content"], [], []),
        "com.apple.pkpass": (["public.data"], ["pkpass"], ["application/vnd.apple.pkpass"]),
        "public.heif-standard": (["public.image"], [], []),
        "public.opentype-font": (["public.font"], ["otf"], ["font/otf"]),
        "public.truetype-ttf-font": (["public.font"], ["ttf"], ["font/ttf"]),
    ]

    private var parents: [String] { UTType.table[identifier]?.parents ?? declaredParents }
    public var supertypes: Set<UTType> {
        var result: Set<UTType> = []
        var queue = parents
        while let next = queue.popLast() {
            let t = UTType(known: next)
            if result.insert(t).inserted { queue += UTType.table[next]?.parents ?? [] }
        }
        return result
    }
    public func conforms(to type: UTType) -> Bool { self == type || supertypes.contains(type) }
    public func isSupertype(of type: UTType) -> Bool { type.conforms(to: self) }
    public func isSubtype(of type: UTType) -> Bool { self != type && conforms(to: type) }
    public var preferredFilenameExtension: String? { UTType.table[identifier]?.extensions.first ?? declaredExtension }
    public var preferredMIMEType: String? { UTType.table[identifier]?.mimes.first }
    public var tags: [UTTagClass: [String]] {
        var result: [UTTagClass: [String]] = [:]
        if let e = UTType.table[identifier]?.extensions, !e.isEmpty { result[.filenameExtension] = e }
        if let m = UTType.table[identifier]?.mimes, !m.isEmpty { result[.mimeType] = m }
        return result
    }
    public var isDeclared: Bool { UTType.table[identifier] != nil || !declaredParents.isEmpty }
    public var isDynamic: Bool { identifier.hasPrefix("dyn.") }
    public var isPublic: Bool { identifier.hasPrefix("public.") }
    public var isSystemDeclared: Bool { UTType.table[identifier] != nil }
    public var localizedDescription: String? { identifier }
    public var description: String { identifier }
    public var debugDescription: String { identifier }
    public static func == (a: UTType, b: UTType) -> Bool { a.identifier == b.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
    public init(from decoder: Decoder) throws { self.init(known: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(identifier) }
    public static func types(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) -> [UTType] {
        UTType(tag: tag, tagClass: tagClass, conformingTo: supertype).map { [$0] } ?? []
    }

    public static let item = UTType(known: "public.item")
    public static let content = UTType(known: "public.content")
    public static let compositeContent = UTType(known: "public.composite-content")
    public static let data = UTType(known: "public.data")
    public static let directory = UTType(known: "public.directory")
    public static let folder = UTType(known: "public.folder")
    public static let volume = UTType(known: "public.volume")
    public static let package = UTType(known: "com.apple.package")
    public static let bundle = UTType(known: "com.apple.bundle")
    public static let application = UTType(known: "com.apple.application")
    public static let applicationBundle = UTType(known: "com.apple.application-bundle")
    public static let symbolicLink = UTType(known: "public.symlink")
    public static let aliasFile = UTType(known: "com.apple.alias-file")
    public static let url = UTType(known: "public.url")
    public static let fileURL = UTType(known: "public.file-url")
    public static let urlBookmarkData = UTType(known: "com.apple.bookmark")
    public static let text = UTType(known: "public.text")
    public static let plainText = UTType(known: "public.plain-text")
    public static let utf8PlainText = UTType(known: "public.utf8-plain-text")
    public static let utf16PlainText = UTType(known: "public.utf16-plain-text")
    public static let utf16ExternalPlainText = UTType(known: "public.utf16-external-plain-text")
    public static let utf8TabSeparatedText = UTType(known: "public.utf8-tab-separated-values-text")
    public static let tabSeparatedText = UTType(known: "public.tab-separated-values-text")
    public static let delimitedText = UTType(known: "public.delimited-values-text")
    public static let commaSeparatedText = UTType(known: "public.comma-separated-values-text")
    public static let rtf = UTType(known: "public.rtf")
    public static let html = UTType(known: "public.html")
    public static let xml = UTType(known: "public.xml")
    public static let yaml = UTType(known: "public.yaml")
    public static let sourceCode = UTType(known: "public.source-code")
    public static let swiftSource = UTType(known: "public.swift-source")
    public static let script = UTType(known: "public.script")
    public static let javaScript = UTType(known: "com.netscape.javascript-source")
    public static let shellScript = UTType(known: "public.shell-script")
    public static let pythonScript = UTType(known: "public.python-script")
    public static let json = UTType(known: "public.json")
    public static let propertyList = UTType(known: "com.apple.property-list")
    public static let xmlPropertyList = UTType(known: "com.apple.xml-property-list")
    public static let binaryPropertyList = UTType(known: "com.apple.binary-property-list")
    public static let pdf = UTType(known: "com.adobe.pdf")
    public static let rtfd = UTType(known: "com.apple.rtfd")
    public static let flatRTFD = UTType(known: "com.apple.flat-rtfd")
    public static let webArchive = UTType(known: "com.apple.webarchive")
    public static let image = UTType(known: "public.image")
    public static let jpeg = UTType(known: "public.jpeg")
    public static let png = UTType(known: "public.png")
    public static let gif = UTType(known: "com.compuserve.gif")
    public static let tiff = UTType(known: "public.tiff")
    public static let bmp = UTType(known: "com.microsoft.bmp")
    public static let ico = UTType(known: "com.microsoft.ico")
    public static let icns = UTType(known: "com.apple.icns")
    public static let svg = UTType(known: "public.svg-image")
    public static let rawImage = UTType(known: "public.camera-raw-image")
    public static let livePhoto = UTType(known: "com.apple.live-photo")
    public static let heic = UTType(known: "public.heic")
    public static let heif = UTType(known: "public.heif")
    public static let webP = UTType(known: "org.webmproject.webp")
    public static let audiovisualContent = UTType(known: "public.audiovisual-content")
    public static let movie = UTType(known: "public.movie")
    public static let video = UTType(known: "public.video")
    public static let audio = UTType(known: "public.audio")
    public static let quickTimeMovie = UTType(known: "com.apple.quicktime-movie")
    public static let mpeg = UTType(known: "public.mpeg")
    public static let mpeg4Movie = UTType(known: "public.mpeg-4")
    public static let mpeg4Audio = UTType(known: "public.mpeg-4-audio")
    public static let appleProtectedMPEG4Audio = UTType(known: "com.apple.protected-mpeg-4-audio")
    public static let mp3 = UTType(known: "public.mp3")
    public static let wav = UTType(known: "com.microsoft.waveform-audio")
    public static let aiff = UTType(known: "public.aiff-audio")
    public static let archive = UTType(known: "public.archive")
    public static let zip = UTType(known: "public.zip-archive")
    public static let gzip = UTType(known: "org.gnu.gnu-zip-archive")
    public static let bz2 = UTType(known: "public.bzip2-archive")
    public static let appleArchive = UTType(known: "com.apple.archive")
    public static let spreadsheet = UTType(known: "public.spreadsheet")
    public static let presentation = UTType(known: "public.presentation")
    public static let database = UTType(known: "public.database")
    public static let message = UTType(known: "public.message")
    public static let emailMessage = UTType(known: "com.apple.mail.email")
    public static let contact = UTType(known: "public.contact")
    public static let vCard = UTType(known: "public.vcard")
    public static let calendarEvent = UTType(known: "public.calendar-event")
    public static let toDoItem = UTType(known: "public.to-do-item")
    public static let ics = UTType(known: "com.apple.ical.ics")
    public static let internetLocation = UTType(known: "com.apple.internet-location")
    public static let executable = UTType(known: "public.executable")
    public static let font = UTType(known: "public.font")
    public static let epub = UTType(known: "org.idpf.epub-container")
    public static let log = UTType(known: "public.log")
    public static let usdz = UTType(known: "com.pixar.universal-scene-description-mobile")
    public static let threeDContent = UTType(known: "public.3d-content")
    public static let pkPass = UTType(known: "com.apple.pkpass")
}

extension URL {
    public func appending(path: String, conformingTo type: UTType) -> URL {
        appendingPathComponent(path).appendingPathExtension(type.preferredFilenameExtension ?? "")
    }
    public func appendingPathComponent(_ partialName: String, conformingTo contentType: UTType) -> URL { appending(path: partialName, conformingTo: contentType) }
    public func appendingPathExtension(for contentType: UTType) -> URL { appendingPathExtension(contentType.preferredFilenameExtension ?? "") }
}
