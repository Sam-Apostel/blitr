internal import CSkia
internal import CHarfBuzz

// Font files, their HarfBuzz/Skia handles, and the system-font substitution table.

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

/// One font file on disk.
final class FontFile {
    let path: String
    let data: Data
    let hbFace: OpaquePointer
    let skTypeface: OpaquePointer
    let unitsPerEm: CGFloat
    /// Variation axes by tag: (min, default, max).
    private(set) var axes: [UInt32: (min: Float, def: Float, max: Float)] = [:]
    private var instances: [[UInt32: Float]: FontInstance] = [:]

    init?(path: String) {
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return nil }
        self.path = path
        self.data = data
        let blob = data.withUnsafeBytes { raw -> OpaquePointer? in
            hb_blob_create(raw.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(raw.count), HB_MEMORY_MODE_DUPLICATE, nil, nil)
        }
        guard let face = hb_face_create(blob, 0) else { return nil }
        hb_blob_destroy(blob)
        hbFace = face
        unitsPerEm = CGFloat(hb_face_get_upem(face))
        let manager = sk_fontmgr_create_default()
        guard let typeface = sk_fontmgr_create_from_file(manager, path, 0) else { return nil }
        skTypeface = typeface
        var count = hb_ot_var_get_axis_count(face)
        if count > 0 {
            var infos = [hb_ot_var_axis_info_t](repeating: hb_ot_var_axis_info_t(), count: Int(count))
            _ = hb_ot_var_get_axis_infos(face, 0, &count, &infos)
            for info in infos.prefix(Int(count)) { axes[info.tag] = (info.min_value, info.default_value, info.max_value) }
        }
    }

    /// The face at a point in its variation space (cached).
    func instance(_ requested: [UInt32: Float]) -> FontInstance {
        var coords: [UInt32: Float] = [:]
        for (tag, value) in requested {
            if let axis = axes[tag] { coords[tag] = max(axis.min, min(axis.max, value)) }
        }
        if let cached = instances[coords] { return cached }
        let instance = FontInstance(file: self, coordinates: coords)
        instances[coords] = instance
        return instance
    }
}

/// A font file at specific variation coordinates: shapes with HarfBuzz, draws with Skia.
final class FontInstance {
    let file: FontFile
    let hbFont: OpaquePointer
    let skTypeface: OpaquePointer
    /// Vertical metrics as fractions of the em (ascent and descent both positive).
    var ascent: CGFloat = 0.95
    var descent: CGFloat = 0.24
    var capHeight: CGFloat = 0.7
    var xHeight: CGFloat = 0.5
    var underlineOffset: CGFloat = 0.1
    var underlineThickness: CGFloat = 0.06
    var isColor = false

    init(file: FontFile, coordinates: [UInt32: Float]) {
        self.file = file
        let font = hb_font_create(file.hbFace)!
        if !coordinates.isEmpty {
            var variations = coordinates.map { hb_variation_t(tag: $0.key, value: $0.value) }
            hb_font_set_variations(font, &variations, UInt32(variations.count))
            var skCoords = coordinates.map { sk_fontarguments_variation_position_coordinate_t(axis: $0.key, value: $0.value) }
            skTypeface = sk_typeface_clone_with_arguments(file.skTypeface, &skCoords, Int32(skCoords.count), 0, 0, nil, 0) ?? file.skTypeface
        } else {
            skTypeface = file.skTypeface
        }
        hbFont = font
        let skFont = sk_font_new_with_values(skTypeface, 1000, 1, 0)
        var m = sk_fontmetrics_t()
        _ = sk_font_get_metrics(skFont, &m)
        sk_font_delete(skFont)
        ascent = CGFloat(-m.fAscent) / 1000
        descent = CGFloat(m.fDescent) / 1000
        if m.fCapHeight > 0 { capHeight = CGFloat(m.fCapHeight) / 1000 }
        if m.fXHeight > 0 { xHeight = CGFloat(m.fXHeight) / 1000 }
        if m.fUnderlineThickness > 0 { underlineThickness = CGFloat(m.fUnderlineThickness) / 1000 }
        if m.fUnderlinePosition > 0 { underlineOffset = CGFloat(m.fUnderlinePosition) / 1000 }
        isColor = sk_typeface_get_table_size(skTypeface, fourCC("CBDT")) > 0 || sk_typeface_get_table_size(skTypeface, fourCC("COLR")) > 0
            || sk_typeface_get_table_size(skTypeface, fourCC("sbix")) > 0
    }

    func hasGlyph(_ scalar: Unicode.Scalar) -> Bool {
        var glyph: UInt32 = 0
        return hb_font_get_nominal_glyph(hbFont, scalar.value, &glyph) != 0
    }
}

@MainActor
final class FontLibrary {
    static let shared = FontLibrary()

    /// Directories searched for font files, most specific first (user fonts, then the bundled ones).
    var directories: [String] = [] { didSet { reset() } }

    private var files: [String: FontFile?] = [:]
    private var systemFaces: [SystemKey: FontFile?] = [:]
    private var customIndex: [String: String]?
    private var fallbacks: [FontFile]?

    private struct SystemKey: Hashable { var design: Font.Design; var italic: Bool }

    private func reset() {
        systemFaces = [:]
        customIndex = nil
        fallbacks = nil
    }

    private func file(_ path: String) -> FontFile? {
        if let cached = files[path] { return cached }
        let f = FontFile(path: path)
        files[path] = f
        return f
    }

    private func find(_ names: [String]) -> FontFile? {
        for dir in directories {
            for name in names {
                let path = dir + "/" + name
                if FileManager.default.fileExists(atPath: path), let f = file(path) { return f }
            }
        }
        return nil
    }

    /// Candidate file names per system design. Apple's own files win when the user supplies them.
    private func systemFile(_ design: Font.Design, italic: Bool) -> FontFile? {
        let key = SystemKey(design: design, italic: italic)
        if let cached = systemFaces[key] { return cached }
        let names: [String]
        switch (design, italic) {
        case (.default, false): names = ["SF-Pro.ttf", "SFNS.ttf", "InterVariable.ttf"]
        case (.default, true): names = ["SF-Pro-Italic.ttf", "SFNSItalic.ttf", "InterVariable-Italic.ttf"]
        case (.rounded, _): names = ["SF-Pro-Rounded.ttf", "SFNSRounded.ttf", "SF-Pro-Rounded-Regular.otf", "Nunito[wght].ttf", "Nunito-VariableFont_wght.ttf"]
        case (.serif, false): names = ["NewYork.ttf", "SourceSerif4[opsz,wght].ttf", "SourceSerif4-VariableFont_opsz,wght.ttf", "NotoSerif-Regular.ttf"]
        case (.serif, true): names = ["NewYorkItalic.ttf", "SourceSerif4-Italic[opsz,wght].ttf", "SourceSerif4-Italic-VariableFont_opsz,wght.ttf"]
        case (.monospaced, false): names = ["SF-Mono.ttf", "SFNSMono.ttf", "JetBrainsMono[wght].ttf", "JetBrainsMono-VariableFont_wght.ttf", "DejaVuSansMono.ttf"]
        case (.monospaced, true): names = ["SF-Mono-Italic.ttf", "SFNSMonoItalic.ttf", "JetBrainsMono-Italic[wght].ttf", "JetBrainsMono-Italic-VariableFont_wght.ttf"]
        }
        var found = find(names)
        if found == nil {
            if italic { found = systemFile(design, italic: false) }
            else if design != .default {
                Runtime.current?.warn("No font installed for the \(design) design; using the default system font")
                found = systemFile(.default, italic: false)
            }
        }
        systemFaces[key] = found
        return found
    }

    private func customFile(named name: String) -> FontFile? {
        if customIndex == nil {
            var index: [String: String] = [:]
            for dir in directories + ["/usr/share/fonts", "/usr/local/share/fonts"] {
                guard let walker = FileManager.default.enumerator(atPath: dir) else { continue }
                for case let rel as String in walker {
                    let lower = rel.lowercased()
                    guard lower.hasSuffix(".ttf") || lower.hasSuffix(".otf") || lower.hasSuffix(".ttc") else { continue }
                    let path = dir + "/" + rel
                    let stem = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
                    index[FontLibrary.normalize(stem)] = index[FontLibrary.normalize(stem)] ?? path
                }
            }
            customIndex = index
        }
        let wanted = FontLibrary.normalize(name)
        if let path = customIndex?[wanted] { return file(path) }
        // "Avenir-Heavy" style PostScript names: fall back to any file of the family.
        let family = FontLibrary.normalize(name.split(separator: "-").first.map(String.init) ?? name)
        if let match = customIndex?.first(where: { $0.key.hasPrefix(family) }) { return file(match.value) }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func instance(for font: ResolvedFont) -> FontInstance {
        var chosen: FontFile?
        var isSystem = true
        switch font.family {
        case .system(let design): chosen = systemFile(design, italic: font.italic)
        case .custom(let name):
            chosen = customFile(named: name)
            isSystem = false
            if chosen == nil {
                Runtime.current?.warn("Font \"\(name)\" not found; using the system font")
                chosen = systemFile(.default, italic: font.italic)
                isSystem = true
            }
        }
        guard let file = chosen else {
            fatalError("No usable system font found. Run scripts/bootstrap.sh, or point SWIFTUI_SCREENSHOT_FONTS at a directory containing InterVariable.ttf.")
        }
        var coords: [UInt32: Float] = [fourCC("wght"): Float(font.weight), fourCC("opsz"): Float(font.size)]
        if font.width != 0 { coords[fourCC("wdth")] = Float(100 + font.width * 25) }
        if font.italic && file.axes[fourCC("ital")] != nil { coords[fourCC("ital")] = 1 }
        if font.italic && file.axes[fourCC("slnt")] != nil { coords[fourCC("slnt")] = -10 }
        let instance = file.instance(coords)
        if isSystem {
            // Every system design shares SF's vertical metrics on iOS; using them keeps line
            // heights identical to the device whichever substitute font is installed.
            instance.ascent = 0.952148
            instance.descent = 0.241211
        }
        return instance
    }

    /// Fonts tried, in order, for characters the primary font lacks (emoji, CJK, symbols).
    func fallbackInstance(for scalar: Unicode.Scalar, like font: ResolvedFont) -> FontInstance? {
        if fallbacks == nil {
            var list: [FontFile] = []
            let candidates = ["AppleColorEmoji.ttf", "NotoColorEmoji.ttf"]
            if let f = find(candidates) { list.append(f) }
            for path in ["/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
                         "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                         "/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf",
                         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"] {
                if !list.contains(where: { $0.path == path }), let f = file(path) { list.append(f) }
            }
            fallbacks = list
        }
        for file in fallbacks ?? [] {
            let instance = file.instance([fourCC("wght"): Float(font.weight)])
            if instance.hasGlyph(scalar) { return instance }
        }
        return nil
    }
}
