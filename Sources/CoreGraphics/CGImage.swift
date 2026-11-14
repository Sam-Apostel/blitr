internal import CSkia

// CGImage: an immutable bitmap. Whatever layout it was created with, the pixels are kept as a Skia
// image (8-bit sRGB), which is what `Image(decorative:scale:)`, `UIImage` and `CGContext.draw` draw.

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

public enum CGImageByteOrderInfo: UInt32, Sendable {
    case orderDefault = 0
    case order16Little = 0x1000
    case order32Little = 0x2000
    case order16Big = 0x3000
    case order32Big = 0x4000
    case orderMask = 0x7000
}

public struct CGBitmapInfo: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatInfoMask = CGBitmapInfo(rawValue: 0xF00)
    public static let floatComponents = CGBitmapInfo(rawValue: 0x100)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 0x1000)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 0x2000)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 0x3000)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 0x4000)
    public static var byteOrderDefault: CGBitmapInfo { [] }

    var alpha: CGImageAlphaInfo { CGImageAlphaInfo(rawValue: rawValue & 0x1F) ?? .none }
    var byteOrder: CGImageByteOrderInfo { CGImageByteOrderInfo(rawValue: rawValue & 0x7000) ?? .orderDefault }
    var isFloat: Bool { rawValue & 0x100 != 0 }
}

public typealias CGDataProviderReleaseDataCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, Int) -> Void

public final class CGDataProvider: @unchecked Sendable {
    package let bytes: Data
    public var data: CFData? { bytes as NSData }

    package init(bytes: Data) { self.bytes = bytes }
    public init?(data: CFData) { bytes = data as Data }
    public init?(url: CFURL) {
        guard let contents = try? Data(contentsOf: url as URL) else { return nil }
        bytes = contents
    }
    public init?(filename: UnsafePointer<CChar>) {
        guard let contents = FileManager.default.contents(atPath: String(cString: filename)) else { return nil }
        bytes = contents
    }
    /// The bytes are copied at once and `releaseData` is called before this returns.
    public init?(dataInfo info: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int, releaseData: CGDataProviderReleaseDataCallback) {
        bytes = Data(bytes: data, count: size)
        releaseData(info, data, size)
    }
}

/// A reference-counted Skia image.
package final class SkImageBox: @unchecked Sendable {
    package let image: OpaquePointer
    /// Takes ownership of one reference.
    package init(adopting image: OpaquePointer) { self.image = image }
    deinit { sk_image_unref(image) }

    package var width: Int { Int(sk_image_get_width(image)) }
    package var height: Int { Int(sk_image_get_height(image)) }
    package var isOpaque: Bool { sk_image_get_alpha_type(image) == OPAQUE_SK_ALPHATYPE }

    package static func decode(_ data: Data) -> SkImageBox? {
        guard !data.isEmpty else { return nil }
        let image: OpaquePointer? = data.withUnsafeBytes { buffer in
            guard let skData = sk_data_new_with_copy(buffer.baseAddress, buffer.count) else { return nil }
            defer { sk_data_unref(skData) }
            guard let lazy = sk_image_new_from_encoded(skData) else { return nil }
            // Decode now: a lazily decoded image that turns out to be corrupt would draw nothing later.
            let raster = sk_image_make_raster_image(lazy)
            sk_image_unref(lazy)
            return raster
        }
        return image.map(SkImageBox.init(adopting:))
    }

    /// From tightly packed 8-bit RGBA rows.
    package static func make(rgba: [UInt8], width: Int, height: Int, alphaRaw: UInt32) -> SkImageBox? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(width), height: Int32(height),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: sk_alphatype_t(rawValue: alphaRaw))
        defer { sk_colorspace_unref(info.colorspace) }
        let image = rgba.withUnsafeBytes { sk_image_new_raster_copy(&info, $0.baseAddress, width * 4) }
        return image.map(SkImageBox.init(adopting:))
    }

    /// The pixels as tightly packed 8-bit RGBA rows.
    package func rgba(premultiplied: Bool) -> [UInt8]? {
        let (w, h) = (width, height)
        guard w > 0, h > 0 else { return nil }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(w), height: Int32(h),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: premultiplied ? PREMUL_SK_ALPHATYPE : UNPREMUL_SK_ALPHATYPE)
        defer { sk_colorspace_unref(info.colorspace) }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { sk_image_read_pixels(image, &info, $0.baseAddress, w * 4, 0, 0, ALLOW_SK_IMAGE_CACHING_HINT) }
        return ok ? pixels : nil
    }

    /// A new image drawn into a `width` x `height` RGBA surface by `draw`.
    package static func render(width: Int, height: Int, opaque: Bool = false, _ draw: (OpaquePointer) -> Void) -> SkImageBox? {
        guard width > 0, height > 0, width <= 32767, height <= 32767 else { return nil }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(width), height: Int32(height),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: opaque ? OPAQUE_SK_ALPHATYPE : PREMUL_SK_ALPHATYPE)
        defer { sk_colorspace_unref(info.colorspace) }
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else { return nil }
        defer { sk_surface_unref(surface) }
        sk_canvas_clear(canvas, opaque ? 0xFF00_0000 : 0)
        draw(canvas)
        return sk_surface_new_image_snapshot(surface).map(SkImageBox.init(adopting:))
    }

    static func sampling(smooth: Bool, mipmaps: Bool = false) -> sk_sampling_options_t {
        sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                              fFilter: smooth ? LINEAR_SK_FILTER_MODE : NEAREST_SK_FILTER_MODE,
                              fMipmap: smooth && mipmaps ? LINEAR_SK_MIPMAP_MODE : NONE_SK_MIPMAP_MODE)
    }

    /// Resampled to a new pixel size.
    package func scaled(width: Int, height: Int, smooth: Bool = true) -> SkImageBox? {
        SkImageBox.render(width: width, height: height) { canvas in
            var dst = sk_rect_t(left: 0, top: 0, right: Float(width), bottom: Float(height))
            var sampling = SkImageBox.sampling(smooth: smooth, mipmaps: true)
            sk_canvas_draw_image_rect(canvas, image, nil, &dst, &sampling, nil)
        }
    }

    /// The image's shape (its alpha) filled with one color.
    package func tinted(r: Double, g: Double, b: Double, a: Double) -> SkImageBox? {
        SkImageBox.render(width: width, height: height) { canvas in
            var sampling = SkImageBox.sampling(smooth: false)
            sk_canvas_draw_image(canvas, image, 0, 0, &sampling, nil)
            sk_canvas_draw_color(canvas, skColor((r, g, b, a)), SRCIN_SK_BLENDMODE)
        }
    }

    package func encoded(_ format: EncodedFormat, quality: Double = 1) -> Data? {
        let (w, h) = (width, height)
        guard w > 0, h > 0 else { return nil }
        let opaqueOut = format == .jpeg
        guard var pixels = rgba(premultiplied: false) else { return nil }
        if opaqueOut {
            // JPEG has no alpha: composite on white, as UIKit does.
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] != 255 {
                let a = Int(pixels[i + 3])
                for k in 0..<3 { pixels[i + k] = UInt8((Int(pixels[i + k]) * a + 255 * (255 - a) + 127) / 255) }
                pixels[i + 3] = 255
            }
        }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(w), height: Int32(h),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: opaqueOut || isOpaque ? OPAQUE_SK_ALPHATYPE : UNPREMUL_SK_ALPHATYPE)
        defer { sk_colorspace_unref(info.colorspace) }
        return pixels.withUnsafeBytes { buffer -> Data? in
            guard let pixmap = sk_pixmap_new_with_params(&info, buffer.baseAddress, w * 4) else { return nil }
            defer { sk_pixmap_destructor(pixmap) }
            guard let stream = sk_dynamicmemorywstream_new() else { return nil }
            defer { sk_dynamicmemorywstream_destroy(stream) }
            let ok: Bool
            switch format {
            case .png:
                var options = sk_pngencoder_options_t(fFilterFlags: ALL_SK_PNGENCODER_FILTER_FLAGS, fZLibLevel: 6, fComments: nil, fGainmap: nil, fGainmapInfo: nil)
                ok = sk_pngencoder_encode(stream, pixmap, &options)
            case .jpeg:
                var options = sk_jpegencoder_options_t()
                options.fQuality = Int32(max(0, min(100, (quality * 100).rounded())))
                options.fDownsample = DOWNSAMPLE_420_SK_JPEGENCODER_DOWNSAMPLE
                options.fAlphaOption = IGNORE_SK_JPEGENCODER_ALPHA_OPTION
                ok = sk_jpegencoder_encode(stream, pixmap, &options)
            case .webp:
                var options = sk_webpencoder_options_t()
                options.fCompression = LOSSY_SK_WEBPENCODER_COMPTRESSION
                options.fQuality = Float(max(0, min(100, quality * 100)))
                ok = sk_webpencoder_encode(stream, pixmap, &options)
            }
            guard ok else { return nil }
            let count = sk_wstream_bytes_written(stream)
            var data = Data(count: count)
            data.withUnsafeMutableBytes { sk_dynamicmemorywstream_copy_to(stream, $0.baseAddress) }
            return data
        }
    }
}

package enum EncodedFormat { case png, jpeg, webp }

public final class CGImage: Hashable, @unchecked Sendable {
    package let box: SkImageBox
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bytesPerRow: Int
    public let bitmapInfo: CGBitmapInfo
    public let colorSpace: CGColorSpace?
    public let shouldInterpolate: Bool
    public let renderingIntent: CGColorRenderingIntent
    private let provider: CGDataProvider?
    /// The uniform type of the data the image was decoded from, when it was.
    package var sourceType: String?

    public var alphaInfo: CGImageAlphaInfo { bitmapInfo.alpha }
    public var byteOrderInfo: CGImageByteOrderInfo { bitmapInfo.byteOrder }
    public var isMask: Bool { false }
    public var utType: CFString? { sourceType.map { $0 as NSString } }
    public var decode: UnsafePointer<CGFloat>? { nil }

    /// The pixel data: what the image was created from, else 8-bit RGBA (premultiplied) rows.
    public var dataProvider: CGDataProvider? {
        if let provider { return provider }
        return box.rgba(premultiplied: true).map { CGDataProvider(bytes: Data($0)) }
    }

    /// Wraps decoded or rendered pixels; described as 8-bit RGBA, which is what `dataProvider` returns.
    package init(box: SkImageBox, shouldInterpolate: Bool = true) {
        self.box = box
        width = box.width
        height = box.height
        bitsPerComponent = 8
        bitsPerPixel = 32
        bytesPerRow = box.width * 4
        bitmapInfo = CGBitmapInfo(rawValue: (box.isOpaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)
        colorSpace = .srgb
        self.shouldInterpolate = shouldInterpolate
        renderingIntent = .defaultIntent
        provider = nil
    }

    public init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int, space: CGColorSpace,
                 bitmapInfo: CGBitmapInfo, provider: CGDataProvider, decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool,
                 intent: CGColorRenderingIntent) {
        guard let (pixels, alphaType) = CGImage.convert(provider.bytes, width: width, height: height, bitsPerComponent: bitsPerComponent,
                                                         bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, space: space, info: bitmapInfo),
              let box = SkImageBox.make(rgba: pixels, width: width, height: height, alphaRaw: alphaType.rawValue) else { return nil }
        self.box = box
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = bytesPerRow
        self.bitmapInfo = bitmapInfo
        colorSpace = space
        self.shouldInterpolate = shouldInterpolate
        renderingIntent = intent
        self.provider = provider
    }

    public convenience init?(jpegDataProviderSource source: CGDataProvider, decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool,
                             intent: CGColorRenderingIntent) {
        guard let box = SkImageBox.decode(source.bytes) else { return nil }
        self.init(box: box, shouldInterpolate: shouldInterpolate)
        sourceType = "public.jpeg"
    }
    public convenience init?(pngDataProviderSource source: CGDataProvider, decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool,
                             intent: CGColorRenderingIntent) {
        guard let box = SkImageBox.decode(source.bytes) else { return nil }
        self.init(box: box, shouldInterpolate: shouldInterpolate)
        sourceType = "public.png"
    }

    public func copy() -> CGImage? { self }
    public func copy(colorSpace space: CGColorSpace) -> CGImage? { self }

    /// The part of the image inside `rect` (pixel coordinates, origin top-left), clipped to the image.
    public func cropping(to rect: CGRect) -> CGImage? {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        let (w, h) = (Int(r.width), Int(r.height))
        let cropped = SkImageBox.render(width: w, height: h, opaque: box.isOpaque) { canvas in
            var sampling = SkImageBox.sampling(smooth: false)
            sk_canvas_draw_image(canvas, box.image, Float(-r.minX), Float(-r.minY), &sampling, nil)
        }
        return cropped.map { CGImage(box: $0, shouldInterpolate: shouldInterpolate) }
    }

    public static func == (a: CGImage, b: CGImage) -> Bool { a === b }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    // MARK: Pixel layouts

    /// Converts a bitmap in any layout CoreGraphics accepts for 8/16-bit integer and 32-bit float
    /// gray, RGB or CMYK data to tight 8-bit RGBA rows, with the Skia alpha type that describes them.
    static func convert(_ data: Data, width: Int, height: Int, bitsPerComponent bpc: Int, bitsPerPixel bpp: Int, bytesPerRow: Int,
                        space: CGColorSpace, info: CGBitmapInfo) -> ([UInt8], sk_alphatype_t)? {
        guard width > 0, height > 0, bpc == 8 || bpc == 16 || bpc == 32, bpp % bpc == 0 else { return nil }
        let bytesPerPixel = bpp / 8, bytesPerComponent = bpc / 8
        let count = bytesPerPixel / bytesPerComponent
        let rowBytes = max(bytesPerRow, width * bytesPerPixel)
        guard data.count >= rowBytes * (height - 1) + width * bytesPerPixel else { return nil }
        let alpha = info.alpha
        let colorCount = alpha == .alphaOnly ? 0 : space.numberOfComponents
        let hasAlphaSlot = alpha != .none
        guard count == colorCount + (hasAlphaSlot ? 1 : 0) else { return nil }
        let alphaFirst = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
        let ignoresAlpha = alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst
        let order = info.byteOrder
        // 8-bit pixels read as one little-endian 32-bit word arrive with their bytes reversed.
        let reversePixel = bpc == 8 && bytesPerPixel == 4 && order == .order32Little
        let littleComponents = order == .order16Little || (bpc == 32 && order == .order32Little) || (info.isFloat && order == .orderDefault)

        var out = [UInt8](repeating: 255, count: width * height * 4)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let source = raw.bindMemory(to: UInt8.self)
            func component(_ offset: Int) -> UInt8 {
                switch bpc {
                case 8: return source[offset]
                case 16: return littleComponents ? source[offset + 1] : source[offset]
                default:
                    var bits: UInt32 = 0
                    for k in 0..<4 { bits |= UInt32(source[offset + k]) << UInt32(littleComponents ? 8 * k : 8 * (3 - k)) }
                    let v = info.isFloat ? Float(bitPattern: bits) : Float(bits) / Float(UInt32.max)
                    return UInt8(max(0, min(255, (v * 255).rounded())))
                }
            }
            var channels = [UInt8](repeating: 0, count: count)
            for y in 0..<height {
                for x in 0..<width {
                    let p = y * rowBytes + x * bytesPerPixel
                    for c in 0..<count {
                        let index = reversePixel ? count - 1 - c : c
                        channels[c] = component(p + index * bytesPerComponent)
                    }
                    let colorStart = hasAlphaSlot && alphaFirst ? 1 : 0
                    let o = (y * width + x) * 4
                    switch colorCount {
                    case 0:
                        out[o] = 0; out[o + 1] = 0; out[o + 2] = 0
                    case 1:
                        out[o] = channels[colorStart]; out[o + 1] = channels[colorStart]; out[o + 2] = channels[colorStart]
                    case 4:
                        let k = 255 - Int(channels[colorStart + 3])
                        for i in 0..<3 { out[o + i] = UInt8((255 - Int(channels[colorStart + i])) * k / 255) }
                    default:
                        out[o] = channels[colorStart]; out[o + 1] = channels[colorStart + 1]; out[o + 2] = channels[colorStart + 2]
                    }
                    if hasAlphaSlot && !ignoresAlpha { out[o + 3] = alphaFirst ? channels[0] : channels[count - 1] }
                }
            }
        }
        let premultiplied = alpha == .premultipliedLast || alpha == .premultipliedFirst || alpha == .alphaOnly
        return (out, ignoresAlpha ? OPAQUE_SK_ALPHATYPE : premultiplied ? PREMUL_SK_ALPHATYPE : UNPREMUL_SK_ALPHATYPE)
    }
}

/// The uniform type identifier of encoded image data, from its first bytes.
package func _encodedFormatName(_ data: Data) -> String? {
    let b = [UInt8](data.prefix(16))
    guard b.count >= 12 else { return nil }
    if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "public.png" }
    if b[0] == 0xFF, b[1] == 0xD8 { return "public.jpeg" }
    if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "com.compuserve.gif" }
    if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "org.webmproject.webp" }
    if b[0] == 0x42, b[1] == 0x4D { return "com.microsoft.bmp" }
    if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) || (b[0] == 0x4D && b[1] == 0x4D && b[3] == 0x2A) { return "public.tiff" }
    if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {
        return String(decoding: b[8..<12], as: UTF8.self).hasPrefix("avi") ? "public.avif" : "public.heic"
    }
    if b[0] == 0x25, b[1] == 0x50, b[2] == 0x44, b[3] == 0x46 { return "com.adobe.pdf" }
    return nil
}

/// EXIF orientations, in the order of `Image.Orientation`'s and `UIImage.Orientation`'s cases.
package enum PixelOrientation: Int, Sendable { case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored }

extension CGImage {
    /// The pixels turned the way `orientation` says they should be shown.
    package func oriented(_ orientation: PixelOrientation) -> CGImage {
        let (w, h) = (CGFloat(width), CGFloat(height))
        let t: CGAffineTransform
        var swaps = false
        switch orientation {
        case .up: return self
        case .upMirrored: t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .down: t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .downMirrored: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case .right: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0); swaps = true
        case .left: t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w); swaps = true
        case .leftMirrored: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0); swaps = true
        case .rightMirrored: t = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w); swaps = true
        }
        let turned = SkImageBox.render(width: swaps ? height : width, height: swaps ? width : height, opaque: box.isOpaque) { canvas in
            var m = sk_matrix44_t(m00: Float(t.a), m01: Float(t.b), m02: 0, m03: 0, m10: Float(t.c), m11: Float(t.d), m12: 0, m13: 0,
                                  m20: 0, m21: 0, m22: 1, m23: 0, m30: Float(t.tx), m31: Float(t.ty), m32: 0, m33: 1)
            sk_canvas_set_matrix(canvas, &m)
            var sampling = SkImageBox.sampling(smooth: false)
            sk_canvas_draw_image(canvas, box.image, 0, 0, &sampling, nil)
        }
        return turned.map { CGImage(box: $0, shouldInterpolate: shouldInterpolate) } ?? self
    }
}
