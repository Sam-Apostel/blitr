internal import CSkia

// Stand-in artwork for SF Symbols.
//
// Resolution order for a symbol name:
//   1. hand-drawn primitives (HandDrawnSymbols) -- chrome glyphs that must match SF proportions;
//   2. the generated Phosphor table (SymbolData), regular or bold outline depending on font weight;
//   3. synthesis: `X.circle[.fill]`, `X.square[.fill]`, `X.fill`, `X.slash` composed from the base glyph.
// Unknown names return nil so the renderer warns and draws its placeholder.

typealias SymbolArt = (viewBox: CGSize, layers: [SymbolGlyph.Layer])

extension Path {
    /// Parses SVG path data (`M... C... Z`) with Skia's parser; nil when the data is malformed.
    init?(svg: String) {
        guard let sk = sk_path_new() else { return nil }
        defer { sk_path_delete(sk) }
        guard sk_path_parse_svg_string(sk, svg) else { return nil }
        self.init(skPath: sk)
    }

    /// Outline of this path stroked with `style` (Skia's fill-path with an explicit identity matrix).
    func stroke(_ style: StrokeStyle) -> Path {
        withSkPath { sk in
            guard let paint = sk_paint_new() else { return self }
            defer { sk_paint_delete(paint) }
            Painter.applyStroke(style, to: paint)
            guard let builder = sk_pathbuilder_new() else { return self }
            var identity = sk_matrix_t(scaleX: 1, skewX: 0, transX: 0, skewY: 0, scaleY: 1, transY: 0, persp0: 0, persp1: 0, persp2: 1)
            _ = sk_paint_get_fill_path(paint, sk, builder, nil, &identity)
            let out = sk_pathbuilder_detach_path(builder)
            sk_pathbuilder_delete(builder)
            guard let out else { return self }
            defer { sk_path_delete(out) }
            return Path(skPath: out)
        }
    }

    /// Boolean difference computed by Skia's path ops (nonzero fill on both operands).
    func subtracting(_ other: Path) -> Path? { op(other, DIFFERENCE_SK_PATHOP) }
    func union(_ other: Path) -> Path? { op(other, UNION_SK_PATHOP) }

    private func op(_ other: Path, _ kind: sk_pathop_t) -> Path? {
        withSkPath { a in
            other.withSkPath { b in
                guard let out = sk_path_new() else { return nil }
                defer { sk_path_delete(out) }
                guard sk_pathop_op(a, b, kind, out) else { return nil }
                return Path(skPath: out)
            }
        }
    }
}

@MainActor
final class SymbolArtwork {
    static let shared = SymbolArtwork()

    /// Weight at and above which the bold outline set is used (SF "medium" and heavier).
    static let boldThreshold: CGFloat = 500

    private struct RawEntry { var viewBox: CGSize; var layers: Substring }
    private lazy var index: [String: RawEntry] = Self.buildIndex()
    private var cache: [String: SymbolArt?] = [:]

    /// True when the name resolves to something (used by tests and the generator report).
    func contains(_ name: String) -> Bool { art(named: name, weight: 400) != nil }

    func art(named name: String, weight: CGFloat) -> SymbolArt? {
        let bold = weight >= Self.boldThreshold
        // Hand-drawn glyphs depend continuously on weight; bucket it so the cache stays small.
        let key = name + (bold ? "#b" : "#r") + String(Int(weight / 50))
        if let hit = cache[key] { return hit }
        let result = resolve(name, weight: weight, bold: bold)
        cache[key] = result
        return result
    }

    private func resolve(_ name: String, weight: CGFloat, bold: Bool) -> SymbolArt? {
        if let drawn = HandDrawnSymbols.make(name, weight: weight) { return drawn }
        if let direct = table(name, bold: bold) { return direct }
        return synthesise(name, weight: weight, bold: bold)
    }

    // MARK: Table

    private func table(_ name: String, bold: Bool) -> SymbolArt? {
        guard let raw = (bold ? index[name + "@b"] : nil) ?? index[name] else { return nil }
        var layers: [SymbolGlyph.Layer] = []
        for spec in raw.layers.split(separator: "|") {
            guard let colon = spec.firstIndex(of: ":") else { continue }
            let head = spec[spec.startIndex..<colon], data = String(spec[spec.index(after: colon)...])
            guard let path = Path(svg: data) else { continue }
            switch head.first {
            case "F": layers.append(.init(path: path, stroke: nil, evenOdd: false))
            case "E": layers.append(.init(path: path, stroke: nil, evenOdd: true))
            case "S":
                let f = head.dropFirst().split(separator: ",")
                guard f.count == 3, let w = Double(f[0]) else { continue }
                let cap: CGLineCap = f[1] == "r" ? .round : f[1] == "s" ? .square : .butt
                let join: CGLineJoin = f[2] == "r" ? .round : f[2] == "b" ? .bevel : .miter
                layers.append(.init(path: path, stroke: StrokeStyle(lineWidth: w, lineCap: cap, lineJoin: join), evenOdd: false))
            default: continue
            }
        }
        return layers.isEmpty ? nil : (raw.viewBox, layers)
    }

    private static func buildIndex() -> [String: RawEntry] {
        var out: [String: RawEntry] = [:]
        out.reserveCapacity(SymbolData.count)
        for line in SymbolData.source.split(separator: "\n") {
            let cols = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count == 3 else { continue }
            let vb = cols[1].split(separator: ",").compactMap { Double($0) }
            guard vb.count == 2 else { continue }
            out[String(cols[0])] = RawEntry(viewBox: CGSize(width: vb[0], height: vb[1]), layers: cols[2])
        }
        return out
    }

    // MARK: Synthesis

    private static let box: CGFloat = 256

    private func synthesise(_ name: String, weight: CGFloat, bold: Bool) -> SymbolArt? {
        for suffix in [".circle.fill", ".square.fill", ".circle", ".square"] where name.hasSuffix(suffix) {
            let base = String(name.dropLast(suffix.count))
            return container(around: base, shape: suffix.contains("circle") ? .circle : .square,
                             filled: suffix.hasSuffix(".fill"), weight: weight, bold: bold)
        }
        if name.hasSuffix(".slash") {
            guard let base = art(named: String(name.dropLast(6)), weight: weight) else { return nil }
            return slashed(base, bold: bold)
        }
        if name.hasSuffix(".fill") {
            return art(named: String(name.dropLast(5)), weight: weight)
        }
        return nil
    }

    private enum Shape { case circle, square }

    /// Scales and centres art into the 256-unit square used by synthesised variants.
    private func normalised(_ art: SymbolArt, scale k: CGFloat, weightBoost: CGFloat = 1) -> [SymbolGlyph.Layer] {
        let s = k * Self.box / max(art.viewBox.width, art.viewBox.height)
        let t = CGAffineTransform(translationX: -art.viewBox.width / 2, y: -art.viewBox.height / 2)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: Self.box / 2, y: Self.box / 2))
        return art.layers.map { layer in
            var out = layer
            out.path = layer.path.applying(t)
            if var st = layer.stroke { st.lineWidth *= s * weightBoost; out.stroke = st }
            return out
        }
    }

    private func container(around base: String, shape: Shape, filled: Bool, weight: CGFloat, bold: Bool) -> SymbolArt? {
        // The inner glyph is drawn heavier than the ring's own weight so it survives the reduction.
        let inner: SymbolArt?
        if filled {
            inner = art(named: base + ".fill", weight: 700) ?? art(named: base, weight: 700)
        } else {
            inner = art(named: base, weight: 700)
        }
        guard let glyph = inner else { return nil }
        let ringWidth: CGFloat = bold ? 24 : 16
        let outline: Path
        switch shape {
        case .circle: outline = Path(ellipseIn: CGRect(x: 16, y: 16, width: 224, height: 224))
        case .square: outline = Path(roundedRect: CGRect(x: 20, y: 20, width: 216, height: 216), cornerRadius: 44, style: .continuous)
        }
        let centreline = outline.boundingRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
        let ringPath: Path = shape == .circle
            ? Path(ellipseIn: centreline)
            : Path(roundedRect: centreline, cornerRadius: 40, style: .continuous)
        let scale: CGFloat = shape == .circle ? 0.56 : 0.6
        let layers = normalised(glyph, scale: scale)
        let viewBox = CGSize(width: Self.box, height: Self.box)
        if !filled {
            let ring = SymbolGlyph.Layer(path: ringPath, stroke: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round), evenOdd: false)
            return (viewBox, [ring] + layers)
        }
        // Solid shape with the glyph knocked out.
        var disc = outline
        for layer in layers {
            let shapePath = layer.stroke.map { layer.path.stroke($0) } ?? layer.path
            if let next = disc.subtracting(shapePath) { disc = next }
        }
        // Skia path-op results are simplified outlines meant for even-odd filling.
        return (viewBox, [.init(path: disc, stroke: nil, evenOdd: true)])
    }

    /// A line segment of the given width with round ends, as a closed outline.
    private static func capsule(from a: CGPoint, to b: CGPoint, width: CGFloat) -> Path {
        let length = hypot(b.x - a.x, b.y - a.y), angle = atan2(b.y - a.y, b.x - a.x)
        let rect = CGRect(x: -width / 2, y: -width / 2, width: length + width, height: width)
        let t = CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: a.x, y: a.y))
        return Path(roundedRect: rect, cornerRadius: width / 2, style: .circular).applying(t)
    }

    private func slashed(_ base: SymbolArt, bold: Bool) -> SymbolArt? {
        let width: CGFloat = bold ? 24 : 16, gap: CGFloat = 12
        let a = CGPoint(x: 36, y: 32), b = CGPoint(x: 220, y: 224)
        let slashShape = Self.capsule(from: a, to: b, width: width)
        let band = Self.capsule(from: a, to: b, width: width + gap * 2)
        var out: [SymbolGlyph.Layer] = []
        for layer in normalised(base, scale: 1) {
            let shapePath = layer.stroke.map { layer.path.stroke($0) } ?? layer.path
            // Even-odd layers are rare here; the difference treats them as nonzero, which is fine for icon art.
            out.append(.init(path: shapePath.subtracting(band) ?? shapePath, stroke: nil, evenOdd: true))
        }
        out.append(.init(path: slashShape, stroke: nil, evenOdd: false))
        return (CGSize(width: Self.box, height: Self.box), out)
    }
}

extension SymbolGlyph {
    /// Stand-in artwork cropped to its ink (plus `pad` points above and below, as `AppleSymbols` pads real
    /// outlines), at `unit` points per viewBox unit. Real SF Symbols lay out at
    /// their outline's bounds (an `ellipsis` at `.title` is 25.7 x 5.3pt, measured: iOS 27.0 simulator), so
    /// a stand-in drawn next to them takes the size of its ink, not of its square viewBox.
    @MainActor static func inkCropped(viewBox: CGSize, layers: [Layer], unit: CGFloat, verticalPadding pad: CGFloat = 0) -> SymbolGlyph? {
        var ink: CGRect?
        for layer in layers {
            let outline = layer.stroke.map { layer.path.stroke($0) } ?? layer.path
            let r = outline.boundingRect
            guard r.width > 0 || r.height > 0 else { continue }
            ink = ink.map { $0.union(r) } ?? r
        }
        guard let ink, ink.width > 0, ink.height > 0 else { return nil }
        let padUnits = pad / max(unit, 0.0001)
        let t = CGAffineTransform(translationX: -ink.minX, y: padUnits - ink.minY)
        let moved = layers.map { layer -> Layer in
            var out = layer
            out.path = layer.path.applying(t)
            return out
        }
        var glyph = SymbolGlyph(size: CGSize(width: ink.width * unit, height: ink.height * unit + 2 * pad),
                                viewBox: CGSize(width: ink.width, height: ink.height + 2 * padUnits), layers: moved)
        glyph.inkInsets = (pad, 0, pad, 0)
        return glyph
    }
}
