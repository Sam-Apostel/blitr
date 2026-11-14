internal import CSkia

// CGContext as a bitmap context drawn by Skia. A context made with `CGContext(data:width:...)` has
// CoreGraphics' own coordinate system (origin bottom-left, y up); the ones `UIGraphicsImageRenderer`
// hands out are flipped to UIKit's (origin top-left, in points), exactly as on iOS.

public enum CGBlendMode: Int32, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity
    case clear, copy, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop
    case xor, plusDarker, plusLighter

    var sk: sk_blendmode_t {
        switch self {
        case .normal: return SRCOVER_SK_BLENDMODE
        case .multiply: return MULTIPLY_SK_BLENDMODE
        case .screen: return SCREEN_SK_BLENDMODE
        case .overlay: return OVERLAY_SK_BLENDMODE
        case .darken: return DARKEN_SK_BLENDMODE
        case .lighten: return LIGHTEN_SK_BLENDMODE
        case .colorDodge: return COLORDODGE_SK_BLENDMODE
        case .colorBurn: return COLORBURN_SK_BLENDMODE
        case .softLight: return SOFTLIGHT_SK_BLENDMODE
        case .hardLight: return HARDLIGHT_SK_BLENDMODE
        case .difference: return DIFFERENCE_SK_BLENDMODE
        case .exclusion: return EXCLUSION_SK_BLENDMODE
        case .hue: return HUE_SK_BLENDMODE
        case .saturation: return SATURATION_SK_BLENDMODE
        case .color: return COLOR_SK_BLENDMODE
        case .luminosity: return LUMINOSITY_SK_BLENDMODE
        case .clear: return CLEAR_SK_BLENDMODE
        case .copy: return SRC_SK_BLENDMODE
        case .sourceIn: return SRCIN_SK_BLENDMODE
        case .sourceOut: return SRCOUT_SK_BLENDMODE
        case .sourceAtop: return SRCATOP_SK_BLENDMODE
        case .destinationOver: return DSTOVER_SK_BLENDMODE
        case .destinationIn: return DSTIN_SK_BLENDMODE
        case .destinationOut: return DSTOUT_SK_BLENDMODE
        case .destinationAtop: return DSTATOP_SK_BLENDMODE
        case .xor: return XOR_SK_BLENDMODE
        case .plusDarker: return DARKEN_SK_BLENDMODE
        case .plusLighter: return PLUS_SK_BLENDMODE
        }
    }
}

public enum CGInterpolationQuality: Int32, Sendable { case `default`, none, low, high, medium }
public enum CGTextDrawingMode: Int32, Sendable { case fill, stroke, fillStroke, invisible, fillClip, strokeClip, fillStrokeClip, clip }

public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 2)
}

public final class CGGradient: @unchecked Sendable {
    let stops: [(color: RGBA, location: Double)]

    /// `colors` is an array of `CGColor`; without `locations` they are spread evenly.
    public init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: UnsafePointer<CGFloat>?) {
        let list = (0..<colors.count).compactMap { colors.object(at: $0) as? CGColor }
        guard !list.isEmpty, list.count == colors.count else { return nil }
        stops = list.enumerated().map { index, color in
            let location = locations.map { Double($0[index]) } ?? (list.count > 1 ? Double(index) / Double(list.count - 1) : 0)
            return (color.rgba, location)
        }
    }
    /// `components` holds `count` colors of the space's components plus alpha.
    public init?(colorSpace space: CGColorSpace, colorComponents components: UnsafePointer<CGFloat>, locations: UnsafePointer<CGFloat>?, count: Int) {
        guard count > 0 else { return nil }
        let n = space.numberOfComponents + 1
        stops = (0..<count).map { index in
            let c = Array(UnsafeBufferPointer(start: components + index * n, count: n))
            let location = locations.map { Double($0[index]) } ?? (count > 1 ? Double(index) / Double(count - 1) : 0)
            return (CGColor.rgba(space: space, c), location)
        }
    }
}

typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

func skPoint(_ p: CGPoint) -> sk_point_t { sk_point_t(x: Float(p.x), y: Float(p.y)) }
func skColor(_ c: RGBA) -> sk_color_t {
    func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
    return (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b)
}
extension PathData {
    static func rect(_ r: CGRect) -> PathData { var p = PathData(); p.addRect(r); return p }
    static func ellipse(_ r: CGRect) -> PathData { var p = PathData(); p.addEllipse(in: r); return p }
}

public final class CGContext: @unchecked Sendable {
    private let surface: OpaquePointer
    package let canvas: OpaquePointer
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bytesPerRow: Int
    public let colorSpace: CGColorSpace?
    public let bitmapInfo: CGBitmapInfo
    public var alphaInfo: CGImageAlphaInfo { bitmapInfo.alpha }
    /// The pixels being drawn into.
    public let data: UnsafeMutableRawPointer?
    private let ownedData: UnsafeMutableRawPointer?
    /// User space to pixels before any CTM change: the y flip of a plain bitmap context, or the
    /// point scale of a UIKit one.
    package let base: CGAffineTransform
    private let isOpaque: Bool

    private struct State {
        var ctm = CGAffineTransform.identity
        var fill: RGBA = (0, 0, 0, 1)
        var stroke: RGBA = (0, 0, 0, 1)
        var lineWidth: CGFloat = 1
        var lineCap = CGLineCap.butt
        var lineJoin = CGLineJoin.miter
        var miterLimit: CGFloat = 10
        var dash: [CGFloat] = []
        var dashPhase: CGFloat = 0
        var alpha: CGFloat = 1
        var blend = CGBlendMode.normal
        var shadow: (offset: CGSize, blur: CGFloat, color: RGBA)?
        var antialias = true
        var interpolation = CGInterpolationQuality.default
        var textMode = CGTextDrawingMode.fill
    }
    private var state = State()
    private var stack: [State] = []
    /// The current path, in user space as it was when each point was added (CTM already applied).
    private var current = PathData()

    public var interpolationQuality: CGInterpolationQuality {
        get { state.interpolation }
        set { state.interpolation = newValue }
    }
    public var textMatrix = CGAffineTransform.identity
    public var textPosition = CGPoint.zero

    // MARK: Creation

    public convenience init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: UInt32) {
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
        self.init(data: data, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: space,
                  info: CGBitmapInfo(rawValue: bitmapInfo), base: flip)
    }
    public convenience init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: CGBitmapInfo) {
        self.init(data: data, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: space,
                  bitmapInfo: bitmapInfo.rawValue)
    }

    /// A context in UIKit's coordinate system: `pixelsPerPoint` scale, origin top-left.
    package static func uikit(size: CGSize, scale: CGFloat, opaque: Bool) -> CGContext? {
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        let info = CGBitmapInfo(rawValue: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: .srgb, info: info,
                         base: CGAffineTransform(scaleX: scale, y: scale))
    }

    package init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace,
          info: CGBitmapInfo, base: CGAffineTransform) {
        guard width > 0, height > 0, width <= 32767, height <= 32767 else { return nil }
        // The layouts CoreGraphics supports for 8-bit bitmap contexts, as Skia color types.
        let colorType: sk_colortype_t, alphaType: sk_alphatype_t, pixelBytes: Int
        switch (space.model, bitsPerComponent, info.alpha, info.byteOrder) {
        case (.rgb, 8, .premultipliedLast, .orderDefault), (.rgb, 8, .premultipliedLast, .order32Big):
            (colorType, alphaType, pixelBytes) = (RGBA_8888_SK_COLORTYPE, PREMUL_SK_ALPHATYPE, 4)
        case (.rgb, 8, .noneSkipLast, .orderDefault), (.rgb, 8, .noneSkipLast, .order32Big):
            (colorType, alphaType, pixelBytes) = (RGB_888X_SK_COLORTYPE, OPAQUE_SK_ALPHATYPE, 4)
        case (.rgb, 8, .premultipliedFirst, .order32Little):
            (colorType, alphaType, pixelBytes) = (BGRA_8888_SK_COLORTYPE, PREMUL_SK_ALPHATYPE, 4)
        case (.rgb, 8, .noneSkipFirst, .order32Little):
            (colorType, alphaType, pixelBytes) = (BGRA_8888_SK_COLORTYPE, OPAQUE_SK_ALPHATYPE, 4)
        case (.monochrome, 8, .none, _):
            (colorType, alphaType, pixelBytes) = (GRAY_8_SK_COLORTYPE, OPAQUE_SK_ALPHATYPE, 1)
        case (_, 8, .alphaOnly, _):
            (colorType, alphaType, pixelBytes) = (ALPHA_8_SK_COLORTYPE, PREMUL_SK_ALPHATYPE, 1)
        default:
            ShimDiagnostics.warn("CGContext: unsupported bitmap layout (\(space.model), \(bitsPerComponent) bits per component, alpha \(info.alpha), byte order \(info.byteOrder)); supported are 8-bit RGBA, RGBX, BGRA, BGRX, gray and alpha-only")
            return nil
        }
        let rowBytes = bytesPerRow == 0 ? width * pixelBytes : bytesPerRow
        guard rowBytes >= width * pixelBytes else { return nil }
        var pixels = data
        if pixels == nil {
            ownedData = calloc(height, rowBytes)
            pixels = ownedData
        } else {
            ownedData = nil
        }
        guard let pixels else { return nil }
        var imageInfo = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(width), height: Int32(height),
                                       colorType: colorType, alphaType: alphaType)
        defer { sk_colorspace_unref(imageInfo.colorspace) }
        guard let surface = sk_surface_new_raster_direct(&imageInfo, pixels, rowBytes, nil, nil, nil),
              let canvas = sk_surface_get_canvas(surface) else {
            free(ownedData)
            return nil
        }
        self.surface = surface
        self.canvas = canvas
        self.data = pixels
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        bitsPerPixel = pixelBytes * 8
        self.bytesPerRow = rowBytes
        colorSpace = space
        bitmapInfo = info
        self.base = base
        isOpaque = alphaType == OPAQUE_SK_ALPHATYPE
        if isOpaque && ownedData != nil { sk_canvas_clear(canvas, 0xFF00_0000) }
    }

    deinit {
        sk_surface_unref(surface)
        free(ownedData)
    }

    /// A snapshot of what has been drawn.
    public func makeImage() -> CGImage? {
        guard let snapshot = sk_surface_new_image_snapshot(surface) else { return nil }
        // The snapshot shares the context's pixels while nothing is drawn; copy them so the image is immutable.
        let raster = sk_image_make_raster_image(snapshot)
        sk_image_unref(snapshot)
        return raster.map { CGImage(box: SkImageBox(adopting: $0)) }
    }

    public func flush() {}
    public func synchronize() {}

    // MARK: Graphics state

    public func saveGState() {
        stack.append(state)
        sk_canvas_save(canvas)
    }
    public func restoreGState() {
        guard let previous = stack.popLast() else { return }
        state = previous
        sk_canvas_restore(canvas)
    }

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = state.ctm.translatedBy(x: x, y: y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = state.ctm.scaledBy(x: x, y: y) }
    public func rotate(by angle: CGFloat) { state.ctm = state.ctm.rotated(by: angle) }
    public func concatenate(_ transform: CGAffineTransform) { state.ctm = transform.concatenating(state.ctm) }
    public var userSpaceToDeviceSpaceTransform: CGAffineTransform { state.ctm.concatenating(base) }
    public func convertToDeviceSpace(_ point: CGPoint) -> CGPoint { point.applying(userSpaceToDeviceSpaceTransform) }
    public func convertToUserSpace(_ point: CGPoint) -> CGPoint { point.applying(userSpaceToDeviceSpaceTransform.inverted()) }

    public func setFillColor(_ color: CGColor) { state.fill = color.rgba }
    public func setStrokeColor(_ color: CGColor) { state.stroke = color.rgba }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        state.fill = (Double(red), Double(green), Double(blue), Double(alpha))
    }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        state.stroke = (Double(red), Double(green), Double(blue), Double(alpha))
    }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { setFillColor(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { setStrokeColor(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setFillColor(cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) {
        state.fill = CGColor.rgba(space: .deviceCMYK, [cyan, magenta, yellow, black, alpha])
    }
    public func setStrokeColor(cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) {
        state.stroke = CGColor.rgba(space: .deviceCMYK, [cyan, magenta, yellow, black, alpha])
    }
    public func setFillColorSpace(_ space: CGColorSpace) {}
    public func setStrokeColorSpace(_ space: CGColorSpace) {}
    public func setLineWidth(_ width: CGFloat) { state.lineWidth = width }
    public func setLineCap(_ cap: CGLineCap) { state.lineCap = cap }
    public func setLineJoin(_ join: CGLineJoin) { state.lineJoin = join }
    public func setMiterLimit(_ limit: CGFloat) { state.miterLimit = limit }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { state.dash = lengths; state.dashPhase = phase }
    public func setFlatness(_ flatness: CGFloat) {}
    public func setAlpha(_ alpha: CGFloat) { state.alpha = max(0, min(1, alpha)) }
    public func setBlendMode(_ mode: CGBlendMode) { state.blend = mode }
    public func setShouldAntialias(_ shouldAntialias: Bool) { state.antialias = shouldAntialias }
    public func setAllowsAntialiasing(_ allowsAntialiasing: Bool) { if !allowsAntialiasing { state.antialias = false } }
    public func setShouldSmoothFonts(_ shouldSmoothFonts: Bool) {}
    public func setRenderingIntent(_ intent: CGColorRenderingIntent) {}
    public func setTextDrawingMode(_ mode: CGTextDrawingMode) { state.textMode = mode }
    public func setCharacterSpacing(_ spacing: CGFloat) {}
    /// The offset and blur are in pixels of the context, unaffected by the CTM, as in CoreGraphics.
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        state.shadow = color.map { (offset, blur, $0.rgba) }
    }
    public func setShadow(offset: CGSize, blur: CGFloat) {
        state.shadow = (offset, blur, (0, 0, 0, 1.0 / 3))
    }

    // MARK: Path construction

    public func beginPath() { current = PathData() }
    public func closePath() { current.close() }
    public func move(to point: CGPoint) { current.move(to: point.applying(state.ctm)) }
    public func addLine(to point: CGPoint) { current.line(to: point.applying(state.ctm)) }
    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        current.move(to: first.applying(state.ctm))
        for p in points.dropFirst() { current.line(to: p.applying(state.ctm)) }
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        current.quad(to: end.applying(state.ctm), control: control.applying(state.ctm))
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        current.curve(to: end.applying(state.ctm), control1: control1.applying(state.ctm), control2: control2.applying(state.ctm))
    }
    public func addRect(_ rect: CGRect) { current.addRect(rect, state.ctm) }
    public func addRects(_ rects: [CGRect]) { rects.forEach { current.addRect($0, state.ctm) } }
    public func addEllipse(in rect: CGRect) { current.addEllipse(in: rect, state.ctm) }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        current.addArc(center: center, radius: radius, start: startAngle, end: endAngle, clockwise: clockwise, state.ctm)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {
        current.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius, state.ctm)
    }
    public func addPath(_ other: CGPath) { current.elements += other.data.applying(state.ctm).elements }
    public func replacePathWithStrokedPath() {
        current = userPath.stroked(width: state.lineWidth, cap: state.lineCap, join: state.lineJoin, miter: state.miterLimit).applying(state.ctm)
    }

    public var isPathEmpty: Bool { current.isEmpty }
    public var currentPointOfPath: CGPoint { (current.currentPoint ?? .zero).applying(state.ctm.inverted()) }
    public var boundingBoxOfPath: CGRect { userPath.tightBounds }
    /// A copy of the current path, in user space.
    public var path: CGPath? { current.isEmpty ? nil : CGPath(data: userPath) }
    public func pathContains(_ point: CGPoint, mode: CGPathDrawingMode) -> Bool {
        userPath.contains(point, evenOdd: mode == .eoFill || mode == .eoFillStroke)
    }

    private var userPath: PathData { current.applying(state.ctm.inverted()) }

    // MARK: Painting

    public func fillPath(using rule: CGPathFillRule = .winding) { draw(current, fill: rule); current = PathData() }
    public func strokePath() { draw(current, stroke: true); current = PathData() }
    public func drawPath(using mode: CGPathDrawingMode) {
        if mode != .stroke { draw(current, fill: mode == .eoFill || mode == .eoFillStroke ? .evenOdd : .winding) }
        if mode == .stroke || mode == .fillStroke || mode == .eoFillStroke { draw(current, stroke: true) }
        current = PathData()
    }

    public func fill(_ rect: CGRect) { draw(PathData.rect(rect).applying(state.ctm), fill: .winding) }
    public func fill(_ rects: [CGRect]) {
        var p = PathData()
        rects.forEach { p.addRect($0) }
        draw(p.applying(state.ctm), fill: .winding)
    }
    public func stroke(_ rect: CGRect) { draw(PathData.rect(rect).applying(state.ctm), stroke: true) }
    public func stroke(_ rect: CGRect, width: CGFloat) {
        let previous = state.lineWidth
        state.lineWidth = width
        stroke(rect)
        state.lineWidth = previous
    }
    public func fillEllipse(in rect: CGRect) { draw(PathData.ellipse(rect).applying(state.ctm), fill: .winding) }
    public func strokeEllipse(in rect: CGRect) { draw(PathData.ellipse(rect).applying(state.ctm), stroke: true) }
    public func strokeLineSegments(between points: [CGPoint]) {
        var p = PathData()
        var index = 0
        while index + 1 < points.count {
            p.move(to: points[index]); p.line(to: points[index + 1])
            index += 2
        }
        draw(p.applying(state.ctm), stroke: true)
    }
    /// Makes the pixels in `rect` transparent (black in an opaque context).
    public func clear(_ rect: CGRect) {
        let saved = state
        state.blend = isOpaque ? .copy : .clear
        state.fill = isOpaque ? (0, 0, 0, 1) : (0, 0, 0, 0)
        state.alpha = 1
        state.shadow = nil
        draw(PathData.rect(rect).applying(state.ctm), fill: .winding)
        state = saved
    }

    // MARK: Clipping

    public func clip(using rule: CGPathFillRule = .winding) {
        setMatrix(base)
        current.withSkPath(evenOdd: rule == .evenOdd) { sk_canvas_clip_path_with_operation(canvas, $0, INTERSECT_SK_CLIPOP, state.antialias) }
        current = PathData()
    }
    public func clip(to rect: CGRect) {
        setMatrix(base)
        PathData.rect(rect).applying(state.ctm).withSkPath { sk_canvas_clip_path_with_operation(canvas, $0, INTERSECT_SK_CLIPOP, state.antialias) }
    }
    public func clip(to rects: [CGRect]) {
        var p = PathData()
        rects.forEach { p.addRect($0) }
        setMatrix(base)
        p.applying(state.ctm).withSkPath { sk_canvas_clip_path_with_operation(canvas, $0, INTERSECT_SK_CLIPOP, state.antialias) }
    }
    /// Clips to the alpha of `mask` drawn in `rect`: what follows only shows where the mask is opaque.
    public func clip(to rect: CGRect, mask: CGImage) {
        ShimDiagnostics.warn("CGContext.clip(to:mask:) clips to the mask's rectangle, not its alpha")
        clip(to: rect)
    }
    public var boundingBoxOfClipPath: CGRect {
        var bounds = sk_rect_t()
        setMatrix(state.ctm.concatenating(base))
        guard sk_canvas_get_local_clip_bounds(canvas, &bounds) else { return .null }
        return CGRect(x: CGFloat(bounds.left), y: CGFloat(bounds.top), width: CGFloat(bounds.right - bounds.left), height: CGFloat(bounds.bottom - bounds.top))
    }

    // MARK: Images and gradients

    /// Draws the image upright in user space, which in a UIKit (flipped) context is upside down,
    /// as it is on iOS; `UIImage.draw(in:)` is the one that compensates.
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        guard rect.width != 0, rect.height != 0 else { return }
        let fit = CGAffineTransform(a: rect.width / CGFloat(image.width), b: 0, c: 0, d: -rect.height / CGFloat(image.height),
                                    tx: rect.minX, ty: rect.maxY)
        drawImage(image.box, transform: fit.concatenating(state.ctm), tile: byTiling)
    }

    /// Draws `box` with its top-left pixel at the origin of `transform`'s space.
    package func drawImage(_ box: SkImageBox, transform: CGAffineTransform, tile: Bool = false) {
        setMatrix(transform.concatenating(base))
        let paint = makePaint(color: (0, 0, 0, 1))
        defer { sk_paint_delete(paint) }
        var sampling = SkImageBox.sampling(smooth: state.interpolation != .none, mipmaps: true)
        if tile {
            let shader = sk_image_make_shader(box.image, REPEAT_SK_SHADER_TILEMODE, REPEAT_SK_SHADER_TILEMODE, &sampling, nil)
            sk_paint_set_shader(paint, shader)
            sk_shader_unref(shader)
            sk_canvas_draw_paint(canvas, paint)
        } else {
            sk_canvas_draw_image(canvas, box.image, 0, 0, &sampling, paint)
        }
    }

    public func drawLinearGradient(_ gradient: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        var points = [skPoint(start), skPoint(end)]
        drawGradient(gradient, options: options) { colors, positions, count, mode in
            sk_shader_new_linear_gradient_color4f(&points, colors, nil, positions, count, mode, nil)
        } bounded: {
            // Without an option the gradient stops at its end line: clip to that side.
            guard options != [.drawsBeforeStartLocation, .drawsAfterEndLocation], !options.isEmpty else { return nil }
            let d = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let length = max(hypot(d.x, d.y), 0.0001), far: CGFloat = 1e5
            let u = CGPoint(x: d.x / length, y: d.y / length), n = CGPoint(x: -u.y, y: u.x)
            let origin = options.contains(.drawsAfterEndLocation) ? start : end
            let sign: CGFloat = options.contains(.drawsAfterEndLocation) ? 1 : -1
            var half = PathData()
            half.move(to: CGPoint(x: origin.x + n.x * far, y: origin.y + n.y * far))
            half.line(to: CGPoint(x: origin.x - n.x * far, y: origin.y - n.y * far))
            half.line(to: CGPoint(x: origin.x - n.x * far + u.x * far * sign, y: origin.y - n.y * far + u.y * far * sign))
            half.line(to: CGPoint(x: origin.x + n.x * far + u.x * far * sign, y: origin.y + n.y * far + u.y * far * sign))
            half.close()
            return half
        }
    }

    public func drawRadialGradient(_ gradient: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat,
                                   options: CGGradientDrawingOptions) {
        var c0 = skPoint(startCenter), c1 = skPoint(endCenter)
        drawGradient(gradient, options: options) { colors, positions, count, mode in
            sk_shader_new_two_point_conical_gradient_color4f(&c0, Float(startRadius), &c1, Float(endRadius), colors, nil, positions, count, mode, nil)
        } bounded: { nil }
    }

    private func drawGradient(_ gradient: CGGradient, options: CGGradientDrawingOptions,
                              shader make: (UnsafePointer<sk_color4f_t>, UnsafePointer<Float>, Int32, sk_shader_tilemode_t) -> OpaquePointer?,
                              bounded: () -> PathData?) {
        var stops = gradient.stops.sorted { $0.location < $1.location }
        if stops.count == 1 { stops.append(stops[0]) }
        let colors = stops.map { sk_color4f_t(fR: Float($0.color.r), fG: Float($0.color.g), fB: Float($0.color.b), fA: Float($0.color.a)) }
        let positions = stops.map { Float($0.location) }
        guard let shader = make(colors, positions, Int32(colors.count), options.isEmpty ? DECAL_SK_SHADER_TILEMODE : CLAMP_SK_SHADER_TILEMODE) else { return }
        setMatrix(state.ctm.concatenating(base))
        let paint = makePaint(color: (0, 0, 0, 1))
        sk_paint_set_shader(paint, shader)
        sk_shader_unref(shader)
        if let half = bounded() {
            sk_canvas_save(canvas)
            half.withSkPath { sk_canvas_clip_path_with_operation(canvas, $0, INTERSECT_SK_CLIPOP, false) }
            sk_canvas_draw_paint(canvas, paint)
            sk_canvas_restore(canvas)
        } else {
            sk_canvas_draw_paint(canvas, paint)
        }
        sk_paint_delete(paint)
    }

    // MARK: Layers

    public func beginTransparencyLayer(auxiliaryInfo: CFDictionary?) {
        stack.append(state)
        let paint = makePaint(color: (0, 0, 0, 1))
        sk_canvas_save_layer(canvas, nil, paint)
        sk_paint_delete(paint)
        state.alpha = 1
        state.shadow = nil
        state.blend = .normal
    }
    public func beginTransparencyLayer(in rect: CGRect, auxiliaryInfo: CFDictionary?) { beginTransparencyLayer(auxiliaryInfo: auxiliaryInfo) }
    public func endTransparencyLayer() { restoreGState() }

    // MARK: Skia plumbing

    /// For drawing that is not CoreGraphics' own (text through the SwiftUI engine): sets the canvas to the
    /// current transform and returns the pixels per user-space unit.
    package func prepareCanvasForUserSpace() -> CGFloat {
        let t = state.ctm.concatenating(base)
        setMatrix(t)
        return max(abs(t.a * t.d - t.b * t.c).squareRoot(), 0.01)
    }

    private func setMatrix(_ t: CGAffineTransform) {
        var m = sk_matrix44_t(m00: Float(t.a), m01: Float(t.b), m02: 0, m03: 0,
                              m10: Float(t.c), m11: Float(t.d), m12: 0, m13: 0,
                              m20: 0, m21: 0, m22: 1, m23: 0,
                              m30: Float(t.tx), m31: Float(t.ty), m32: 0, m33: 1)
        sk_canvas_set_matrix(canvas, &m)
    }

    /// A paint with the state's alpha, blend mode, antialiasing and shadow.
    private func makePaint(color: RGBA) -> OpaquePointer {
        let paint = sk_paint_new()!
        sk_paint_set_antialias(paint, state.antialias)
        var c = sk_color4f_t(fR: Float(color.r), fG: Float(color.g), fB: Float(color.b), fA: Float(max(0, min(1, color.a * Double(state.alpha)))))
        sk_paint_set_color4f(paint, &c, nil)
        if state.blend != .normal { sk_paint_set_blendmode(paint, state.blend.sk) }
        if let shadow = state.shadow, shadow.color.a > 0 {
            // CoreGraphics measures the offset and blur in pixels of the context (points in a UIKit one),
            // whatever the CTM; Skia maps a paint's filter through the canvas matrix, so undo that here.
            var total = sk_matrix44_t()
            sk_canvas_get_matrix(canvas, &total)
            let m = CGAffineTransform(a: CGFloat(total.m00), b: CGFloat(total.m01), c: CGFloat(total.m10), d: CGFloat(total.m11), tx: 0, ty: 0)
            let det = abs(m.a * m.d - m.b * m.c)
            let device = CGSize(width: shadow.offset.width * abs(base.a), height: shadow.offset.height * base.d)
            let local = det > 0 ? device.applying(m.inverted()) : device
            let sigma = Float(max(shadow.blur, 0) / 2 * abs(base.a) / (det > 0 ? det.squareRoot() : 1))
            let filter = sk_imagefilter_new_drop_shadow(Float(local.width), Float(local.height), sigma, sigma,
                                                        skColor(shadow.color), nil, nil)
            sk_paint_set_imagefilter(paint, filter)
            sk_imagefilter_unref(filter)
        }
        return paint
    }

    private func draw(_ devicePath: PathData, fill rule: CGPathFillRule) {
        guard !devicePath.isEmpty else { return }
        setMatrix(base)
        let paint = makePaint(color: state.fill)
        devicePath.withSkPath(evenOdd: rule == .evenOdd) { sk_canvas_draw_path(canvas, $0, paint) }
        sk_paint_delete(paint)
    }

    private func draw(_ devicePath: PathData, stroke: Bool) {
        guard !devicePath.isEmpty else { return }
        // Stroke in user space so the line width follows the CTM, as in CoreGraphics.
        let det = state.ctm.a * state.ctm.d - state.ctm.b * state.ctm.c
        let paint = makePaint(color: state.stroke)
        PathData.applyStroke(to: paint, width: state.lineWidth, cap: state.lineCap, join: state.lineJoin, miter: state.miterLimit,
                                 dash: state.dash, phase: state.dashPhase)
        if det != 0 {
            setMatrix(state.ctm.concatenating(base))
            devicePath.applying(state.ctm.inverted()).withSkPath { sk_canvas_draw_path(canvas, $0, paint) }
        } else {
            setMatrix(base)
            devicePath.withSkPath { sk_canvas_draw_path(canvas, $0, paint) }
        }
        sk_paint_delete(paint)
    }
}
