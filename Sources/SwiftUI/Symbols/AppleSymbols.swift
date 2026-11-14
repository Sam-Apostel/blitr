internal import CSkia
internal import CHarfBuzz

// Real SF Symbols, when the user has supplied them.
//
// Apple's SF Pro font (scripts/fetch-apple-fonts.sh) contains the symbol outlines, addressed
// by private-use code points. What it does not contain is the symbol names: Apple ships that
// table only in obfuscated form. So real symbols are used when a name map is also present:
// a file `sf-symbols-map.json` in any font directory, of the form
//
//     { "symbols": { "heart.fill": "1002B5", "chevron.right": "10018A", ... } }
//
// generated once on a Mac (see scripts/mac/). Names missing from the map fall back to the
// bundled open icon set.
@MainActor
final class AppleSymbols {
    static let shared = AppleSymbols()

    private var loadedFor: [String]?
    private var codePoints: [String: UInt32] = [:]
    private var font: FontFile?

    private func load() {
        let directories = FontLibrary.shared.directories
        if loadedFor == directories { return }
        loadedFor = directories
        codePoints = [:]
        font = nil
        for dir in directories {
            let mapPath = dir + "/sf-symbols-map.json"
            guard let data = FileManager.default.contents(atPath: mapPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let symbols = json["symbols"] as? [String: String] else { continue }
            for (name, hex) in symbols {
                if let value = UInt32(hex.replacingOccurrences(of: "U+", with: ""), radix: 16) { codePoints[name] = value }
            }
            break
        }
        let hasMap = !codePoints.isEmpty
        // Symbols at documented code points need no map: the Apple logo is U+F8FF in every Apple font.
        for (name, codePoint) in AppleSymbols.wellKnown where codePoints[name] == nil { codePoints[name] = codePoint }
        font = FontLibrary.shared.fontFile(named: "SF-Pro.ttf")
        if font == nil, hasMap {
            Runtime.current?.warn("sf-symbols-map.json found but SF-Pro.ttf is not installed; using the open icon set")
        }
    }

    /// Space above and below a symbol's outline, as a fraction of its point size.
    static let verticalPadding: CGFloat = 0.09

    private static let wellKnown: [String: UInt32] = ["apple.logo": 0xF8FF, "applelogo": 0xF8FF]

    /// True when the font is available (the name map decides which names resolve).
    var isAvailable: Bool {
        load()
        return font != nil
    }

    /// The outline of a symbol at a weight and point size, positioned with its top-left at the origin.
    func glyph(named name: String, weight: CGFloat, pointSize: CGFloat) -> SymbolGlyph? {
        load()
        guard let font, let codePoint = codePoints[name] else { return nil }
        let instance = font.instance([fourCC("wght"): font.axisWeight(Float(weight)), fourCC("opsz"): Float(pointSize)])
        var glyphID: UInt32 = 0
        guard hb_font_get_nominal_glyph(instance.hbFont, codePoint, &glyphID) != 0 else { return nil }
        let skFont = sk_font_new_with_values(instance.skTypeface, Float(pointSize), 1, 0)
        defer { sk_font_delete(skFont) }
        guard let skPath = sk_path_new() else { return nil }
        defer { sk_path_delete(skPath) }
        guard sk_font_get_path(skFont, UInt16(truncatingIfNeeded: glyphID), skPath) else { return nil }
        let outline = Path(skPath: skPath)
        let bounds = outline.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // The image is as wide as the glyph's advance, the outline at its left side bearing, and
        // as tall as the outline plus `verticalPadding` x the point size above and below.
        // measured: iOS 27.0 simulator (Symbols, ControlsButtons): images in an HStack(spacing: 14)
        // sit 14pt + (advance - outline width) apart (21pt for chevron.right at 28pt, 17pt for
        // heart.fill at 12pt); rows of symbols are 2.0 to 3.0pt per side taller than their tallest
        // outline at 22 to 34pt, a 17pt star.fill label in a button 1.67pt per side.
        let advance = CGFloat(hb_font_get_glyph_h_advance(instance.hbFont, glyphID)) * pointSize / font.unitsPerEm
        let width = max(bounds.width, advance)
        let left = min(max(0, bounds.minX), width - bounds.width)
        let pad = ((AppleSymbols.verticalPadding * pointSize) * 3).rounded() / 3
        let size = CGSize(width: width, height: bounds.height + 2 * pad)
        let placed = outline.offsetBy(dx: left - bounds.minX, dy: pad - bounds.minY)
        var glyph = SymbolGlyph(size: size, viewBox: size, layers: [.init(path: placed, stroke: nil, evenOdd: false)])
        glyph.inkInsets = (pad, left, pad, width - bounds.width - left)
        return glyph
    }
}
