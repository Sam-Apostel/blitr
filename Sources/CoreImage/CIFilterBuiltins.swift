// CoreImage.CIFilterBuiltins: typed filters (`CIFilter.qrCodeGenerator()` and the rest). Each sets the same
// keys as `CIFilter(name:)` with `setValue(_:forKey:)`; the work is done by CIFilter.outputImage.
// (`import CoreImage.CIFilterBuiltins` is rewritten to `import CoreImage` by the preprocessor.)


public protocol CIQRCodeGenerator: CIFilterProtocol {
    var message: Data { get set }
    var correctionLevel: String { get set }
}

public protocol CICode128BarcodeGenerator: CIFilterProtocol {
    var message: Data { get set }
    var quietSpace: Float { get set }
    var barcodeHeight: Float { get set }
}

public protocol CIAztecCodeGenerator: CIFilterProtocol {
    var message: Data { get set }
    var correctionLevel: Float { get set }
    var layers: Float { get set }
    var compactStyle: Float { get set }
}

public protocol CIPDF417BarcodeGenerator: CIFilterProtocol {
    var message: Data { get set }
    var minWidth: Float { get set }
    var maxWidth: Float { get set }
    var minHeight: Float { get set }
    var maxHeight: Float { get set }
    var dataColumns: Float { get set }
    var rows: Float { get set }
    var preferredAspectRatio: Float { get set }
    var compactionMode: Float { get set }
    var compactStyle: Float { get set }
    var correctionLevel: Float { get set }
    var alwaysSpecifyCompaction: Float { get set }
}

public protocol CIConstantColorGenerator: CIFilterProtocol {
    var color: CIColor { get set }
}

public protocol CIGaussianBlur: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var radius: Float { get set }
}

public protocol CIBoxBlur: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var radius: Float { get set }
}

public protocol CIDiscBlur: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var radius: Float { get set }
}

public protocol CIColorControls: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var saturation: Float { get set }
    var brightness: Float { get set }
    var contrast: Float { get set }
}

public protocol CISepiaTone: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var intensity: Float { get set }
}

public protocol CIColorInvert: CIFilterProtocol {
    var inputImage: CIImage? { get set }
}

public protocol CIColorMonochrome: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var color: CIColor { get set }
    var intensity: Float { get set }
}

public protocol CIPhotoEffect: CIFilterProtocol {
    var inputImage: CIImage? { get set }
}

public protocol CIExposureAdjust: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var ev: Float { get set }
}

public protocol CIHueAdjust: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var angle: Float { get set }
}

public protocol CIFalseColor: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var color0: CIColor { get set }
    var color1: CIColor { get set }
}

public protocol CIAffineTransform: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var transform: CGAffineTransform { get set }
}

public protocol CILanczosScaleTransform: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var scale: Float { get set }
    var aspectRatio: Float { get set }
}

public protocol CICompositeOperation: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var backgroundImage: CIImage? { get set }
}

public protocol CIAreaAverage: CIFilterProtocol {
    var inputImage: CIImage? { get set }
    var extent: CGRect { get set }
}

final class _CIQRCodeGeneratorFilter: CIFilter, CIQRCodeGenerator, @unchecked Sendable {
    public var message: Data {
        get { values["inputMessage"] as? Data ?? Data() }
        set { values["inputMessage"] = newValue }
    }
    public var correctionLevel: String {
        get { values["inputCorrectionLevel"] as? String ?? "M" }
        set { values["inputCorrectionLevel"] = newValue }
    }
}

final class _CICode128BarcodeGeneratorFilter: CIFilter, CICode128BarcodeGenerator, @unchecked Sendable {
    public var message: Data {
        get { values["inputMessage"] as? Data ?? Data() }
        set { values["inputMessage"] = newValue }
    }
    public var quietSpace: Float {
        get { Float(number("inputQuietSpace")) }
        set { values["inputQuietSpace"] = Double(newValue) }
    }
    public var barcodeHeight: Float {
        get { Float(number("inputBarcodeHeight")) }
        set { values["inputBarcodeHeight"] = Double(newValue) }
    }
}

final class _CIAztecCodeGeneratorFilter: CIFilter, CIAztecCodeGenerator, @unchecked Sendable {
    public var message: Data {
        get { values["inputMessage"] as? Data ?? Data() }
        set { values["inputMessage"] = newValue }
    }
    public var correctionLevel: Float {
        get { Float(number("inputCorrectionLevel")) }
        set { values["inputCorrectionLevel"] = Double(newValue) }
    }
    public var layers: Float {
        get { Float(number("inputLayers")) }
        set { values["inputLayers"] = Double(newValue) }
    }
    public var compactStyle: Float {
        get { Float(number("inputCompactStyle")) }
        set { values["inputCompactStyle"] = Double(newValue) }
    }
}

final class _CIPDF417BarcodeGeneratorFilter: CIFilter, CIPDF417BarcodeGenerator, @unchecked Sendable {
    public var message: Data {
        get { values["inputMessage"] as? Data ?? Data() }
        set { values["inputMessage"] = newValue }
    }
    public var minWidth: Float {
        get { Float(number("inputMinWidth")) }
        set { values["inputMinWidth"] = Double(newValue) }
    }
    public var maxWidth: Float {
        get { Float(number("inputMaxWidth")) }
        set { values["inputMaxWidth"] = Double(newValue) }
    }
    public var minHeight: Float {
        get { Float(number("inputMinHeight")) }
        set { values["inputMinHeight"] = Double(newValue) }
    }
    public var maxHeight: Float {
        get { Float(number("inputMaxHeight")) }
        set { values["inputMaxHeight"] = Double(newValue) }
    }
    public var dataColumns: Float {
        get { Float(number("inputDataColumns")) }
        set { values["inputDataColumns"] = Double(newValue) }
    }
    public var rows: Float {
        get { Float(number("inputRows")) }
        set { values["inputRows"] = Double(newValue) }
    }
    public var preferredAspectRatio: Float {
        get { Float(number("inputPreferredAspectRatio")) }
        set { values["inputPreferredAspectRatio"] = Double(newValue) }
    }
    public var compactionMode: Float {
        get { Float(number("inputCompactionMode")) }
        set { values["inputCompactionMode"] = Double(newValue) }
    }
    public var compactStyle: Float {
        get { Float(number("inputCompactStyle")) }
        set { values["inputCompactStyle"] = Double(newValue) }
    }
    public var correctionLevel: Float {
        get { Float(number("inputCorrectionLevel")) }
        set { values["inputCorrectionLevel"] = Double(newValue) }
    }
    public var alwaysSpecifyCompaction: Float {
        get { Float(number("inputAlwaysSpecifyCompaction")) }
        set { values["inputAlwaysSpecifyCompaction"] = Double(newValue) }
    }
}

final class _CIConstantColorGeneratorFilter: CIFilter, CIConstantColorGenerator, @unchecked Sendable {
    public var color: CIColor {
        get { color("inputColor", .black) }
        set { values["inputColor"] = newValue }
    }
}

final class _CIGaussianBlurFilter: CIFilter, CIGaussianBlur, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var radius: Float {
        get { Float(number("inputRadius")) }
        set { values["inputRadius"] = Double(newValue) }
    }
}

final class _CIBoxBlurFilter: CIFilter, CIBoxBlur, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var radius: Float {
        get { Float(number("inputRadius")) }
        set { values["inputRadius"] = Double(newValue) }
    }
}

final class _CIDiscBlurFilter: CIFilter, CIDiscBlur, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var radius: Float {
        get { Float(number("inputRadius")) }
        set { values["inputRadius"] = Double(newValue) }
    }
}

final class _CIColorControlsFilter: CIFilter, CIColorControls, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var saturation: Float {
        get { Float(number("inputSaturation")) }
        set { values["inputSaturation"] = Double(newValue) }
    }
    public var brightness: Float {
        get { Float(number("inputBrightness")) }
        set { values["inputBrightness"] = Double(newValue) }
    }
    public var contrast: Float {
        get { Float(number("inputContrast")) }
        set { values["inputContrast"] = Double(newValue) }
    }
}

final class _CISepiaToneFilter: CIFilter, CISepiaTone, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var intensity: Float {
        get { Float(number("inputIntensity")) }
        set { values["inputIntensity"] = Double(newValue) }
    }
}

final class _CIColorInvertFilter: CIFilter, CIColorInvert, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIColorMonochromeFilter: CIFilter, CIColorMonochrome, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var color: CIColor {
        get { color("inputColor", .black) }
        set { values["inputColor"] = newValue }
    }
    public var intensity: Float {
        get { Float(number("inputIntensity")) }
        set { values["inputIntensity"] = Double(newValue) }
    }
}

final class _CIPhotoEffectMonoFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectNoirFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectTonalFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectChromeFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectFadeFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectInstantFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectProcessFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIPhotoEffectTransferFilter: CIFilter, CIPhotoEffect, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
}

final class _CIExposureAdjustFilter: CIFilter, CIExposureAdjust, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var ev: Float {
        get { Float(number("inputEV")) }
        set { values["inputEV"] = Double(newValue) }
    }
}

final class _CIHueAdjustFilter: CIFilter, CIHueAdjust, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var angle: Float {
        get { Float(number("inputAngle")) }
        set { values["inputAngle"] = Double(newValue) }
    }
}

final class _CIFalseColorFilter: CIFilter, CIFalseColor, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var color0: CIColor {
        get { color("inputColor0", .black) }
        set { values["inputColor0"] = newValue }
    }
    public var color1: CIColor {
        get { color("inputColor1", .black) }
        set { values["inputColor1"] = newValue }
    }
}

final class _CIAffineTransformFilter: CIFilter, CIAffineTransform, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var transform: CGAffineTransform {
        get { values["inputTransform"] as? CGAffineTransform ?? .identity }
        set { values["inputTransform"] = newValue }
    }
}

final class _CILanczosScaleTransformFilter: CIFilter, CILanczosScaleTransform, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var scale: Float {
        get { Float(number("inputScale")) }
        set { values["inputScale"] = Double(newValue) }
    }
    public var aspectRatio: Float {
        get { Float(number("inputAspectRatio")) }
        set { values["inputAspectRatio"] = Double(newValue) }
    }
}

final class _CISourceOverCompositingFilter: CIFilter, CICompositeOperation, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var backgroundImage: CIImage? {
        get { image("inputBackgroundImage") }
        set { values["inputBackgroundImage"] = newValue }
    }
}

final class _CIAreaAverageFilter: CIFilter, CIAreaAverage, @unchecked Sendable {
    public var inputImage: CIImage? {
        get { image("inputImage") }
        set { values["inputImage"] = newValue }
    }
    public var extent: CGRect {
        get { rect("inputExtent") ?? .zero }
        set { values["inputExtent"] = newValue }
    }
}

extension CIFilter {
    public class func qrCodeGenerator() -> CIFilter & CIQRCodeGenerator { _CIQRCodeGeneratorFilter(filterName: "CIQRCodeGenerator") }
    public class func code128BarcodeGenerator() -> CIFilter & CICode128BarcodeGenerator { _CICode128BarcodeGeneratorFilter(filterName: "CICode128BarcodeGenerator") }
    public class func aztecCodeGenerator() -> CIFilter & CIAztecCodeGenerator { _CIAztecCodeGeneratorFilter(filterName: "CIAztecCodeGenerator") }
    public class func pdf417BarcodeGenerator() -> CIFilter & CIPDF417BarcodeGenerator { _CIPDF417BarcodeGeneratorFilter(filterName: "CIPDF417BarcodeGenerator") }
    public class func constantColorGenerator() -> CIFilter & CIConstantColorGenerator { _CIConstantColorGeneratorFilter(filterName: "CIConstantColorGenerator") }
    public class func gaussianBlur() -> CIFilter & CIGaussianBlur { _CIGaussianBlurFilter(filterName: "CIGaussianBlur") }
    public class func boxBlur() -> CIFilter & CIBoxBlur { _CIBoxBlurFilter(filterName: "CIBoxBlur") }
    public class func discBlur() -> CIFilter & CIDiscBlur { _CIDiscBlurFilter(filterName: "CIDiscBlur") }
    public class func colorControls() -> CIFilter & CIColorControls { _CIColorControlsFilter(filterName: "CIColorControls") }
    public class func sepiaTone() -> CIFilter & CISepiaTone { _CISepiaToneFilter(filterName: "CISepiaTone") }
    public class func colorInvert() -> CIFilter & CIColorInvert { _CIColorInvertFilter(filterName: "CIColorInvert") }
    public class func colorMonochrome() -> CIFilter & CIColorMonochrome { _CIColorMonochromeFilter(filterName: "CIColorMonochrome") }
    public class func photoEffectMono() -> CIFilter & CIPhotoEffect { _CIPhotoEffectMonoFilter(filterName: "CIPhotoEffectMono") }
    public class func photoEffectNoir() -> CIFilter & CIPhotoEffect { _CIPhotoEffectNoirFilter(filterName: "CIPhotoEffectNoir") }
    public class func photoEffectTonal() -> CIFilter & CIPhotoEffect { _CIPhotoEffectTonalFilter(filterName: "CIPhotoEffectTonal") }
    public class func photoEffectChrome() -> CIFilter & CIPhotoEffect { _CIPhotoEffectChromeFilter(filterName: "CIPhotoEffectChrome") }
    public class func photoEffectFade() -> CIFilter & CIPhotoEffect { _CIPhotoEffectFadeFilter(filterName: "CIPhotoEffectFade") }
    public class func photoEffectInstant() -> CIFilter & CIPhotoEffect { _CIPhotoEffectInstantFilter(filterName: "CIPhotoEffectInstant") }
    public class func photoEffectProcess() -> CIFilter & CIPhotoEffect { _CIPhotoEffectProcessFilter(filterName: "CIPhotoEffectProcess") }
    public class func photoEffectTransfer() -> CIFilter & CIPhotoEffect { _CIPhotoEffectTransferFilter(filterName: "CIPhotoEffectTransfer") }
    public class func exposureAdjust() -> CIFilter & CIExposureAdjust { _CIExposureAdjustFilter(filterName: "CIExposureAdjust") }
    public class func hueAdjust() -> CIFilter & CIHueAdjust { _CIHueAdjustFilter(filterName: "CIHueAdjust") }
    public class func falseColor() -> CIFilter & CIFalseColor { _CIFalseColorFilter(filterName: "CIFalseColor") }
    public class func affineTransform() -> CIFilter & CIAffineTransform { _CIAffineTransformFilter(filterName: "CIAffineTransform") }
    public class func lanczosScaleTransform() -> CIFilter & CILanczosScaleTransform { _CILanczosScaleTransformFilter(filterName: "CILanczosScaleTransform") }
    public class func sourceOverCompositing() -> CIFilter & CICompositeOperation { _CISourceOverCompositingFilter(filterName: "CISourceOverCompositing") }
    public class func areaAverage() -> CIFilter & CIAreaAverage { _CIAreaAverageFilter(filterName: "CIAreaAverage") }
}
