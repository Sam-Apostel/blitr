// `import Vision`: requests run and complete with no results (no observations are produced here),
// so code that falls back when nothing is found takes that path. Mask generation throws.
@_exported import Foundation
@_exported import CoreImage

public struct VNErrorCode: Error, Sendable { public let rawValue: Int }
public enum VNImageOption: String, Sendable { case properties = "VNImageOptionProperties", ciContext = "VNImageOptionCIContext" }
public enum VNRequestTrackingLevel: Int, Sendable { case accurate, fast }
public enum VNRequestTextRecognitionLevel: Int, Sendable { case accurate, fast }
public typealias VNRequestCompletionHandler = (VNRequest, Error?) -> Void

public struct VNBarcodeSymbology: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let aztec = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyAztec")
    public static let code39 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyCode39")
    public static let code93 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyCode93")
    public static let code128 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyCode128")
    public static let dataMatrix = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyDataMatrix")
    public static let ean8 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyEAN8")
    public static let ean13 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyEAN13")
    public static let i2of5 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyI2of5")
    public static let itf14 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyITF14")
    public static let pdf417 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyPDF417")
    public static let qr = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyQR")
    public static let upce = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyUPCE")
    public static let codabar = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyCodabar")
    public static let gs1DataBar = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyGS1DataBar")
    public static let microPDF417 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyMicroPDF417")
    public static let microQR = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyMicroQR")
    public static let msiPlessey = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyMSIPlessey")
}

open class VNObservation: NSObject, @unchecked Sendable {
    open var uuid = UUID()
    open var confidence: Float = 0
}
open class VNDetectedObjectObservation: VNObservation, @unchecked Sendable {
    open var boundingBox = CGRect.zero
}
open class VNRectangleObservation: VNDetectedObjectObservation, @unchecked Sendable {
    open var topLeft = CGPoint.zero, topRight = CGPoint.zero, bottomLeft = CGPoint.zero, bottomRight = CGPoint.zero
}
open class VNBarcodeObservation: VNRectangleObservation, @unchecked Sendable {
    open var symbology = VNBarcodeSymbology.qr
    open var payloadStringValue: String?
    open var payloadData: Data?
    open var barcodeDescriptor: AnyObject?
}
open class VNRecognizedText: NSObject, @unchecked Sendable {
    open var string = ""
    open var confidence: Float = 0
}
open class VNRecognizedTextObservation: VNRectangleObservation, @unchecked Sendable {
    open func topCandidates(_ maxCandidateCount: Int) -> [VNRecognizedText] { [] }
}
open class VNClassificationObservation: VNObservation, @unchecked Sendable { open var identifier = "" }
open class VNFaceObservation: VNDetectedObjectObservation, @unchecked Sendable {}
open class VNPixelBufferObservation: VNObservation, @unchecked Sendable {
    open var pixelBuffer: CVPixelBuffer { _emptyPixelBuffer() }
}
open class VNSaliencyImageObservation: VNPixelBufferObservation, @unchecked Sendable {
    open var salientObjects: [VNRectangleObservation]? { nil }
}
open class VNInstanceMaskObservation: VNObservation, @unchecked Sendable {
    open var allInstances: IndexSet { IndexSet() }
    open var instanceMask: CVPixelBuffer { _emptyPixelBuffer() }
    open func generateMask(forInstances instances: IndexSet) throws -> CVPixelBuffer { throw VNErrorCode(rawValue: 9) }
    open func generateMaskedImage(ofInstances instances: IndexSet, from requestHandler: VNImageRequestHandler, croppedToInstancesExtent: Bool) throws -> CVPixelBuffer {
        throw VNErrorCode(rawValue: 9)
    }
    open func generateScaledMaskForImage(forInstances instances: IndexSet, from requestHandler: VNImageRequestHandler) throws -> CVPixelBuffer {
        throw VNErrorCode(rawValue: 9)
    }
}

open class VNRequest: NSObject, @unchecked Sendable {
    public let completionHandler: VNRequestCompletionHandler?
    open var revision = 1
    open var usesCPUOnly = false
    open var preferBackgroundProcessing = false
    open var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    public init(completionHandler: VNRequestCompletionHandler? = nil) { self.completionHandler = completionHandler; super.init() }
    public convenience override init() { self.init(completionHandler: nil) }
    open func cancel() {}
    func finish() { completionHandler?(self, nil) }
}
open class VNImageBasedRequest: VNRequest, @unchecked Sendable {}

open class VNDetectBarcodesRequest: VNImageBasedRequest, @unchecked Sendable {
    open var symbologies: [VNBarcodeSymbology] = []
    open var results: [VNBarcodeObservation]? = nil
    open func supportedSymbologies() throws -> [VNBarcodeSymbology] { [.qr, .aztec, .pdf417, .code128, .dataMatrix, .ean13, .ean8] }
    open class var supportedSymbologies: [VNBarcodeSymbology] { [.qr, .aztec, .pdf417, .code128, .dataMatrix, .ean13, .ean8] }
    override func finish() { results = []; super.finish() }
}
open class VNRecognizeTextRequest: VNImageBasedRequest, @unchecked Sendable {
    open var recognitionLevel = VNRequestTextRecognitionLevel.accurate
    open var recognitionLanguages: [String] = ["en-US"]
    open var usesLanguageCorrection = true
    open var automaticallyDetectsLanguage = false
    open var customWords: [String] = []
    open var minimumTextHeight: Float = 0
    open var results: [VNRecognizedTextObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNGenerateAttentionBasedSaliencyImageRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNSaliencyImageObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNGenerateObjectnessBasedSaliencyImageRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNSaliencyImageObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNGenerateForegroundInstanceMaskRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNInstanceMaskObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNClassifyImageRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNClassificationObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNDetectFaceRectanglesRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNFaceObservation]? = nil
    override func finish() { results = []; super.finish() }
}
open class VNDetectRectanglesRequest: VNImageBasedRequest, @unchecked Sendable {
    open var results: [VNRectangleObservation]? = nil
    override func finish() { results = []; super.finish() }
}

open class VNImageRequestHandler: NSObject, @unchecked Sendable {
    public init(cgImage image: CGImage, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(cgImage image: CGImage, orientation: CGImagePropertyOrientation, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(ciImage image: CIImage, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(ciImage image: CIImage, orientation: CGImagePropertyOrientation, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(cvPixelBuffer pixelBuffer: CVPixelBuffer, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(data imageData: Data, options: [VNImageOption: Any] = [:]) { super.init() }
    public init(url imageURL: URL, options: [VNImageOption: Any] = [:]) { super.init() }
    /// Every request completes, with no observations.
    open func perform(_ requests: [VNRequest]) throws { requests.forEach { $0.finish() } }
}
open class VNSequenceRequestHandler: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open func perform(_ requests: [VNRequest], on image: CGImage) throws { requests.forEach { $0.finish() } }
    open func perform(_ requests: [VNRequest], on image: CIImage) throws { requests.forEach { $0.finish() } }
}
public func VNImageRectForNormalizedRect(_ normalizedRect: CGRect, _ imageWidth: Int, _ imageHeight: Int) -> CGRect {
    CGRect(x: normalizedRect.minX * CGFloat(imageWidth), y: normalizedRect.minY * CGFloat(imageHeight),
           width: normalizedRect.width * CGFloat(imageWidth), height: normalizedRect.height * CGFloat(imageHeight))
}
