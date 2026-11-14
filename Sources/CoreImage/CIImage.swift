// `import CoreImage`: CIImage, CIColor, CIContext and CIFilter (with CoreImage.CIFilterBuiltins'
// typed filters). An image is pixels (or a solid color) placed in Core Image's coordinate space
// (origin bottom-left) by a transform; filters rasterize their input and work on the pixels with Skia.
@_exported import CoreGraphics
@_exported import ImageIO
internal import CSkia

public final class CIColor: NSObject, @unchecked Sendable {
    public let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        super.init()
    }
    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1, colorSpace: CGColorSpace) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    public convenience init(cgColor: CGColor) { self.init(red: cgColor.rgba.r, green: cgColor.rgba.g, blue: cgColor.rgba.b, alpha: cgColor.rgba.a) }
    /// "r g b a" with components from 0 to 1, as `stringRepresentation` gives.
    public convenience init(string representation: String) {
        let parts = representation.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
        self.init(red: parts.count > 0 ? parts[0] : 0, green: parts.count > 1 ? parts[1] : 0, blue: parts.count > 2 ? parts[2] : 0, alpha: parts.count > 3 ? parts[3] : 1)
    }
    public var numberOfComponents: Int { 4 }
    public var components: UnsafePointer<CGFloat> {
        let p = UnsafeMutablePointer<CGFloat>.allocate(capacity: 4)
        p[0] = red; p[1] = green; p[2] = blue; p[3] = alpha
        return UnsafePointer(p)
    }
    public var stringRepresentation: String { "\(red) \(green) \(blue) \(alpha)" }
    public var colorSpace: CGColorSpace { CGColorSpaceCreateDeviceRGB() }
    var cg: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public static let black = CIColor(red: 0, green: 0, blue: 0)
    public static let white = CIColor(red: 1, green: 1, blue: 1)
    public static let gray = CIColor(red: 0.5, green: 0.5, blue: 0.5)
    public static let red = CIColor(red: 1, green: 0, blue: 0)
    public static let green = CIColor(red: 0, green: 1, blue: 0)
    public static let blue = CIColor(red: 0, green: 0, blue: 1)
    public static let cyan = CIColor(red: 0, green: 1, blue: 1)
    public static let magenta = CIColor(red: 1, green: 0, blue: 1)
    public static let yellow = CIColor(red: 1, green: 1, blue: 0)
    public static let clear = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public struct CIFormat: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let ARGB8 = CIFormat(rawValue: 264)
    public static let BGRA8 = CIFormat(rawValue: 266)
    public static let RGBA8 = CIFormat(rawValue: 264 + 1)
    public static let RGBAh = CIFormat(rawValue: 2056)
    public static let RGBAf = CIFormat(rawValue: 2312)
    public static let L8 = CIFormat(rawValue: 1048)
    public static let A8 = CIFormat(rawValue: 265)
}

public struct CIImageOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let colorSpace = CIImageOption(rawValue: "kCIImageColorSpace")
    public static let properties = CIImageOption(rawValue: "kCIImageProperties")
    public static let applyOrientationProperty = CIImageOption(rawValue: "kCIImageApplyOrientationProperty")
    public static let nearestSampling = CIImageOption(rawValue: "kCIImageNearestSampling")
}

public final class CIImage: NSObject, @unchecked Sendable {
    enum Content { case pixels(SkImageBox), color(CIColor), empty }
    let content: Content
    /// From the pixel grid placed with its bottom-left at the origin (y up) to Core Image space.
    let transform: CGAffineTransform
    /// A crop applied after the transform, in Core Image space.
    let crop: CGRect?
    /// Set when the image came from a CGImage, returned by `cgImage`.
    public let cgImage: CGImage?
    public private(set) var properties: [String: Any] = [:]

    init(content: Content, transform: CGAffineTransform = .identity, crop: CGRect? = nil, cgImage: CGImage? = nil) {
        self.content = content
        self.transform = transform
        self.crop = crop
        self.cgImage = cgImage
        super.init()
    }

    public convenience init(cgImage: CGImage) { self.init(content: .pixels(cgImage.box), cgImage: cgImage) }
    public convenience init(cgImage: CGImage, options: [CIImageOption: Any]? = nil) { self.init(cgImage: cgImage) }
    public convenience init(color: CIColor) { self.init(content: .color(color)) }
    public convenience init?(data: Data) { self.init(data: data, options: nil) }
    public convenience init?(data: Data, options: [CIImageOption: Any]? = nil) {
        guard let box = SkImageBox.decode(data) else { return nil }
        self.init(content: .pixels(box), cgImage: CGImage(box: box))
    }
    public convenience init?(contentsOf url: URL) { self.init(contentsOf: url, options: nil) }
    public convenience init?(contentsOf url: URL, options: [CIImageOption: Any]? = nil) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, options: options)
    }
    /// From raw pixels (RGBA8 or BGRA8 rows).
    public convenience init(bitmapData data: Data, bytesPerRow: Int, size: CGSize, format: CIFormat, colorSpace: CGColorSpace?) {
        let info: CGBitmapInfo = format == .BGRA8 ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let provider = CGDataProvider(data: data as NSData),
           let image = CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                               space: colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
                               shouldInterpolate: true, intent: .defaultIntent) {
            self.init(cgImage: image)
        } else {
            self.init(content: .empty)
        }
    }
    public static func empty() -> CIImage { CIImage(content: .empty) }
    public static var black: CIImage { CIImage(color: .black) }
    public static var white: CIImage { CIImage(color: .white) }
    public static var clear: CIImage { CIImage(color: .clear) }
    public static var red: CIImage { CIImage(color: .red) }

    var pixelSize: CGSize {
        if case .pixels(let box) = content { return CGSize(width: box.width, height: box.height) }
        return .zero
    }

    /// Where the image is, in Core Image space; infinite for a solid color that is not cropped.
    public var extent: CGRect {
        var rect: CGRect
        switch content {
        case .pixels: rect = CGRect(origin: .zero, size: pixelSize).applying(transform)
        case .color: rect = .infinite
        case .empty: return .null
        }
        if let crop { rect = rect.isInfinite ? crop : rect.intersection(crop) }
        return rect
    }
    public var url: URL? { nil }
    public var colorSpace: CGColorSpace? { CGColorSpaceCreateDeviceRGB() }

    // MARK: Geometry

    public func transformed(by matrix: CGAffineTransform) -> CIImage {
        CIImage(content: content, transform: transform.concatenating(matrix), crop: crop.map { $0.applying(matrix) }, cgImage: nil)
    }
    public func transformed(by matrix: CGAffineTransform, highQualityDownsample: Bool) -> CIImage { transformed(by: matrix) }
    public func cropped(to rect: CGRect) -> CIImage {
        CIImage(content: content, transform: transform, crop: crop.map { $0.intersection(rect) } ?? rect, cgImage: nil)
    }
    public func clampedToExtent() -> CIImage { self }
    public func clamped(to rect: CGRect) -> CIImage { cropped(to: rect) }
    public func oriented(_ orientation: CGImagePropertyOrientation) -> CIImage {
        guard case .pixels = content, orientation != .up else { return self }
        let order: [CGImagePropertyOrientation: PixelOrientation] = [.upMirrored: .upMirrored, .down: .down, .downMirrored: .downMirrored,
                                                                    .leftMirrored: .leftMirrored, .right: .right, .rightMirrored: .rightMirrored, .left: .left]
        guard let image = render(extent) else { return self }
        let turned = CGImage(box: image).oriented(order[orientation] ?? .up)
        return CIImage(content: .pixels(turned.box))
    }
    public func oriented(forExifOrientation orientation: Int32) -> CIImage {
        oriented(CGImagePropertyOrientation(rawValue: UInt32(orientation)) ?? .up)
    }
    public func orientationTransform(for orientation: CGImagePropertyOrientation) -> CGAffineTransform { .identity }

    // MARK: Filters

    public func applyingFilter(_ filterName: String, parameters params: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: filterName) else { return self }
        filter.setValue(self, forKey: kCIInputImageKey)
        for (key, value) in params { filter.setValue(value, forKey: key) }
        return filter.outputImage ?? self
    }
    public func applyingFilter(_ filterName: String) -> CIImage { applyingFilter(filterName, parameters: [:]) }
    public func applyingGaussianBlur(sigma: Double) -> CIImage { applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma]) }
    public func composited(over dest: CIImage) -> CIImage {
        applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: dest])
    }
    public func settingAlphaOne(in extent: CGRect) -> CIImage { self }
    public func premultiplyingAlpha() -> CIImage { self }
    public func unpremultiplyingAlpha() -> CIImage { self }
    public func samplingNearest() -> CIImage { self }
    public func samplingLinear() -> CIImage { self }
    public func insertingIntermediate() -> CIImage { self }
    public func insertingIntermediate(cache: Bool) -> CIImage { self }
    public func matchedToWorkingSpace(from colorSpace: CGColorSpace) -> CIImage? { self }
    public func matchedFromWorkingSpace(to colorSpace: CGColorSpace) -> CIImage? { self }

    // MARK: Rendering

    /// The image's pixels inside `rect` (Core Image space), one pixel per unit; nil for an infinite rect.
    func render(_ rect: CGRect) -> SkImageBox? {
        let r = rect.integral
        guard !r.isNull, !r.isInfinite, r.width >= 1, r.height >= 1, r.width < 32768, r.height < 32768 else { return nil }
        return SkImageBox.render(width: Int(r.width), height: Int(r.height)) { canvas in
            // Core Image space to output pixels (top-left origin).
            let toOutput = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -r.minX, ty: r.maxY)
            if let crop {
                var clip = Self.skRect(crop.applying(toOutput))
                sk_canvas_clip_rect_with_operation(canvas, &clip, INTERSECT_SK_CLIPOP, false)
            }
            switch content {
            case .empty: return
            case .color(let color):
                var c = sk_color4f_t(fR: Float(color.red), fG: Float(color.green), fB: Float(color.blue), fA: Float(color.alpha))
                let paint = sk_paint_new()
                sk_paint_set_color4f(paint, &c, nil)
                sk_canvas_draw_paint(canvas, paint)
                sk_paint_delete(paint)
            case .pixels(let box):
                let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(box.height))
                let m = flip.concatenating(transform).concatenating(toOutput)
                var matrix = sk_matrix44_t(m00: Float(m.a), m01: Float(m.b), m02: 0, m03: 0, m10: Float(m.c), m11: Float(m.d), m12: 0, m13: 0,
                                           m20: 0, m21: 0, m22: 1, m23: 0, m30: Float(m.tx), m31: Float(m.ty), m32: 0, m33: 1)
                sk_canvas_concat(canvas, &matrix)
                // Whole-number scales keep pixels crisp (generated barcodes); anything else is smoothed.
                let integral = m.b == 0 && m.c == 0 && abs(m.a).rounded() == abs(m.a) && abs(m.d).rounded() == abs(m.d)
                var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                                     fFilter: integral ? NEAREST_SK_FILTER_MODE : LINEAR_SK_FILTER_MODE,
                                                     fMipmap: integral ? NONE_SK_MIPMAP_MODE : LINEAR_SK_MIPMAP_MODE)
                sk_canvas_draw_image(canvas, box.image, 0, 0, &sampling, nil)
            }
        }
    }

    static func skRect(_ r: CGRect) -> sk_rect_t { sk_rect_t(left: Float(r.minX), top: Float(r.minY), right: Float(r.maxX), bottom: Float(r.maxY)) }

    /// A filter's result: pixels covering `extent`.
    static func pixels(_ box: SkImageBox, at extent: CGRect) -> CIImage {
        CIImage(content: .pixels(box), transform: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }
}

public struct CIContextOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let workingColorSpace = CIContextOption(rawValue: "working_color_space")
    public static let outputColorSpace = CIContextOption(rawValue: "output_color_space")
    public static let useSoftwareRenderer = CIContextOption(rawValue: "software_renderer")
    public static let cacheIntermediates = CIContextOption(rawValue: "kCIContextCacheIntermediates")
    public static let priorityRequestLow = CIContextOption(rawValue: "kCIContextPriorityRequestLow")
    public static let highQualityDownsample = CIContextOption(rawValue: "kCIContextHighQualityDownsample")
    public static let workingFormat = CIContextOption(rawValue: "working_format")
}

public final class CIContext: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    public init(options: [CIContextOption: Any]? = nil) { super.init() }
    public convenience init(cgContext: CGContext, options: [CIContextOption: Any]? = nil) { self.init() }

    public func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? {
        image.render(fromRect).map { CGImage(box: $0) }
    }
    public func createCGImage(_ image: CIImage, from fromRect: CGRect, format: CIFormat, colorSpace: CGColorSpace?) -> CGImage? {
        createCGImage(image, from: fromRect)
    }
    public func createCGImage(_ image: CIImage, from fromRect: CGRect, format: CIFormat, colorSpace: CGColorSpace?, deferred: Bool) -> CGImage? {
        createCGImage(image, from: fromRect)
    }
    /// Writes 8-bit RGBA (or BGRA) rows of `bounds` into `data`.
    public func render(_ image: CIImage, toBitmap data: UnsafeMutableRawPointer, rowBytes: Int, bounds: CGRect, format: CIFormat, colorSpace: CGColorSpace?) {
        guard let box = image.render(bounds), let pixels = box.rgba(premultiplied: true) else { return }
        let w = box.width
        for y in 0..<box.height {
            for x in 0..<w {
                let s = (y * w + x) * 4, d = y * rowBytes + x * 4
                let o = data.advanced(by: d).assumingMemoryBound(to: UInt8.self)
                if format == .BGRA8 { o[0] = pixels[s + 2]; o[1] = pixels[s + 1]; o[2] = pixels[s]; o[3] = pixels[s + 3] }
                else { o[0] = pixels[s]; o[1] = pixels[s + 1]; o[2] = pixels[s + 2]; o[3] = pixels[s + 3] }
            }
        }
    }
    public func pngRepresentation(of image: CIImage, format: CIFormat, colorSpace: CGColorSpace, options: [CIImageRepresentationOption: Any] = [:]) -> Data? {
        image.render(image.extent)?.encoded(.png)
    }
    public func jpegRepresentation(of image: CIImage, colorSpace: CGColorSpace, options: [CIImageRepresentationOption: Any] = [:]) -> Data? {
        image.render(image.extent)?.encoded(.jpeg, quality: 0.9)
    }
    public func heifRepresentation(of image: CIImage, format: CIFormat, colorSpace: CGColorSpace, options: [CIImageRepresentationOption: Any] = [:]) -> Data? {
        ShimDiagnostics.warn("CIContext.heifRepresentation: HEIF cannot be encoded here; returning nil")
        return nil
    }
    public func clearCaches() {}
    public var workingColorSpace: CGColorSpace? { CGColorSpaceCreateDeviceRGB() }
}

public struct CIImageRepresentationOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Core Video pixel buffers (as Vision and AVFoundation hand them out)

package func _emptyPixelBuffer() -> CVPixelBuffer { CVBuffer(image: nil) }
public final class CVBuffer: @unchecked Sendable {
    let image: CGImage?
    init(image: CGImage?) { self.image = image }
}
public typealias CVPixelBuffer = CVBuffer
public typealias CVImageBuffer = CVBuffer
public func CVPixelBufferGetWidth(_ buffer: CVPixelBuffer) -> Int { buffer.image?.width ?? 0 }
public func CVPixelBufferGetHeight(_ buffer: CVPixelBuffer) -> Int { buffer.image?.height ?? 0 }
extension CIImage {
    public convenience init(cvPixelBuffer pixelBuffer: CVPixelBuffer) {
        if let image = pixelBuffer.image { self.init(cgImage: image) } else { self.init(content: .empty) }
    }
    public convenience init(cvPixelBuffer pixelBuffer: CVPixelBuffer, options: [CIImageOption: Any]? = nil) { self.init(cvPixelBuffer: pixelBuffer) }
    public convenience init(cvImageBuffer imageBuffer: CVImageBuffer) { self.init(cvPixelBuffer: imageBuffer) }
    public var pixelBuffer: CVPixelBuffer? { nil }
}
