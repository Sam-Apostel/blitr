// `import VisionKit`: the live scanner is unsupported here (as on a device without the hardware), and
// its view controller, if wrapped anyway, is shown as a placeholder.
@_exported import Foundation
import UIKit
import Vision

@MainActor
open class DataScannerViewController: UIViewController {
    public enum QualityLevel: Int, Sendable { case balanced, fast, accurate }
    public enum TextContentType: Sendable, Hashable { case dateTimeDuration, emailAddress, flightNumber, fullStreetAddress, shipmentTrackingNumber, telephoneNumber, url, currency }
    public enum RecognizedDataType: Hashable, Sendable {
        case text(languages: [String] = [], textContentType: TextContentType? = nil)
        case barcode(symbologies: [VNBarcodeSymbology] = [])
    }
    public enum ScanningUnavailable: Error, Sendable { case unsupported, cameraRestricted }

    nonisolated public static var isSupported: Bool { false }
    nonisolated public static var isAvailable: Bool { false }
    nonisolated public static var supportedTextRecognitionLanguages: [String] { [] }

    public let recognizedDataTypes: Set<RecognizedDataType>
    public let qualityLevel: QualityLevel
    public let recognizesMultipleItems: Bool
    open weak var delegate: DataScannerViewControllerDelegate?
    open var isScanning: Bool { false }
    open var regionOfInterest: CGRect?
    open var zoomFactor: Double = 1
    open var overlayContainerView: UIView { view }
    public init(recognizedDataTypes: Set<RecognizedDataType>, qualityLevel: QualityLevel = .balanced, recognizesMultipleItems: Bool = false,
                isHighFrameRateTrackingEnabled: Bool = true, isPinchToZoomEnabled: Bool = true, isGuidanceEnabled: Bool = true,
                isHighlightingEnabled: Bool = false) {
        self.recognizedDataTypes = recognizedDataTypes
        self.qualityLevel = qualityLevel
        self.recognizesMultipleItems = recognizesMultipleItems
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { recognizedDataTypes = []; qualityLevel = .balanced; recognizesMultipleItems = false; super.init(coder: coder) }
    open func startScanning() throws { throw ScanningUnavailable.unsupported }
    open func stopScanning() {}
    open func capturePhoto() async throws -> UIImage { throw ScanningUnavailable.unsupported }
}

public enum RecognizedItem: Identifiable, Sendable {
    public struct Text: Sendable { public let transcript: String; public let id: UUID }
    public struct Barcode: Sendable { public let payloadStringValue: String?; public let id: UUID }
    case text(Text)
    case barcode(Barcode)
    public var id: UUID {
        switch self { case .text(let t): return t.id; case .barcode(let b): return b.id }
    }
}

public protocol DataScannerViewControllerDelegate: AnyObject {}

public final class ImageAnalyzer: @unchecked Sendable {
    public static var isSupported: Bool { false }
    public init() {}
}
