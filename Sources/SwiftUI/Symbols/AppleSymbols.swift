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
        guard !codePoints.isEmpty else { return }
        font = FontLibrary.shared.fontFile(named: "SF-Pro.ttf")
        if font == nil {
            Runtime.current?.warn("sf-symbols-map.json found but SF-Pro.ttf is not installed; using the open icon set")
        }
    }

    /// True when both the name map and the font are available.
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
        let placed = outline.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        return SymbolGlyph(size: bounds.size, viewBox: bounds.size, layers: [.init(path: placed, stroke: nil, evenOdd: false)])
    }
}
