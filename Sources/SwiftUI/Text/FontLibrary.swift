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
    /// (weight on the 100...900 scale, value on this font's `wght` axis), ascending. Apple's fonts
    /// do not put Regular/Semibold/Bold at 400/600/700 on the axis, so the mapping is read from
    /// the font's named instances. Empty means the axis already uses the standard scale.
    private(set) var weightStops: [(weight: Float, axis: Float)] = []
    /// PostScript and family names, for fonts registered by name at run time (CoreText).
    var postScriptName: String { FontFile.name(sk_typeface_get_post_script_name(skTypeface)) }
    var familyName: String { FontFile.name(sk_typeface_get_family_name(skTypeface)) }
    private static func name(_ s: OpaquePointer?) -> String {
        guard let s else { return "" }
        defer { sk_string_destructor(s) }
        return String(cString: sk_string_get_c_str(s))
    }
    /// True for Apple's system fonts, which carry a `trak` table (size-dependent tracking).
    private(set) var hasTracking = false

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
            readWeightStops(axisInfos: Array(infos.prefix(Int(count))))
        }
        hasTracking = hb_face_reference_table(face, fourCC("trak")).map { blob in
            defer { hb_blob_destroy(blob) }
            return hb_blob_get_length(blob) > 0
        } ?? false
    }

    /// Reads Apple-style named instances ("Ultralight" ... "Black") to learn where each weight sits on the axis.
    private func readWeightStops(axisInfos: [hb_ot_var_axis_info_t]) {
        let appleNames: [String: Float] = ["ultralight": 100, "thin": 200, "light": 300, "regular": 400, "medium": 500,
                                           "semibold": 600, "bold": 700, "heavy": 800, "black": 900]
        guard let weightIndex = axisInfos.firstIndex(where: { $0.tag == fourCC("wght") }) else { return }
        var found: [Float: Float] = [:]
        var sawAppleOnlyName = false
        let english = hb_language_from_string("en", -1)
        for i in 0..<hb_ot_var_get_named_instance_count(hbFace) {
            var length: UInt32 = 64
            var buffer = [CChar](repeating: 0, count: 64)
            _ = hb_ot_name_get_utf8(hbFace, hb_ot_var_named_instance_get_subfamily_name_id(hbFace, i), english, &length, &buffer)
            let name = String(cString: buffer)
            // "Semibold"/"Heavy" (as opposed to "SemiBold"/"ExtraBold") identify Apple's naming.
            if name == "Semibold" || name == "Heavy" || name == "Ultralight" { sawAppleOnlyName = true }
            guard let weight = appleNames[name.lowercased()] else { continue }
            var coordCount = UInt32(axisInfos.count)
            var coords = [Float](repeating: 0, count: axisInfos.count)
            _ = hb_ot_var_named_instance_get_design_coords(hbFace, i, &coordCount, &coords)
            // Only the instance at the default width counts ("Regular", not "Condensed Regular").
            let othersAtDefault = axisInfos.indices.allSatisfy { k in
                k == weightIndex || axisInfos[k].tag == fourCC("opsz") || abs(coords[k] - axisInfos[k].default_value) < 0.5
            }
            if othersAtDefault { found[weight] = coords[weightIndex] }
        }
        guard sawAppleOnlyName, found.count >= 3 else { return }
        weightStops = found.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Converts a 100...900 weight to this font's `wght` axis value.
    func axisWeight(_ weight: Float) -> Float {
        guard let first = weightStops.first, let last = weightStops.last else { return weight }
        if weight <= first.weight { return first.axis }
        if weight >= last.weight { return last.axis }
        for (a, b) in zip(weightStops, weightStops.dropFirst()) where weight <= b.weight {
            return a.axis + (b.axis - a.axis) * (weight - a.weight) / (b.weight - a.weight)
        }
        return weight
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
    /// Multiplier applied to every advance. 1 for real fonts; for the Inter substitute it is the
    /// measured SF Pro / Inter width ratio at this size and weight, so lines break where they do on iOS.
    var advanceScale: CGFloat = 1
    /// Set for the substitute of the default system font: SF Pro's own advance per character at
    /// this size and weight, used in preference to `advanceScale` wherever a character is covered.
    var sfProMetrics: SFProMetrics?

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

    private struct SystemKey: Hashable { var design: Font.Design; var italic: Bool; var staticWeight: Int }

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

    /// A font file by exact name from the configured directories.
    func fontFile(named name: String) -> FontFile? { find([name]) }

    /// Candidate file names per system design. Apple's own files win when the user supplies them.
    /// Apple ships SF Pro Rounded and SF Mono as one file per weight; this picks the nearest.
    private static let staticWeights: [(weight: CGFloat, name: String)] = [
        (100, "Ultralight"), (200, "Thin"), (300, "Light"), (400, "Regular"), (500, "Medium"),
        (600, "Semibold"), (700, "Bold"), (800, "Heavy"), (900, "Black"),
    ]

    private func staticFile(prefix: String, weight: CGFloat, italic: Bool) -> FontFile? {
        let ordered = FontLibrary.staticWeights.sorted { abs($0.weight - weight) < abs($1.weight - weight) }
        for candidate in ordered {
            if let file = find(["\(prefix)-\(candidate.name)\(italic ? "Italic" : "").otf"]) { return file }
        }
        return nil
    }

    /// Candidate files per system design. Apple's own files win when the user has installed them
    /// (scripts/fetch-apple-fonts.sh); otherwise the bundled open substitutes are used.
    private func systemFile(_ design: Font.Design, italic: Bool, weight: CGFloat = 400) -> FontFile? {
        let step = Int((weight / 100).rounded()) * 100
        let key = SystemKey(design: design, italic: italic, staticWeight: design == .rounded || design == .monospaced ? step : 0)
        if let cached = systemFaces[key] { return cached }
        var found: FontFile?
        // watchOS sets its system font in SF Compact (and SF Compact Rounded), when the user has it.
        if RenderedPlatform.platform == .watchOS {
            switch (design, italic) {
            case (.default, false): found = find(["SF-Compact.ttf", "SFCompact.ttf"])
            case (.default, true): found = find(["SF-Compact-Italic.ttf", "SFCompactItalic.ttf"])
            case (.rounded, _): found = find(["SF-Compact-Rounded.ttf", "SFCompactRounded.ttf"])
            default: break
            }
            if found != nil {
                systemFaces[key] = found
                return found
            }
        }
        switch (design, italic) {
        case (.default, false): found = find(["SF-Pro.ttf", "SFNS.ttf", "InterVariable.ttf"])
        case (.default, true): found = find(["SF-Pro-Italic.ttf", "SFNSItalic.ttf", "InterVariable-Italic.ttf"])
        case (.rounded, _):
            found = find(["SF-Pro-Rounded.ttf", "SFNSRounded.ttf"]) ?? staticFile(prefix: "SF-Pro-Rounded", weight: weight, italic: false)
                ?? find(["Nunito[wght].ttf", "Nunito-VariableFont_wght.ttf"])
        case (.serif, false): found = find(["NewYork.ttf", "SourceSerif4[opsz,wght].ttf", "SourceSerif4-VariableFont_opsz,wght.ttf", "NotoSerif-Regular.ttf"])
        case (.serif, true): found = find(["NewYorkItalic.ttf", "SourceSerif4-Italic[opsz,wght].ttf", "SourceSerif4-Italic-VariableFont_opsz,wght.ttf"])
        case (.monospaced, _):
            found = find([italic ? "SF-Mono-Italic.ttf" : "SF-Mono.ttf", italic ? "SFNSMonoItalic.ttf" : "SFNSMono.ttf"])
                ?? staticFile(prefix: "SF-Mono", weight: weight, italic: italic)
                ?? find(italic ? ["JetBrainsMono-Italic[wght].ttf", "JetBrainsMono-Italic-VariableFont_wght.ttf"]
                               : ["JetBrainsMono[wght].ttf", "JetBrainsMono-VariableFont_wght.ttf", "DejaVuSansMono.ttf"])
        }
        if found == nil {
            if italic { found = systemFile(design, italic: false, weight: weight) }
            else if design != .default {
                Runtime.current?.warn("No font installed for the \(design) design; using the default system font")
                found = systemFile(.default, italic: false)
            }
        }
        systemFaces[key] = found
        return found
    }

    /// Whether `Font.custom(name, ...)` finds a font rather than falling back to the system font.
    package func hasCustomFont(named name: String) -> Bool { customFile(named: name) != nil }

    /// True when the default system font is Apple's SF Pro rather than the open substitute.
    var usesAppleSystemFont: Bool { systemFile(.default, italic: false)?.hasTracking ?? false }

    private func customFile(named name: String) -> FontFile? {
        // Fonts registered at run time (CoreText) win over the font directories.
        for path in FontRegistry.paths {
            guard let f = file(path) else { continue }
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if [f.postScriptName, f.familyName, stem].contains(where: { FontLibrary.normalize($0) == FontLibrary.normalize(name) }) { return f }
        }
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
        case .system(let design): chosen = systemFile(design, italic: font.italic, weight: font.weight)
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
        var coords: [UInt32: Float] = [fourCC("wght"): file.axisWeight(Float(font.weight)), fourCC("opsz"): Float(font.size)]
        if font.width != 0 {
            // Font.Width values (-0.8 compressed, -0.2 condensed, 0.2 expanded) on SF's wdth axis (47, 60, 132).
            let w = Float(font.width)
            coords[fourCC("wdth")] = w <= -0.2 ? 60 + (w + 0.2) / 0.6 * 13 : w <= 0 ? 100 + w / 0.2 * 40 : 100 + w / 0.2 * 32
        }
        if font.italic && file.axes[fourCC("ital")] != nil { coords[fourCC("ital")] = 1 }
        if font.italic && file.axes[fourCC("slnt")] != nil { coords[fourCC("slnt")] = -10 }
        let instance = file.instance(coords)
        if isSystem {
            // Every system design shares SF's vertical metrics on iOS; using them keeps line
            // heights identical to the device whichever substitute font is installed.
            instance.ascent = 0.952148
            instance.descent = 0.241211
            if case .system(.default) = font.family, !file.hasTracking, file.path.hasSuffix("InterVariable.ttf") || file.path.hasSuffix("InterVariable-Italic.ttf") {
                instance.advanceScale = SubstituteCalibration.interToSFPro(size: font.size, weight: font.weight)
                if font.width == 0 { instance.sfProMetrics = SFProMetrics.resolve(size: font.size, weight: font.weight) }
            }
        }
        return instance
    }

    /// Fonts tried, in order, for characters the primary font lacks (emoji, CJK, symbols).
    func fallbackInstance(for scalar: Unicode.Scalar, like font: ResolvedFont) -> FontInstance? {
        if fallbacks == nil {
            var list: [FontFile] = []
            let candidates = ["AppleColorEmoji.ttf", "Apple Color Emoji.ttc", "NotoColorEmoji.ttf"]
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

/// How much wider or narrower SF Pro sets text than the bundled substitute.
///
/// Measured by laying out the same mixed English sample with SF Pro (including its `trak`
/// tracking and optical sizes) and with Inter at each size and weight; the value is the ratio of
/// the two line widths. SF tightens as size grows, so one global factor would not do.
enum SubstituteCalibration {
    private static let sizes: [CGFloat] = [11, 12, 13, 15, 16, 17, 20, 22, 28, 34]
    private static let weights: [CGFloat] = [400, 500, 600, 700]
    private static let ratios: [[CGFloat]] = [
        [1.010, 0.998, 0.986, 0.971, 0.968, 0.960, 0.951, 0.948, 0.973, 0.989],  // regular
        [1.024, 1.012, 1.000, 0.984, 0.981, 0.973, 0.964, 0.961, 0.984, 0.999],  // medium
        [1.030, 1.019, 1.007, 0.991, 0.987, 0.979, 0.970, 0.966, 0.988, 1.001],  // semibold
        [1.044, 1.032, 1.020, 1.004, 1.000, 0.992, 0.982, 0.978, 1.000, 1.010],  // bold
    ]

    private static func bracket(_ value: CGFloat, in stops: [CGFloat]) -> (Int, Int, CGFloat) {
        if value <= stops[0] { return (0, 0, 0) }
        if value >= stops[stops.count - 1] { return (stops.count - 1, stops.count - 1, 0) }
        let upper = stops.firstIndex { $0 >= value }!
        return (upper - 1, upper, (value - stops[upper - 1]) / (stops[upper] - stops[upper - 1]))
    }

    static func interToSFPro(size: CGFloat, weight: CGFloat) -> CGFloat {
        let (s0, s1, st) = bracket(size, in: sizes)
        let (w0, w1, wt) = bracket(weight, in: weights)
        func row(_ w: Int) -> CGFloat { ratios[w][s0] + (ratios[w][s1] - ratios[w][s0]) * st }
        return row(w0) + (row(w1) - row(w0)) * wt
    }
}
