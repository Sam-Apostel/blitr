// `import CoreText`: font registration (the registered files are what `Font.custom` and `UIFont(name:size:)`
// find, through the font registry in CoreGraphics) and CTFont metrics read from the font file.
@_exported import CoreGraphics
internal import CSkia

public enum CTFontManagerScope: UInt32, Sendable {
    case none = 0, process = 1, persistent = 2, session = 3, user = 2147483647
}
public enum CTFontManagerError: Int, Sendable {
    case fileNotFound = 101, insufficientPermissions = 102, unrecognizedFormat = 103, invalidFontData = 104, alreadyRegistered = 105
    case notRegistered = 201, inUse = 202, systemRequired = 203
}
public let kCTFontManagerErrorDomain: CFString = _cfString("com.apple.CoreText.CTFontManagerErrorDomain")

private func fail(_ code: CTFontManagerError, _ url: URL?, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    error?.pointee = Unmanaged.passRetained(NSError(domain: kCTFontManagerErrorDomain as String, code: code.rawValue,
                                                   userInfo: url.map { [NSURLErrorKey: $0] }))
    return false
}

/// Registers the font file so `Font.custom` finds it by PostScript, family or file name.
@discardableResult
public func CTFontManagerRegisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    let url = fontURL as URL
    guard FileManager.default.fileExists(atPath: url.path) else { return fail(.fileNotFound, url, error) }
    guard FontFace(path: url.path) != nil else { return fail(.unrecognizedFormat, url, error) }
    FontRegistry.add(url.path)
    return true
}

@discardableResult
public func CTFontManagerUnregisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    let path = (fontURL as URL).path
    guard FontRegistry.paths.contains(path) else { return fail(.notRegistered, fontURL as URL, error) }
    FontRegistry.remove(path)
    return true
}

public func CTFontManagerRegisterFontURLs(_ fontURLs: CFArray, _ scope: CTFontManagerScope, _ enabled: Bool,
                                          _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
    var errors: [NSError] = []
    for case let url as URL in (fontURLs as NSArray).compactMap({ ($0 as? URL) ?? ($0 as? NSURL).map { $0 as URL } }) {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as NSURL, scope, &error), let e = error?.takeRetainedValue() { errors.append(e) }
    }
    _ = registrationHandler?(errors as NSArray as CFArray, true)
}
public func CTFontManagerUnregisterFontURLs(_ fontURLs: CFArray, _ scope: CTFontManagerScope, _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
    for case let url as URL in (fontURLs as NSArray).compactMap({ ($0 as? URL) ?? ($0 as? NSURL).map { $0 as URL } }) {
        FontRegistry.remove(url.path)
    }
    _ = registrationHandler?(NSArray() as CFArray, true)
}
@discardableResult
public func CTFontManagerRegisterFontsForURLs(_ fontURLs: CFArray, _ scope: CTFontManagerScope, _ errors: UnsafeMutablePointer<Unmanaged<CFArray>?>?) -> Bool {
    var ok = true
    CTFontManagerRegisterFontURLs(fontURLs, scope, true) { failures, _ in ok = (failures as NSArray).count == 0; return true }
    return ok
}

/// Registers a font made from data (`CGFont(provider)`): the data is written to a temporary file.
@discardableResult
public func CTFontManagerRegisterGraphicsFont(_ font: CGFont, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    FontRegistry.add(font.path)
    return true
}
@discardableResult
public func CTFontManagerUnregisterGraphicsFont(_ font: CGFont, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    FontRegistry.remove(font.path)
    return true
}
public func CTFontManagerCreateFontDescriptorsFromURL(_ fileURL: CFURL) -> CFArray? {
    guard let face = FontFace(path: (fileURL as URL).path) else { return nil }
    return [CTFontDescriptor(name: face.postScriptName, size: 0)] as NSArray
}
public func CTFontManagerCopyAvailablePostScriptNames() -> CFArray { FontRegistry.paths.compactMap { FontFace(path: $0)?.postScriptName } as NSArray }
public func CTFontManagerCopyAvailableFontFamilyNames() -> CFArray { FontRegistry.paths.compactMap { FontFace(path: $0)?.familyName } as NSArray }

// MARK: - Fonts

/// A font file read with Skia: its names and vertical metrics (fractions of the em).
final class FontFace {
    let path: String
    let postScriptName: String
    let familyName: String
    let unitsPerEm: Int
    let ascent: CGFloat, descent: CGFloat, leading: CGFloat, capHeight: CGFloat, xHeight: CGFloat
    let underlinePosition: CGFloat, underlineThickness: CGFloat
    let glyphCount: Int

    init?(path: String) {
        guard let manager = sk_fontmgr_create_default() else { return nil }
        defer { sk_fontmgr_unref(manager) }
        guard let typeface = sk_fontmgr_create_from_file(manager, path, 0) else { return nil }
        defer { sk_typeface_unref(typeface) }
        func name(_ s: OpaquePointer?) -> String {
            guard let s else { return "" }
            defer { sk_string_destructor(s) }
            return String(cString: sk_string_get_c_str(s))
        }
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let ps = name(sk_typeface_get_post_script_name(typeface)), family = name(sk_typeface_get_family_name(typeface))
        self.path = path
        postScriptName = ps.isEmpty ? stem : ps
        familyName = family.isEmpty ? stem : family
        unitsPerEm = Int(sk_typeface_get_units_per_em(typeface))
        glyphCount = Int(sk_typeface_count_glyphs(typeface))
        let font = sk_font_new_with_values(typeface, 1000, 1, 0)
        defer { sk_font_delete(font) }
        var m = sk_fontmetrics_t()
        _ = sk_font_get_metrics(font, &m)
        ascent = CGFloat(-m.fAscent) / 1000
        descent = CGFloat(m.fDescent) / 1000
        leading = CGFloat(m.fLeading) / 1000
        capHeight = CGFloat(m.fCapHeight) / 1000
        xHeight = CGFloat(m.fXHeight) / 1000
        underlinePosition = -CGFloat(m.fUnderlinePosition) / 1000
        underlineThickness = CGFloat(m.fUnderlineThickness) / 1000
    }

    /// A registered font by PostScript, family or file name.
    static func registered(named name: String) -> FontFace? {
        func normalize(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wanted = normalize(name)
        for path in FontRegistry.paths {
            guard let face = FontFace(path: path) else { continue }
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if [face.postScriptName, face.familyName, stem].map(normalize).contains(wanted) { return face }
        }
        return nil
    }
}

public final class CTFontDescriptor: @unchecked Sendable {
    let name: String
    let size: CGFloat
    init(name: String, size: CGFloat) { self.name = name; self.size = size }
}
public func CTFontDescriptorCreateWithNameAndSize(_ name: CFString, _ size: CGFloat) -> CTFontDescriptor { CTFontDescriptor(name: name as String, size: size) }
public func CTFontDescriptorCopyAttribute(_ descriptor: CTFontDescriptor, _ attribute: CFString) -> CFTypeRef? {
    switch attribute as String {
    case "NSFontNameAttribute", "NSFontFamilyAttribute": return descriptor.name as NSString
    case "NSFontSizeAttribute": return NSNumber(value: Double(descriptor.size))
    default: return nil
    }
}
public let kCTFontNameAttribute: CFString = _cfString("NSFontNameAttribute")
public let kCTFontFamilyNameAttribute: CFString = _cfString("NSFontFamilyAttribute")
public let kCTFontSizeAttribute: CFString = _cfString("NSFontSizeAttribute")
public let kCTFontTraitsAttribute: CFString = _cfString("NSCTFontTraitsAttribute")

/// A font at a size. Metrics come from the font file when one by that name is registered (or the
/// descriptor's file), and from the system font's proportions otherwise.
public final class CTFont: @unchecked Sendable {
    let name: String
    let size: CGFloat
    let face: FontFace?
    init(name: String, size: CGFloat, face: FontFace?) { self.name = name; self.size = size == 0 ? 12 : size; self.face = face }
}
public struct CTFontOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let `default`: CTFontOptions = []
    public static let preventAutoActivation = CTFontOptions(rawValue: 1)
    public static let preferSystemFont = CTFontOptions(rawValue: 4)
}
public enum CTFontUIFontType: UInt32, Sendable { case none = 4294967295, user = 0, userFixedPitch, system, emphasizedSystem, smallSystem, label = 10 }

public func CTFontCreateWithName(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    CTFont(name: name as String, size: size, face: FontFace.registered(named: name as String))
}
public func CTFontCreateWithNameAndOptions(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ options: CTFontOptions) -> CTFont {
    CTFontCreateWithName(name, size, matrix)
}
public func CTFontCreateWithFontDescriptor(_ descriptor: CTFontDescriptor, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    CTFontCreateWithName(descriptor.name as NSString, size == 0 ? descriptor.size : size, matrix)
}
public func CTFontCreateWithGraphicsFont(_ graphicsFont: CGFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?,
                                         _ attributes: CTFontDescriptor?) -> CTFont {
    CTFont(name: graphicsFont.face.postScriptName, size: size, face: graphicsFont.face)
}
public func CTFontCreateUIFontForLanguage(_ uiType: CTFontUIFontType, _ size: CGFloat, _ language: CFString?) -> CTFont? {
    CTFont(name: ".SFUI-Regular", size: size, face: nil)
}
public func CTFontCreateCopyWithAttributes(_ font: CTFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ attributes: CTFontDescriptor?) -> CTFont {
    CTFont(name: font.name, size: size == 0 ? font.size : size, face: font.face)
}
public func CTFontCopyPostScriptName(_ font: CTFont) -> CFString { (font.face?.postScriptName ?? font.name) as NSString }
public func CTFontCopyFamilyName(_ font: CTFont) -> CFString { (font.face?.familyName ?? font.name) as NSString }
public func CTFontCopyFullName(_ font: CTFont) -> CFString { (font.face?.postScriptName ?? font.name) as NSString }
public func CTFontCopyDisplayName(_ font: CTFont) -> CFString { (font.face?.familyName ?? font.name) as NSString }
public func CTFontCopyFontDescriptor(_ font: CTFont) -> CTFontDescriptor { CTFontDescriptor(name: font.name, size: font.size) }
public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.size }
public func CTFontGetAscent(_ font: CTFont) -> CGFloat { (font.face?.ascent ?? 0.952) * font.size }
public func CTFontGetDescent(_ font: CTFont) -> CGFloat { (font.face?.descent ?? 0.241) * font.size }
public func CTFontGetLeading(_ font: CTFont) -> CGFloat { (font.face?.leading ?? 0) * font.size }
public func CTFontGetCapHeight(_ font: CTFont) -> CGFloat { (font.face?.capHeight ?? 0.705) * font.size }
public func CTFontGetXHeight(_ font: CTFont) -> CGFloat { (font.face?.xHeight ?? 0.526) * font.size }
public func CTFontGetUnderlinePosition(_ font: CTFont) -> CGFloat { (font.face?.underlinePosition ?? -0.1) * font.size }
public func CTFontGetUnderlineThickness(_ font: CTFont) -> CGFloat { (font.face?.underlineThickness ?? 0.06) * font.size }
public func CTFontGetUnitsPerEm(_ font: CTFont) -> UInt32 { UInt32(font.face?.unitsPerEm ?? 2048) }
public func CTFontGetGlyphCount(_ font: CTFont) -> CFIndex { font.face?.glyphCount ?? 0 }
public func CTFontGetSlantAngle(_ font: CTFont) -> CGFloat { 0 }
public func CTFontGetMatrix(_ font: CTFont) -> CGAffineTransform { .identity }
public func CTFontGetBoundingBox(_ font: CTFont) -> CGRect {
    CGRect(x: 0, y: -CTFontGetDescent(font), width: font.size, height: CTFontGetAscent(font) + CTFontGetDescent(font))
}

// MARK: - CGFont (Core Graphics' font type, made from font data for registration)

public final class CGFont: @unchecked Sendable {
    let path: String
    let face: FontFace
    init?(path: String) {
        guard let face = FontFace(path: path) else { return nil }
        self.path = path
        self.face = face
    }
    /// Font data is written to a temporary file the renderer can load by path.
    public convenience init?(_ provider: CGDataProvider) {
        guard let data = provider.data as Data? else { return nil }
        let path = NSTemporaryDirectory() + "/blitr-font-\(UUID().uuidString).ttf"
        guard FileManager.default.createFile(atPath: path, contents: data) else { return nil }
        self.init(path: path)
    }
    public convenience init?(_ name: CFString) {
        guard let face = FontFace.registered(named: name as String) else { return nil }
        self.init(path: face.path)
    }
    public var postScriptName: CFString? { face.postScriptName as NSString }
    public var fullName: CFString? { face.postScriptName as NSString }
    public var unitsPerEm: Int32 { Int32(face.unitsPerEm) }
    public var numberOfGlyphs: Int { face.glyphCount }
    public var ascent: Int32 { Int32((face.ascent * CGFloat(face.unitsPerEm)).rounded()) }
    public var descent: Int32 { Int32((-face.descent * CGFloat(face.unitsPerEm)).rounded()) }
    public var capHeight: Int32 { Int32((face.capHeight * CGFloat(face.unitsPerEm)).rounded()) }
    public var xHeight: Int32 { Int32((face.xHeight * CGFloat(face.unitsPerEm)).rounded()) }
}
