internal import CSkia

// Image: bitmap assets and system symbols.

/// A decoded bitmap (Skia image) with its point size.
final class Bitmap: @unchecked Sendable {
    let image: OpaquePointer
    let pointSize: CGSize
    init?(path: String, scale: CGFloat) {
        guard let data = sk_data_new_from_file(path) else { return nil }
        defer { sk_data_unref(data) }
        guard let image = sk_image_new_from_encoded(data) else { return nil }
        self.image = image
        pointSize = CGSize(width: CGFloat(sk_image_get_width(image)) / scale, height: CGFloat(sk_image_get_height(image)) / scale)
    }
    deinit { sk_image_unref(image) }
}

/// Finds named images and colors in the asset directories given to the renderer:
/// `.xcassets` catalogs (imagesets / colorsets) and loose image files.
@MainActor
final class AssetCatalog {
    static let shared = AssetCatalog()
    var directories: [String] = [] { didSet { index = nil; bitmaps = [:] } }
    private var index: [String: [String]]?
    private var bitmaps: [String: Bitmap?] = [:]

    /// name -> candidate file paths (imageset members or loose files), built lazily.
    private func buildIndex() -> [String: [String]] {
        var result: [String: [String]] = [:]
        let fm = FileManager.default
        for dir in directories {
            guard let walker = fm.enumerator(atPath: dir) else { continue }
            for case let rel as String in walker {
                let path = dir + "/" + rel
                let ns = rel as NSString
                let ext = ns.pathExtension.lowercased()
                if ext == "imageset" || ext == "colorset" {
                    let name = (ns.lastPathComponent as NSString).deletingPathExtension
                    let files = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted().map { path + "/" + $0 }
                    result[ext == "colorset" ? "color:" + name : name, default: []] += files
                } else if ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains(ext), !rel.contains(".imageset/") {
                    var name = (ns.lastPathComponent as NSString).deletingPathExtension
                    for suffix in ["@2x", "@3x"] where name.hasSuffix(suffix) { name.removeLast(3) }
                    result[name, default: []].append(path)
                }
            }
        }
        return result
    }

    func bitmap(named name: String, scheme: ColorScheme) -> Bitmap? {
        let key = name + (scheme == .dark ? "#dark" : "")
        if let cached = bitmaps[key] { return cached }
        if index == nil { index = buildIndex() }
        let stem = (name as NSString).deletingPathExtension
        let candidates = (index?[name] ?? index?[stem] ?? []).filter {
            ["png", "jpg", "jpeg", "webp", "gif"].contains(($0 as NSString).pathExtension.lowercased())
        }
        // Prefer the highest-resolution variant.
        func scale(_ path: String) -> CGFloat { path.contains("@3x") ? 3 : path.contains("@2x") ? 2 : 1 }
        let best = candidates.max { scale($0) < scale($1) }
        let bitmap = best.flatMap { Bitmap(path: $0, scale: scale($0)) }
        bitmaps[key] = bitmap
        return bitmap
    }

    func color(named name: String, scheme: ColorScheme) -> RGBA? {
        if index == nil { index = buildIndex() }
        guard let contents = index?["color:" + name]?.first(where: { $0.hasSuffix("Contents.json") }),
              let data = FileManager.default.contents(atPath: contents),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let colors = json["colors"] as? [[String: Any]] else { return nil }
        func isDark(_ entry: [String: Any]) -> Bool {
            ((entry["appearances"] as? [[String: Any]]) ?? []).contains { ($0["value"] as? String) == "dark" }
        }
        let entry = colors.first { isDark($0) == (scheme == .dark) } ?? colors.first { !isDark($0) } ?? colors.first
        guard let components = (entry?["color"] as? [String: Any])?["components"] as? [String: Any] else { return nil }
        func component(_ key: String) -> Double {
            guard let raw = components[key] else { return 0 }
            if let n = raw as? NSNumber { return n.doubleValue }
            guard let s = raw as? String else { return 0 }
            if s.hasPrefix("0x") { return Double(UInt8(s.dropFirst(2), radix: 16) ?? 0) / 255 }
            let v = Double(s) ?? 0
            return v > 1 ? v / 255 : v
        }
        return RGBA(component("red"), component("green"), component("blue"), components["alpha"] == nil ? 1 : component("alpha"))
    }
}

public struct Image: Equatable, Sendable {
    public enum ResizingMode: Hashable, Sendable { case tile, stretch }
    public enum TemplateRenderingMode: Hashable, Sendable { case template, original }
    public enum Interpolation: Hashable, Sendable { case none, low, medium, high }
    public enum Scale: Hashable, Sendable { case small, medium, large }
    public enum Orientation: UInt8, Hashable, Sendable { case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored }

    enum Source: Equatable, Sendable {
        case named(String)
        case system(String)
        case file(String)
    }
    var source: Source
    /// `Image(decorative:)`: hidden from assistive technology.
    var isDecorative = false
    /// `Image(_:label:)`: the accessibility label.
    var accessibilityLabelText: String?
    var isResizable = false
    var renderingMode: TemplateRenderingMode?
    var symbolMode: SymbolRenderingMode?

    public init(_ name: String, bundle: Bundle? = nil) { source = .named(name) }
    public init(_ name: String, bundle: Bundle? = nil, label: Text) { source = .named(name); accessibilityLabelText = label.plainString }
    public init(decorative name: String, bundle: Bundle? = nil) { source = .named(name); isDecorative = true }
    public init(systemName: String) { source = .system(systemName) }
    public init(systemName: String, variableValue: Double?) { source = .system(systemName) }
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) { source = .named(name) }

    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        copy.isResizable = true
        return copy
    }
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var copy = self
        copy.renderingMode = renderingMode
        return copy
    }
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image {
        var copy = self
        copy.symbolMode = mode
        return copy
    }
    public func interpolation(_ interpolation: Interpolation) -> Image { self }
    public func antialiased(_ isAntialiased: Bool) -> Image { self }
}

public struct SymbolRenderingMode: Hashable, Sendable {
    let raw: Int
    public static let monochrome = SymbolRenderingMode(raw: 0)
    public static let multicolor = SymbolRenderingMode(raw: 1)
    public static let hierarchical = SymbolRenderingMode(raw: 2)
    public static let palette = SymbolRenderingMode(raw: 3)
}

public struct SymbolVariants: Hashable, Sendable {
    var suffixes: [String] = []
    public static let none = SymbolVariants()
    public static let fill = SymbolVariants(suffixes: ["fill"])
    public static let circle = SymbolVariants(suffixes: ["circle"])
    public static let square = SymbolVariants(suffixes: ["square"])
    public static let rectangle = SymbolVariants(suffixes: ["rectangle"])
    public static let slash = SymbolVariants(suffixes: ["slash"])
    public var fill: SymbolVariants { SymbolVariants(suffixes: suffixes + ["fill"]) }
    public var circle: SymbolVariants { SymbolVariants(suffixes: suffixes + ["circle"]) }
    public var square: SymbolVariants { SymbolVariants(suffixes: suffixes + ["square"]) }
    public var rectangle: SymbolVariants { SymbolVariants(suffixes: suffixes + ["rectangle"]) }
    public var slash: SymbolVariants { SymbolVariants(suffixes: suffixes + ["slash"]) }
    public func contains(_ other: SymbolVariants) -> Bool { other.suffixes.allSatisfy(suffixes.contains) }
}

enum ImageScaleKey: EnvironmentKey { static let defaultValue = Image.Scale.medium }
enum SymbolVariantsKey: EnvironmentKey { static let defaultValue = SymbolVariants.none }
enum SymbolRenderingModeKey: EnvironmentKey { static let defaultValue: SymbolRenderingMode? = nil }

extension EnvironmentValues {
    public var imageScale: Image.Scale {
        get { self[ImageScaleKey.self] }
        set { self[ImageScaleKey.self] = newValue }
    }
    public var symbolVariants: SymbolVariants {
        get { self[SymbolVariantsKey.self] }
        set { self[SymbolVariantsKey.self] = newValue }
    }
    public var symbolRenderingMode: SymbolRenderingMode? {
        get { self[SymbolRenderingModeKey.self] }
        set { self[SymbolRenderingModeKey.self] = newValue }
    }
}

extension View {
    public func imageScale(_ scale: Image.Scale) -> some View { env { $0.imageScale = scale } }
    public func symbolVariant(_ variant: SymbolVariants) -> some View { env { $0.symbolVariants = variant } }
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View { env { $0.symbolRenderingMode = mode } }
}

/// What an Image draws once its source is looked up.
enum ImageContent {
    case bitmap(Bitmap, template: _Paint?)
    case symbol(SymbolGlyph, paint: _Paint)
    case missing(String)

    var naturalSize: CGSize {
        switch self {
        case .bitmap(let b, _): return b.pointSize
        case .symbol(let s, _): return s.size
        case .missing: return CGSize(width: 24, height: 24)
        }
    }

    @MainActor func draw(_ p: Painter, in rect: CGRect) {
        switch self {
        case .bitmap(let bitmap, let template):
            if p.suppressesDrawing { return }
            var dst = Painter.skRect(rect)
            var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                                 fFilter: LINEAR_SK_FILTER_MODE, fMipmap: LINEAR_SK_MIPMAP_MODE)
            if let template {
                // Template images are drawn as a mask filled with the foreground style.
                p.saveLayer(.init(bounds: rect))
                sk_canvas_draw_image_rect(p.canvas, bitmap.image, nil, &dst, &sampling, nil)
                let paint = p.makePaint(template.kind, bounds: rect)
                sk_paint_set_blendmode(paint, SRCIN_SK_BLENDMODE)
                sk_canvas_draw_rect(p.canvas, &dst, paint)
                sk_paint_delete(paint)
                p.restore()
            } else {
                sk_canvas_draw_image_rect(p.canvas, bitmap.image, nil, &dst, &sampling, nil)
            }
        case .symbol(let symbol, let paint):
            symbol.draw(p, in: rect, paint: paint)
        case .missing:
            // A visible placeholder: dashed box with a cross, so missing assets are obvious.
            let color = _Paint.color(RGBA(0.56, 0.56, 0.58, 1))
            let box = rect.insetBy(dx: 1, dy: 1)
            p.stroke(Path(roundedRect: box, cornerRadius: min(4, box.width / 6), style: .circular), with: color,
                     style: StrokeStyle(lineWidth: 1, dash: [3, 2]), in: rect)
            var cross = Path()
            cross.move(to: CGPoint(x: box.minX, y: box.minY)); cross.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            cross.move(to: CGPoint(x: box.maxX, y: box.minY)); cross.addLine(to: CGPoint(x: box.minX, y: box.maxY))
            p.stroke(cross, with: color, style: StrokeStyle(lineWidth: 0.5), in: rect)
        }
    }
}

extension Image {
    @MainActor
    func content(in env: EnvironmentValues, font: ResolvedFont? = nil, paint: _Paint? = nil) -> ImageContent {
        let foreground = paint ?? ForegroundStyle()._paint(in: env)
        switch source {
        case .system(let name):
            let font = font ?? (env.font ?? .body).resolve(in: env)
            if let glyph = SymbolLibrary.shared.glyph(named: name, variants: env.symbolVariants, font: font, scale: env.imageScale) {
                return .symbol(glyph, paint: foreground)
            }
            Runtime.current?.warn("SF Symbol \"\(name)\" has no open-source equivalent mapped; rendered as a placeholder")
            let side = font.size * 1.2
            _ = side
            return .missing(name)
        case .file(let path):
            guard let bitmap = Bitmap(path: path, scale: 1) else { return .missing(path) }
            return .bitmap(bitmap, template: renderingMode == .template ? foreground : nil)
        case .named(let name):
            guard let bitmap = AssetCatalog.shared.bitmap(named: name, scheme: env.colorScheme) else {
                Runtime.current?.warn("Image asset \"\(name)\" not found (pass --assets <dir>); rendered as a placeholder")
                return .missing(name)
            }
            return .bitmap(bitmap, template: renderingMode == .template ? foreground : nil)
        }
    }

    @MainActor
    func inlineAttachment(font: ResolvedFont, paint: _Paint, env: EnvironmentValues) -> InlineAttachment {
        let content = self.content(in: env, font: font, paint: paint)
        var size = content.naturalSize
        if case .bitmap = content {} else if case .missing = content { size = CGSize(width: font.size, height: font.size) }
        // Symbols sit slightly below the baseline, centred on the cap height.
        let descent: CGFloat
        if case .bitmap = content { descent = 0 } else { descent = max(0, (size.height - font.size * 0.7) / 2) }
        return InlineAttachment(size: size, descent: descent) { p, rect in content.draw(p, in: rect) }
    }
}

final class ImageNode: Node {
    let content: ImageContent
    let isResizable: Bool
    /// Where the image came from, for accessibility labels (set by `Image.resolve`).
    var imageSource: Image.Source?
    var isDecorative = false
    var accessibilityLabelText: String?
    init(content: ImageContent, isResizable: Bool) {
        self.content = content
        self.isResizable = isResizable
        super.init()
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let natural = content.naturalSize
        guard isResizable else { return natural }
        return CGSize(width: proposal.width ?? natural.width, height: proposal.height ?? natural.height)
    }
    override func drawContent(_ p: Painter) {
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return }
        content.draw(p, in: CGRect(origin: .zero, size: frame.size))
    }
}

extension Image: View, PrimitiveView {
    public typealias Body = Never
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        var env = ctx.env
        if let symbolMode { env.symbolRenderingMode = symbolMode }
        let node = ImageNode(content: content(in: env), isResizable: isResizable)
        node.imageSource = source
        node.isDecorative = isDecorative
        node.accessibilityLabelText = accessibilityLabelText
        out.append(node)
    }
}

// MARK: - Symbols

/// A vector icon standing in for an SF Symbol, already sized for a font.
struct SymbolGlyph {
    struct Layer {
        var path: Path
        var stroke: StrokeStyle?
        var evenOdd = false
    }
    /// Layout size in points.
    var size: CGSize
    /// Paths in a `viewBox`-sized coordinate space.
    var viewBox: CGSize
    var layers: [Layer]

    @MainActor func draw(_ p: Painter, in rect: CGRect, paint: _Paint) {
        guard viewBox.width > 0, viewBox.height > 0 else { return }
        // Fit the artwork into the rect, preserving aspect.
        let s = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * s) / 2, dy = rect.minY + (rect.height - viewBox.height * s) / 2
        let transform = CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: dx, y: dy))
        for layer in layers {
            let path = layer.path.applying(transform)
            if var stroke = layer.stroke {
                stroke.lineWidth *= s
                p.stroke(path, with: paint, style: stroke, in: rect)
            } else {
                p.fill(path, with: paint, in: rect, style: FillStyle(eoFill: layer.evenOdd))
            }
        }
    }
}

/// Maps SF Symbol names to open-source vector icons. Populated by the symbol set loaded at startup.
@MainActor
final class SymbolLibrary {
    static let shared = SymbolLibrary()
    /// Looks up artwork for a (variant-qualified) SF Symbol name; installed by the icon set.
    var provider: ((String) -> (viewBox: CGSize, layers: [SymbolGlyph.Layer])?)?

    func glyph(named name: String, variants: SymbolVariants, font: ResolvedFont, scale: Image.Scale) -> SymbolGlyph? {
        // Without an installed provider, fall back to the bundled Phosphor-based artwork (Symbols/).
        let lookup: (String) -> (viewBox: CGSize, layers: [SymbolGlyph.Layer])? = provider
            ?? { SymbolArtwork.shared.art(named: $0, weight: font.weight) }
        // Environment variants are appended to the name when that variant exists (heart -> heart.fill).
        var candidates = [name]
        if !variants.suffixes.isEmpty {
            let parts = name.split(separator: ".").map(String.init)
            let extra = variants.suffixes.filter { !parts.contains($0) }
            if !extra.isEmpty { candidates.insert((parts + extra).joined(separator: "."), at: 0) }
        }
        let factor: CGFloat = scale == .small ? 0.82 : scale == .large ? 1.28 : 1
        // Apple's own artwork, when the user has installed SF Pro and a symbol name map.
        if provider == nil, AppleSymbols.shared.isAvailable {
            for candidate in candidates {
                if let glyph = AppleSymbols.shared.glyph(named: candidate, weight: font.weight, pointSize: font.size * factor) { return glyph }
            }
        }
        for candidate in candidates {
            guard let art = lookup(candidate) else { continue }
            // SF Symbols are drawn roughly 1.2x the point size tall at medium scale.
            let height = font.size * 1.2 * factor
            let width = height * art.viewBox.width / max(art.viewBox.height, 1)
            return SymbolGlyph(size: CGSize(width: width, height: height), viewBox: art.viewBox, layers: art.layers)
        }
        return nil
    }
}
