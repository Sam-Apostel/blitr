// CIFilter: parameters by key (`setValue(_:forKey:)`, as with CIFilter(name:)) and the typed filters of
// CoreImage.CIFilterBuiltins, which set the same keys. Implemented: QR Code and Code 128 generators,
// constant color, Gaussian/box/disc blur, color controls, sepia, invert, monochrome, photo effects,
// exposure, hue, false color, color matrix, affine/Lanczos scale/crop, source-over compositing and
// area average. Aztec and PDF417 give no image (with a warning); other filter names pass their input
// image through, with a warning.
internal import CSkia

public let kCIInputImageKey = "inputImage"
public let kCIOutputImageKey = "outputImage"
public let kCIInputBackgroundImageKey = "inputBackgroundImage"
public let kCIInputRadiusKey = "inputRadius"
public let kCIInputIntensityKey = "inputIntensity"
public let kCIInputColorKey = "inputColor"
public let kCIInputSaturationKey = "inputSaturation"
public let kCIInputBrightnessKey = "inputBrightness"
public let kCIInputContrastKey = "inputContrast"
public let kCIInputEVKey = "inputEV"
public let kCIInputAngleKey = "inputAngle"
public let kCIInputScaleKey = "inputScale"
public let kCIInputAspectRatioKey = "inputAspectRatio"
public let kCIInputTransformKey = "inputTransform"
public let kCIInputExtentKey = "inputExtent"
public let kCIInputCenterKey = "inputCenter"
public let kCIInputWidthKey = "inputWidth"
public let kCIInputSharpnessKey = "inputSharpness"
public let kCIInputMaskImageKey = "inputMaskImage"
public let kCIAttributeFilterName = "CIAttributeFilterName"
public let kCIAttributeFilterDisplayName = "CIAttributeFilterDisplayName"
public let kCICategoryBuiltIn = "CICategoryBuiltIn"

public protocol CIFilterProtocol: AnyObject {
    var outputImage: CIImage? { get }
}

open class CIFilter: NSObject, CIFilterProtocol, @unchecked Sendable {
    public let name: String
    var values: [String: Any] = [:]
    open var isEnabled = true

    init(filterName: String) {
        name = filterName
        super.init()
        setDefaults()
    }

    /// A filter by Core Image name; unknown names give a filter that passes its input image through.
    public convenience init?(name: String) {
        self.init(filterName: name)
    }
    public convenience init?(name: String, parameters params: [String: Any]?) {
        self.init(filterName: name)
        for (key, value) in params ?? [:] { setValue(value, forKey: key) }
    }

    open func setValue(_ value: Any?, forKey key: String) { values[key] = value }
    open func value(forKey key: String) -> Any? { key == kCIOutputImageKey ? outputImage : values[key] }
    open func setDefaults() {
        switch name {
        case "CIQRCodeGenerator": values["inputCorrectionLevel"] = "M"
        case "CICode128BarcodeGenerator": values["inputQuietSpace"] = 7.0; values["inputBarcodeHeight"] = 32.0
        case "CIGaussianBlur": values[kCIInputRadiusKey] = 10.0
        case "CIBoxBlur", "CIDiscBlur": values[kCIInputRadiusKey] = 10.0
        case "CIColorControls": values[kCIInputSaturationKey] = 1.0; values[kCIInputBrightnessKey] = 0.0; values[kCIInputContrastKey] = 1.0
        case "CISepiaTone", "CIColorMonochrome": values[kCIInputIntensityKey] = 1.0
        case "CILanczosScaleTransform": values[kCIInputScaleKey] = 1.0; values[kCIInputAspectRatioKey] = 1.0
        default: break
        }
    }
    open var inputKeys: [String] { values.keys.filter { $0.hasPrefix("input") }.sorted() }
    open var outputKeys: [String] { [kCIOutputImageKey] }
    open var attributes: [String: Any] { [kCIAttributeFilterName: name, kCIAttributeFilterDisplayName: name] }
    public class func filterNames(inCategory category: String?) -> [String] { CIFilter.implemented.sorted() }
    public class func filterNames(inCategories categories: [String]?) -> [String] { CIFilter.implemented.sorted() }
    public class func localizedName(forFilterName filterName: String) -> String? { filterName }

    static let implemented: Set<String> = [
        "CIQRCodeGenerator", "CICode128BarcodeGenerator", "CIAztecCodeGenerator", "CIPDF417BarcodeGenerator", "CIConstantColorGenerator",
        "CIGaussianBlur", "CIBoxBlur", "CIDiscBlur", "CIColorControls", "CISepiaTone", "CIColorInvert", "CIColorMonochrome",
        "CIPhotoEffectMono", "CIPhotoEffectNoir", "CIPhotoEffectTonal", "CIPhotoEffectChrome", "CIPhotoEffectFade", "CIPhotoEffectInstant",
        "CIPhotoEffectProcess", "CIPhotoEffectTransfer", "CIExposureAdjust", "CIHueAdjust", "CIFalseColor", "CIColorMatrix",
        "CIAffineTransform", "CILanczosScaleTransform", "CICrop", "CISourceOverCompositing", "CIAreaAverage",
    ]

    // MARK: Parameter access

    func image(_ key: String = kCIInputImageKey) -> CIImage? { values[key] as? CIImage }
    func number(_ key: String, _ fallback: Double = 0) -> Double { _cfNumber(values[key]) ?? fallback }
    func color(_ key: String, _ fallback: CIColor) -> CIColor {
        if let c = values[key] as? CIColor { return c }
        if let c = values[key] as? CGColor { return CIColor(cgColor: c) }
        return fallback
    }
    func data(_ key: String) -> Data? {
        if let d = values[key] as? Data { return d }
        if let d = values[key] as? NSData { return d as Data }
        return nil
    }
    func rect(_ key: String) -> CGRect? {
        if let r = values[key] as? CGRect { return r }
        if let v = values[key] as? CIVector { return v.cgRectValue }
        return nil
    }

    // MARK: Output

    open var outputImage: CIImage? {
        let input = image()
        switch name {
        case "CIQRCodeGenerator":
            guard let message = data("inputMessage"), !message.isEmpty else { return nil }
            let level = (values["inputCorrectionLevel"] as? String) ?? "M"
            guard let matrix = QRCode.encode([UInt8](message), ecc: QRCode.ECC(letter: level)) else {
                ShimDiagnostics.warn("CIQRCodeGenerator: the message is too long for a QR code")
                return nil
            }
            return CIFilter.barcodeImage(rows: matrix, quiet: 1)
        case "CICode128BarcodeGenerator":
            guard let message = data("inputMessage"), !message.isEmpty, message.allSatisfy({ $0 < 128 }) else { return nil }
            let quiet = max(0, Int(number("inputQuietSpace", 7).rounded()))
            let height = max(1, Int(number("inputBarcodeHeight", 32).rounded()))
            let row = Code128.modules([UInt8](message))
            return CIFilter.barcodeImage(rows: Array(repeating: row, count: height), quiet: 0, horizontalQuiet: quiet)
        case "CIAztecCodeGenerator", "CIPDF417BarcodeGenerator":
            ShimDiagnostics.warn("\(name) is not implemented: it produces no image (QR Code and Code 128 are drawn)")
            return nil
        case "CIConstantColorGenerator":
            return CIImage(color: color(kCIInputColorKey, .black))
        case "CIGaussianBlur", "CIDiscBlur":
            let radius = number(kCIInputRadiusKey, 10)
            return CIFilter.filtered(input, grow: CGFloat(radius * 3)) { sk_imagefilter_new_blur(Float(radius), Float(radius), DECAL_SK_SHADER_TILEMODE, nil, nil) }
        case "CIBoxBlur":
            let sigma = number(kCIInputRadiusKey, 10) / 2
            return CIFilter.filtered(input, grow: CGFloat(sigma * 3)) { sk_imagefilter_new_blur(Float(sigma), Float(sigma), DECAL_SK_SHADER_TILEMODE, nil, nil) }
        case "CIColorControls":
            let s = Float(number(kCIInputSaturationKey, 1)), b = Float(number(kCIInputBrightnessKey, 0)), c = Float(number(kCIInputContrastKey, 1))
            var m = ColorMatrix.saturation(s)
            m = ColorMatrix.concat(ColorMatrix.brightness(b), m)
            m = ColorMatrix.concat(ColorMatrix.contrast(c), m)
            return CIFilter.colorFiltered(input, m)
        case "CISepiaTone":
            return CIFilter.colorFiltered(input, ColorMatrix.mix(ColorMatrix.sepia, Float(number(kCIInputIntensityKey, 1))))
        case "CIColorInvert":
            return CIFilter.colorFiltered(input, ColorMatrix.invert)
        case "CIColorMonochrome":
            let c = color(kCIInputColorKey, CIColor(red: 0.6, green: 0.45, blue: 0.3))
            return CIFilter.colorFiltered(input, ColorMatrix.mix(ColorMatrix.tinted(Float(c.red), Float(c.green), Float(c.blue)), Float(number(kCIInputIntensityKey, 1))))
        case "CIPhotoEffectMono", "CIPhotoEffectTonal":
            return CIFilter.colorFiltered(input, ColorMatrix.saturation(0))
        case "CIPhotoEffectNoir":
            return CIFilter.colorFiltered(input, ColorMatrix.concat(ColorMatrix.contrast(1.3), ColorMatrix.saturation(0)))
        case "CIPhotoEffectChrome", "CIPhotoEffectProcess":
            return CIFilter.colorFiltered(input, ColorMatrix.concat(ColorMatrix.contrast(1.1), ColorMatrix.saturation(1.2)))
        case "CIPhotoEffectFade", "CIPhotoEffectInstant", "CIPhotoEffectTransfer":
            return CIFilter.colorFiltered(input, ColorMatrix.concat(ColorMatrix.brightness(0.05), ColorMatrix.saturation(0.75)))
        case "CIExposureAdjust":
            return CIFilter.colorFiltered(input, ColorMatrix.scale(Float(pow(2, number(kCIInputEVKey, 0) / 2.2))))
        case "CIHueAdjust":
            return CIFilter.colorFiltered(input, ColorMatrix.hue(Float(number(kCIInputAngleKey, 0))))
        case "CIFalseColor":
            let a = color("inputColor0", CIColor(red: 0.3, green: 0, blue: 0)), b = color("inputColor1", CIColor(red: 1, green: 0.9, blue: 0.8))
            return CIFilter.colorFiltered(input, ColorMatrix.falseColor(a, b))
        case "CIColorMatrix":
            func vector(_ key: String, _ fallback: [CGFloat]) -> [Float] { ((values[key] as? CIVector)?.values ?? fallback).map { Float($0) } }
            let r = vector("inputRVector", [1, 0, 0, 0]), g = vector("inputGVector", [0, 1, 0, 0]), b = vector("inputBVector", [0, 0, 1, 0])
            let a = vector("inputAVector", [0, 0, 0, 1]), bias = vector("inputBiasVector", [0, 0, 0, 0])
            return CIFilter.colorFiltered(input, r + [bias[0]] + g + [bias[1]] + b + [bias[2]] + a + [bias[3]])
        case "CIAffineTransform":
            let t = (values[kCIInputTransformKey] as? CGAffineTransform) ?? (values[kCIInputTransformKey] as? NSValue).map { _ in CGAffineTransform.identity } ?? .identity
            return input?.transformed(by: t)
        case "CILanczosScaleTransform":
            let scale = CGFloat(number(kCIInputScaleKey, 1)), aspect = CGFloat(number(kCIInputAspectRatioKey, 1))
            return input?.transformed(by: CGAffineTransform(scaleX: scale * aspect, y: scale))
        case "CICrop":
            guard let r = rect("inputRectangle") else { return input }
            return input?.cropped(to: r)
        case "CISourceOverCompositing":
            guard let input, let background = image(kCIInputBackgroundImageKey) else { return input }
            var extent = input.extent.union(background.extent)
            if extent.isInfinite { extent = input.extent.isInfinite ? background.extent : input.extent }
            guard let top = input.render(extent), let bottom = background.render(extent) else { return input }
            let combined = SkImageBox.render(width: top.width, height: top.height) { canvas in
                var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                                     fFilter: NEAREST_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
                sk_canvas_draw_image(canvas, bottom.image, 0, 0, &sampling, nil)
                sk_canvas_draw_image(canvas, top.image, 0, 0, &sampling, nil)
            }
            return combined.map { CIImage.pixels($0, at: extent.integral) }
        case "CIAreaAverage":
            guard let input else { return nil }
            let region = rect(kCIInputExtentKey) ?? input.extent
            guard let box = input.render(region), let pixels = box.rgba(premultiplied: true), !pixels.isEmpty else { return nil }
            var sum = [Int](repeating: 0, count: 4)
            for i in stride(from: 0, to: pixels.count, by: 4) { for k in 0..<4 { sum[k] += Int(pixels[i + k]) } }
            let n = pixels.count / 4
            let average = (0..<4).map { UInt8((sum[$0] + n / 2) / n) }
            return SkImageBox.make(rgba: average, width: 1, height: 1, alphaRaw: PREMUL_SK_ALPHATYPE.rawValue)
                .map { CIImage.pixels($0, at: CGRect(x: region.minX, y: region.minY, width: 1, height: 1)) }
        default:
            ShimDiagnostics.warn("Core Image filter \(name) is not implemented; its input image is passed through")
            return input
        }
    }

    // MARK: Helpers

    /// A black-on-white image of the modules, one pixel each, with quiet zones.
    static func barcodeImage(rows: [[Bool]], quiet: Int, horizontalQuiet: Int? = nil) -> CIImage? {
        guard let first = rows.first else { return nil }
        let hq = horizontalQuiet ?? quiet
        let w = first.count + 2 * hq, h = rows.count + 2 * quiet
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, dark) in row.enumerated() where dark {
                let o = ((y + quiet) * w + x + hq) * 4
                pixels[o] = 0; pixels[o + 1] = 0; pixels[o + 2] = 0
            }
        }
        return SkImageBox.make(rgba: pixels, width: w, height: h, alphaRaw: OPAQUE_SK_ALPHATYPE.rawValue)
            .map { CIImage.pixels($0, at: CGRect(x: 0, y: 0, width: w, height: h)) }
    }

    /// The input rasterized over its extent (grown by `grow`) and drawn through an image filter.
    static func filtered(_ input: CIImage?, grow: CGFloat, _ make: () -> OpaquePointer?) -> CIImage? {
        guard let input, !input.extent.isInfinite, !input.extent.isNull else { return input }
        let extent = input.extent.integral.insetBy(dx: -ceil(grow), dy: -ceil(grow))
        guard let source = input.render(input.extent.integral) else { return input }
        let pad = Float(ceil(grow))
        let result = SkImageBox.render(width: Int(extent.width), height: Int(extent.height)) { canvas in
            let paint = sk_paint_new()
            let filter = make()
            sk_paint_set_imagefilter(paint, filter)
            sk_imagefilter_unref(filter)
            var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                                 fFilter: NEAREST_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
            sk_canvas_draw_image(canvas, source.image, pad, pad, &sampling, paint)
            sk_paint_delete(paint)
        }
        return result.map { CIImage.pixels($0, at: extent) }
    }

    static func colorFiltered(_ input: CIImage?, _ matrix: [Float]) -> CIImage? {
        guard let input else { return nil }
        // A solid color stays one: apply the matrix to it directly.
        if case .color(let c) = input.content {
            let v = [Float(c.red), Float(c.green), Float(c.blue), Float(c.alpha)]
            func row(_ r: Int) -> CGFloat { CGFloat(max(0, min(1, (0..<4).reduce(Float(0)) { $0 + matrix[r * 5 + $1] * v[$1] } + matrix[r * 5 + 4]))) }
            return CIImage(content: .color(CIColor(red: row(0), green: row(1), blue: row(2), alpha: row(3))), crop: input.crop)
        }
        return filtered(input, grow: 0) {
            let cf = sk_colorfilter_new_color_matrix(matrix)
            let f = sk_imagefilter_new_color_filter(cf, nil, nil)
            sk_colorfilter_unref(cf)
            return f
        }
    }
}

/// 4x5 color matrices (row-major, RGBA, translation in 0...1).
enum ColorMatrix {
    static let identity: [Float] = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
    static let invert: [Float] = [-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0]
    static let sepia: [Float] = [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0]
    static func saturation(_ s: Float) -> [Float] {
        let (lr, lg, lb): (Float, Float, Float) = (0.2126, 0.7152, 0.0722)
        return [lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0,
                lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0,
                lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0,
                0, 0, 0, 1, 0]
    }
    static func brightness(_ b: Float) -> [Float] { [1, 0, 0, 0, b, 0, 1, 0, 0, b, 0, 0, 1, 0, b, 0, 0, 0, 1, 0] }
    static func contrast(_ c: Float) -> [Float] {
        let t = 0.5 * (1 - c)
        return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0]
    }
    static func scale(_ k: Float) -> [Float] { [k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, 1, 0] }
    static func tinted(_ r: Float, _ g: Float, _ b: Float) -> [Float] {
        let (lr, lg, lb): (Float, Float, Float) = (0.2126, 0.7152, 0.0722)
        return [lr * r, lg * r, lb * r, 0, 0, lr * g, lg * g, lb * g, 0, 0, lr * b, lg * b, lb * b, 0, 0, 0, 0, 0, 1, 0]
    }
    static func falseColor(_ a: CIColor, _ b: CIColor) -> [Float] {
        let (lr, lg, lb): (Float, Float, Float) = (0.2126, 0.7152, 0.0722)
        func row(_ from: CGFloat, _ to: CGFloat) -> [Float] {
            let d = Float(to - from)
            return [lr * d, lg * d, lb * d, 0, Float(from)]
        }
        return row(a.red, b.red) + row(a.green, b.green) + row(a.blue, b.blue) + [0, 0, 0, 1, 0]
    }
    static func hue(_ angle: Float) -> [Float] {
        let c = cos(angle), s = sin(angle)
        let (lr, lg, lb): (Float, Float, Float) = (0.213, 0.715, 0.072)
        return [lr + c * (1 - lr) + s * -lr, lg + c * -lg + s * -lg, lb + c * -lb + s * (1 - lb), 0, 0,
                lr + c * -lr + s * 0.143, lg + c * (1 - lg) + s * 0.140, lb + c * -lb + s * -0.283, 0, 0,
                lr + c * -lr + s * -(1 - lr), lg + c * -lg + s * lg, lb + c * (1 - lb) + s * lb, 0, 0,
                0, 0, 0, 1, 0]
    }
    static func mix(_ m: [Float], _ amount: Float) -> [Float] { zip(m, identity).map { $0 * amount + $1 * (1 - amount) } }
    /// `a` after `b`.
    static func concat(_ a: [Float], _ b: [Float]) -> [Float] {
        var r = [Float](repeating: 0, count: 20)
        for i in 0..<4 {
            for j in 0..<4 { r[i * 5 + j] = (0..<4).reduce(Float(0)) { $0 + a[i * 5 + $1] * b[$1 * 5 + j] } }
            r[i * 5 + 4] = (0..<4).reduce(Float(0)) { $0 + a[i * 5 + $1] * b[$1 * 5 + 4] } + a[i * 5 + 4]
        }
        return r
    }
}

public final class CIVector: NSObject, @unchecked Sendable {
    public let values: [CGFloat]
    public init(values: UnsafePointer<CGFloat>, count: Int) { self.values = Array(UnsafeBufferPointer(start: values, count: count)); super.init() }
    public init(x: CGFloat) { values = [x]; super.init() }
    public init(x: CGFloat, y: CGFloat) { values = [x, y]; super.init() }
    public init(x: CGFloat, y: CGFloat, z: CGFloat) { values = [x, y, z]; super.init() }
    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) { values = [x, y, z, w]; super.init() }
    public convenience init(cgPoint p: CGPoint) { self.init(x: p.x, y: p.y) }
    public convenience init(cgRect r: CGRect) { self.init(x: r.minX, y: r.minY, z: r.width, w: r.height) }
    public convenience init(cgAffineTransform t: CGAffineTransform) {
        let list = [t.a, t.b, t.c, t.d, t.tx, t.ty]
        self.init(values: list, count: 6)
    }
    public var count: Int { values.count }
    public func value(at index: Int) -> CGFloat { index < values.count ? values[index] : 0 }
    public var x: CGFloat { value(at: 0) }
    public var y: CGFloat { value(at: 1) }
    public var z: CGFloat { value(at: 2) }
    public var w: CGFloat { value(at: 3) }
    public var cgPointValue: CGPoint { CGPoint(x: x, y: y) }
    public var cgRectValue: CGRect { CGRect(x: x, y: y, width: z, height: w) }
    public var cgAffineTransformValue: CGAffineTransform { CGAffineTransform(a: x, b: y, c: z, d: w, tx: value(at: 4), ty: value(at: 5)) }
}
