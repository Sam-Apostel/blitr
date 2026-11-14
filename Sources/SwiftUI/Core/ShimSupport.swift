// Hooks for the shim framework modules of this package (MapKit, WidgetKit, UIKit, ...), which extend
// SwiftUI types from outside the module. `package` access: app code compiled against the SDK cannot see
// them. See docs/ARCHITECTURE.md, "Shim modules".

extension ForEach {
    /// For `ForEach` conformances in other modules (MapKit's `MapContent`), which cannot assign the stored
    /// properties of a resilient struct themselves.
    package init(_data data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
}

extension Group {
    package init(_content content: Content) { self.content = content }
}

extension ObservedObject.Wrapper {
    /// For `@UIApplicationDelegateAdaptor` (UIKit), whose projected value is an observed object's wrapper.
    package init(_object object: ObjectType) { self.init(object: object) }
}

// MARK: - Fonts and symbols for UIKit's UIFont and UIImage

/// Vertical metrics, as fractions of the point size, of the font that would draw this description.
@MainActor
package func _fontMetrics(name: String?, design: Font.Design, size: CGFloat, weight: CGFloat, italic: Bool, width: CGFloat)
    -> (ascent: CGFloat, descent: CGFloat, capHeight: CGFloat, xHeight: CGFloat) {
    var r = ResolvedFont()
    r.family = name.map { .custom($0) } ?? .system(design)
    r.size = size
    r.weight = weight
    r.italic = italic
    r.width = width
    let instance = FontLibrary.shared.instance(for: r)
    return (instance.ascent, instance.descent, instance.capHeight, instance.xHeight)
}

/// The SF Symbol stand-in drawn in one color into a bitmap at `pixelScale`; nil when no artwork is mapped.
@MainActor
package func _renderSymbol(named name: String, pointSize: CGFloat, weight: Font.Weight, scale: Image.Scale, color: (r: Double, g: Double, b: Double, a: Double),
                           pixelScale: CGFloat) -> CGImage? {
    var font = Font.system(size: pointSize, weight: weight).resolve(in: EnvironmentValues())
    font.size = pointSize
    guard let glyph = SymbolLibrary.shared.glyph(named: name, variants: .none, font: font, scale: scale),
          glyph.size.width > 0, glyph.size.height > 0 else { return nil }
    let box = SkImageBox.render(width: Int((glyph.size.width * pixelScale).rounded(.up)), height: Int((glyph.size.height * pixelScale).rounded(.up))) { canvas in
        let painter = Painter(canvas: canvas, scale: pixelScale)
        painter.scale(pixelScale, pixelScale)
        glyph.draw(painter, in: CGRect(origin: .zero, size: glyph.size), paint: .color(RGBA(color.r, color.g, color.b, color.a)))
    }
    return box.map { CGImage(box: $0) }
}

/// The point size of a symbol image drawn at `pointSize`.
@MainActor
package func _symbolSize(named name: String, pointSize: CGFloat, weight: Font.Weight, scale: Image.Scale) -> CGSize? {
    var font = Font.system(size: pointSize, weight: weight).resolve(in: EnvironmentValues())
    font.size = pointSize
    return SymbolLibrary.shared.glyph(named: name, variants: .none, font: font, scale: scale)?.size
}

// MARK: - Text for UIKit's string drawing (NSString.draw, boundingRect, UILabel sizing)

/// A run of attributed text, described without UIKit types.
package struct _TextSpan {
    package var text: String
    package var fontName: String?
    package var design: Font.Design = .default
    package var size: CGFloat = 17
    package var weight: CGFloat = 400
    package var italic = false
    package var width: CGFloat = 0
    package var color: (r: Double, g: Double, b: Double, a: Double) = (0, 0, 0, 1)
    package var underline = false
    package var strikethrough = false
    package var kern: CGFloat = 0
    package var baselineOffset: CGFloat = 0
    package init(text: String) { self.text = text }

    var run: TextRun {
        var font = ResolvedFont()
        font.family = fontName.map { .custom($0) } ?? .system(design)
        font.size = size
        font.weight = weight
        font.italic = italic
        font.width = width
        let rgba = RGBA(color.r, color.g, color.b, color.a)
        return TextRun(text: text, font: font, paint: .color(rgba), underline: underline ? rgba : nil, strikethrough: strikethrough ? rgba : nil,
                       kerning: kern, baselineOffset: baselineOffset)
    }
}

/// 0 leading, 1 centre, 2 trailing.
private func layoutOptions(alignment: Int, lineLimit: Int?, scale: CGFloat) -> TextLayoutOptions {
    var options = TextLayoutOptions()
    options.alignment = alignment == 1 ? .center : alignment == 2 ? .trailing : .leading
    options.lineLimit = lineLimit
    options.scale = scale
    return options
}

/// The size of the laid-out text, wrapped at `width` (nil: one line per paragraph).
@MainActor
package func _measureText(_ spans: [_TextSpan], width: CGFloat?, alignment: Int = 0, lineLimit: Int? = nil) -> CGSize {
    guard !spans.isEmpty else { return .zero }
    return TextLayout(runs: spans.map(\.run), width: width, options: layoutOptions(alignment: alignment, lineLimit: lineLimit, scale: 3)).size
}

/// Draws the text with its top-left at `rect`'s origin, wrapped at the rect's width when it is finite.
@MainActor
package func _drawText(_ spans: [_TextSpan], in rect: CGRect, context: CGContext, alignment: Int = 0, lineLimit: Int? = nil) {
    guard !spans.isEmpty else { return }
    let scale = context.prepareCanvasForUserSpace()
    let width: CGFloat? = rect.width.isFinite && rect.width > 0 && rect.width < 1e6 ? rect.width : nil
    let layout = TextLayout(runs: spans.map(\.run), width: width, options: layoutOptions(alignment: alignment, lineLimit: lineLimit, scale: scale))
    let painter = Painter(canvas: context.canvas, scale: scale)
    painter.save()
    painter.translate(rect.minX, rect.minY)
    layout.draw(painter, in: CGRect(origin: .zero, size: CGSize(width: width ?? layout.size.width, height: layout.size.height)))
    painter.restore()
}

/// Whether `Font.custom(name, ...)` finds a font (a registered one, or one in the font directories).
@MainActor
package func _hasCustomFont(named name: String) -> Bool { FontLibrary.shared.hasCustomFont(named: name) }
