// UIKit's drawing entry points: the current-context stack, UIGraphicsImageRenderer and the older
// UIGraphicsBeginImageContext family, all on top of the Skia-backed CGContext.

import Foundation
import SwiftUI

private let contextStackKey = "SwiftUI.UIGraphics.contextStack"

private final class ContextStack {
    var contexts: [CGContext] = []
    /// Contexts opened by UIGraphicsBeginImageContext, with their scale.
    var imageContexts: [(context: CGContext, scale: CGFloat)] = []
}

private var currentStack: ContextStack {
    let dictionary = Thread.current.threadDictionary
    if let stack = dictionary[contextStackKey] as? ContextStack { return stack }
    let stack = ContextStack()
    dictionary[contextStackKey] = stack
    return stack
}

public func UIGraphicsGetCurrentContext() -> CGContext? { currentStack.contexts.last }
public func UIGraphicsPushContext(_ context: CGContext) { currentStack.contexts.append(context) }
public func UIGraphicsPopContext() { _ = currentStack.contexts.popLast() }

public func UIGraphicsBeginImageContext(_ size: CGSize) { UIGraphicsBeginImageContextWithOptions(size, false, 1) }
/// A `scale` of 0 means the screen's.
public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    let s = scale == 0 ? (_currentConfiguration().scale ?? _currentConfiguration().device.scale) : scale
    guard let context = CGContext.uikit(size: size, scale: s, opaque: opaque) else { return }
    currentStack.imageContexts.append((context, s))
    UIGraphicsPushContext(context)
}
public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
    guard let top = currentStack.imageContexts.last, let image = top.context.makeImage() else { return nil }
    return UIImage(cgImage: image, scale: top.scale, orientation: .up)
}
public func UIGraphicsEndImageContext() {
    guard currentStack.imageContexts.popLast() != nil else { return }
    UIGraphicsPopContext()
}

public func UIRectFill(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.fill(rect) }
public func UIRectFillUsingBlendMode(_ rect: CGRect, _ blendMode: CGBlendMode) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.setBlendMode(blendMode)
    context.fill(rect)
    context.restoreGState()
}
public func UIRectFrame(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1) }
public func UIRectClip(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.clip(to: rect) }

extension UIColor {
    /// Sets the fill color of the current graphics context.
    public func setFill() { UIGraphicsGetCurrentContext()?.setFillColor(cgColor) }
    public func setStroke() { UIGraphicsGetCurrentContext()?.setStrokeColor(cgColor) }
    public func set() { setFill(); setStroke() }
}

// MARK: - Renderers

open class UIGraphicsRendererFormat: NSObject {
    public var bounds: CGRect = .zero
    public required override init() { super.init() }
    public class func `default`() -> Self { self.init() }
    public class func preferred() -> Self { self.init() }
}

open class UIGraphicsImageRendererFormat: UIGraphicsRendererFormat {
    public enum Range: Int, Sendable { case unspecified = -1, automatic, extended, standard }
    /// Pixels per point; the rendered device's unless set.
    public var scale: CGFloat = _currentConfiguration().scale ?? _currentConfiguration().device.scale
    public var opaque = false
    public var preferredRange = Range.automatic
    public var prefersExtendedRange = false
    public var supportsHighDynamicRange: Bool { false }
    public required init() { super.init() }
    public convenience init(for traitCollection: UITraitCollection) {
        self.init()
        if traitCollection.displayScale > 0 { scale = traitCollection.displayScale }
    }
}

open class UIGraphicsRendererContext: NSObject {
    public let cgContext: CGContext
    public let format: UIGraphicsRendererFormat
    init(cgContext: CGContext, format: UIGraphicsRendererFormat) {
        self.cgContext = cgContext
        self.format = format
        super.init()
    }
    public func fill(_ rect: CGRect) { cgContext.fill(rect) }
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) {
        cgContext.saveGState()
        cgContext.setBlendMode(blendMode)
        cgContext.fill(rect)
        cgContext.restoreGState()
    }
    public func stroke(_ rect: CGRect) { cgContext.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1) }
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) {
        cgContext.saveGState()
        cgContext.setBlendMode(blendMode)
        stroke(rect)
        cgContext.restoreGState()
    }
    public func clip(to rect: CGRect) { cgContext.clip(to: rect) }
}

open class UIGraphicsImageRendererContext: UIGraphicsRendererContext {
    let scale: CGFloat
    init(cgContext: CGContext, format: UIGraphicsImageRendererFormat) {
        scale = format.scale
        super.init(cgContext: cgContext, format: format)
    }
    public var currentImage: UIImage {
        cgContext.makeImage().map { UIImage(cgImage: $0, scale: scale, orientation: .up) } ?? UIImage()
    }
}

open class UIGraphicsRenderer: NSObject {
    let bounds: CGRect
    public var allowsImageOutput: Bool { true }
    public init(bounds: CGRect) { self.bounds = bounds; super.init() }
}

open class UIGraphicsImageRenderer: UIGraphicsRenderer {
    public typealias DrawingActions = (UIGraphicsImageRendererContext) -> Void
    public let format: UIGraphicsImageRendererFormat

    public convenience init(size: CGSize) { self.init(bounds: CGRect(origin: .zero, size: size), format: UIGraphicsImageRendererFormat()) }
    public convenience init(size: CGSize, format: UIGraphicsImageRendererFormat) { self.init(bounds: CGRect(origin: .zero, size: size), format: format) }
    public convenience override init(bounds: CGRect) { self.init(bounds: bounds, format: UIGraphicsImageRendererFormat()) }
    public init(bounds: CGRect, format: UIGraphicsImageRendererFormat) {
        self.format = format
        format.bounds = bounds
        super.init(bounds: bounds)
    }

    /// Runs `actions` with a fresh bitmap context current and returns what was drawn.
    public func image(actions: DrawingActions) -> UIImage {
        guard let context = CGContext.uikit(size: bounds.size, scale: format.scale, opaque: format.opaque) else {
            ShimDiagnostics.warn("UIGraphicsImageRenderer: cannot make a \(Int(bounds.width)) x \(Int(bounds.height)) pt bitmap; the image is empty")
            return UIImage()
        }
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        // Opaque renderers start black, as on iOS; drawing colors default to black.
        let rendererContext = UIGraphicsImageRendererContext(cgContext: context, format: format)
        UIGraphicsPushContext(context)
        actions(rendererContext)
        UIGraphicsPopContext()
        return rendererContext.currentImage
    }
    public func pngData(actions: DrawingActions) -> Data { image(actions: actions).pngData() ?? Data() }
    public func jpegData(withCompressionQuality compressionQuality: CGFloat, actions: DrawingActions) -> Data {
        image(actions: actions).jpegData(compressionQuality: compressionQuality) ?? Data()
    }
}

// MARK: - PDF renderer

open class UIGraphicsPDFRendererFormat: UIGraphicsRendererFormat {
    public var documentInfo: [String: Any] = [:]
    public required init() { super.init() }
}
open class UIGraphicsPDFRendererContext: UIGraphicsRendererContext {
    var pages: [CGRect] = []
    let defaultBounds: CGRect
    var pageContext: CGContext
    init(bounds: CGRect, format: UIGraphicsPDFRendererFormat) {
        defaultBounds = bounds
        pageContext = CGContext.uikit(size: bounds.size, scale: 1, opaque: false)!
        super.init(cgContext: pageContext, format: format)
    }
    public var pdfContextBounds: CGRect { pages.last ?? defaultBounds }
    /// Pages are recorded with their size; what is drawn on them is not kept (the PDF's pages are blank).
    public func beginPage() { pages.append(defaultBounds) }
    public func beginPage(withBounds bounds: CGRect, pageInfo: [String: Any]) { pages.append(bounds) }
    public func setURL(_ url: URL, for rect: CGRect) {}
    public func addDestination(withName name: String, at point: CGPoint) {}
}
open class UIGraphicsPDFRenderer: UIGraphicsRenderer {
    public typealias DrawingActions = (UIGraphicsPDFRendererContext) -> Void
    public let format: UIGraphicsPDFRendererFormat
    public init(bounds: CGRect, format: UIGraphicsPDFRendererFormat) { self.format = format; super.init(bounds: bounds) }
    public convenience override init(bounds: CGRect) { self.init(bounds: bounds, format: UIGraphicsPDFRendererFormat()) }

    /// A PDF with one blank page per `beginPage` (drawing is performed, so its side effects happen, but not recorded).
    public func pdfData(actions: DrawingActions) -> Data {
        ShimDiagnostics.warn("UIGraphicsPDFRenderer: PDF pages are written blank; their drawing is not recorded")
        let context = UIGraphicsPDFRendererContext(bounds: bounds, format: format)
        UIGraphicsPushContext(context.cgContext)
        actions(context)
        UIGraphicsPopContext()
        return UIGraphicsPDFRenderer.blankPDF(pages: context.pages.isEmpty ? [bounds] : context.pages)
    }
    public func writePDF(to url: URL, withActions actions: DrawingActions) throws { try pdfData(actions: actions).write(to: url) }

    static func blankPDF(pages: [CGRect]) -> Data {
        var objects: [String] = ["<< /Type /Catalog /Pages 2 0 R >>", ""]
        var kids: [String] = []
        for (i, page) in pages.enumerated() {
            let number = 3 + i
            kids.append("\(number) 0 R")
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(Int(page.width)) \(Int(page.height))] >>")
        }
        objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(pages.count) >>"
        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}
