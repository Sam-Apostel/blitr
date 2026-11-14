// UIKit's text system additions to Foundation: attribute keys, paragraph styles, string measuring
// and drawing (through the SwiftUI text engine), and TextKit's storage, container and layout manager.

import Foundation
import SwiftUI

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let tracking = NSAttributedString.Key("NSTracking")
    public static let ligature = NSAttributedString.Key("NSLigature")
    public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
    public static let strikethroughColor = NSAttributedString.Key("NSStrikethroughColor")
    public static let underlineStyle = NSAttributedString.Key("NSUnderline")
    public static let underlineColor = NSAttributedString.Key("NSUnderlineColor")
    public static let strokeColor = NSAttributedString.Key("NSStrokeColor")
    public static let strokeWidth = NSAttributedString.Key("NSStrokeWidth")
    public static let shadow = NSAttributedString.Key("NSShadow")
    public static let textEffect = NSAttributedString.Key("NSTextEffect")
    public static let attachment = NSAttributedString.Key("NSAttachment")
    public static let link = NSAttributedString.Key("NSLink")
    public static let baselineOffset = NSAttributedString.Key("NSBaselineOffset")
    public static let obliqueness = NSAttributedString.Key("NSObliqueness")
    public static let expansion = NSAttributedString.Key("NSExpansion")
    public static let writingDirection = NSAttributedString.Key("NSWritingDirection")
    public static let verticalGlyphForm = NSAttributedString.Key("NSVerticalGlyphForm")
}

public struct NSUnderlineStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 0x01)
    public static let thick = NSUnderlineStyle(rawValue: 0x02)
    public static let double = NSUnderlineStyle(rawValue: 0x09)
    public static let patternDot = NSUnderlineStyle(rawValue: 0x0100)
    public static let patternDash = NSUnderlineStyle(rawValue: 0x0200)
    public static let patternDashDot = NSUnderlineStyle(rawValue: 0x0300)
    public static let patternDashDotDot = NSUnderlineStyle(rawValue: 0x0400)
    public static let byWord = NSUnderlineStyle(rawValue: 0x8000)
}

open class NSParagraphStyle: NSObject, @unchecked Sendable {
    public internal(set) var alignment = NSTextAlignment.natural
    public internal(set) var lineSpacing: CGFloat = 0
    public internal(set) var paragraphSpacing: CGFloat = 0
    public internal(set) var paragraphSpacingBefore: CGFloat = 0
    public internal(set) var headIndent: CGFloat = 0
    public internal(set) var tailIndent: CGFloat = 0
    public internal(set) var firstLineHeadIndent: CGFloat = 0
    public internal(set) var minimumLineHeight: CGFloat = 0
    public internal(set) var maximumLineHeight: CGFloat = 0
    public internal(set) var lineHeightMultiple: CGFloat = 0
    public internal(set) var lineBreakMode = NSLineBreakMode.byWordWrapping
    public internal(set) var baseWritingDirection = NSWritingDirection.natural
    public internal(set) var hyphenationFactor: Float = 0
    public internal(set) var allowsDefaultTighteningForTruncation = false
    public class var `default`: NSParagraphStyle { NSParagraphStyle() }
    public override init() { super.init() }
    open override func mutableCopy() -> Any {
        let copy = NSMutableParagraphStyle()
        copy.setParagraphStyle(self)
        return copy
    }
}
open class NSMutableParagraphStyle: NSParagraphStyle {
    public override var alignment: NSTextAlignment { get { super.alignment } set { super.alignment = newValue } }
    public override var lineSpacing: CGFloat { get { super.lineSpacing } set { super.lineSpacing = newValue } }
    public override var paragraphSpacing: CGFloat { get { super.paragraphSpacing } set { super.paragraphSpacing = newValue } }
    public override var paragraphSpacingBefore: CGFloat { get { super.paragraphSpacingBefore } set { super.paragraphSpacingBefore = newValue } }
    public override var headIndent: CGFloat { get { super.headIndent } set { super.headIndent = newValue } }
    public override var tailIndent: CGFloat { get { super.tailIndent } set { super.tailIndent = newValue } }
    public override var firstLineHeadIndent: CGFloat { get { super.firstLineHeadIndent } set { super.firstLineHeadIndent = newValue } }
    public override var minimumLineHeight: CGFloat { get { super.minimumLineHeight } set { super.minimumLineHeight = newValue } }
    public override var maximumLineHeight: CGFloat { get { super.maximumLineHeight } set { super.maximumLineHeight = newValue } }
    public override var lineHeightMultiple: CGFloat { get { super.lineHeightMultiple } set { super.lineHeightMultiple = newValue } }
    public override var lineBreakMode: NSLineBreakMode { get { super.lineBreakMode } set { super.lineBreakMode = newValue } }
    public override var baseWritingDirection: NSWritingDirection { get { super.baseWritingDirection } set { super.baseWritingDirection = newValue } }
    public override var hyphenationFactor: Float { get { super.hyphenationFactor } set { super.hyphenationFactor = newValue } }
    public func setParagraphStyle(_ other: NSParagraphStyle) {
        alignment = other.alignment; lineSpacing = other.lineSpacing; paragraphSpacing = other.paragraphSpacing
        headIndent = other.headIndent; tailIndent = other.tailIndent; firstLineHeadIndent = other.firstLineHeadIndent
        lineBreakMode = other.lineBreakMode; lineHeightMultiple = other.lineHeightMultiple
    }
}

open class NSShadow: NSObject {
    open var shadowOffset = CGSize.zero
    open var shadowBlurRadius: CGFloat = 0
    open var shadowColor: Any?
    public override init() { super.init() }
}

open class NSTextAttachment: NSObject {
    open var image: UIImage?
    open var bounds = CGRect.zero
    open var contents: Data?
    open var fileType: String?
    public override init() { super.init() }
    public init(data contentData: Data?, ofType uti: String?) { contents = contentData; fileType = uti; super.init() }
    public convenience init(image: UIImage) { self.init(); self.image = image }
}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1 << 0)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 1 << 1)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 1 << 3)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 1 << 5)
}
open class NSStringDrawingContext: NSObject {
    open var minimumScaleFactor: CGFloat = 0
    open var actualScaleFactor: CGFloat { 1 }
    open var totalBounds: CGRect { .zero }
    public override init() { super.init() }
}

// MARK: - Measuring and drawing

/// The spans of an attributed string, for the SwiftUI text engine.
private func spans(of string: NSAttributedString) -> (spans: [_TextSpan], alignment: Int) {
    var result: [_TextSpan] = []
    var alignment = 0
    let ns = string.string as NSString
    string.enumerateAttributes(in: NSRange(location: 0, length: ns.length), options: []) { attributes, range, _ in
        var span = _TextSpan(text: ns.substring(with: range))
        let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: 12)
        span.fontName = font.spec.name
        span.design = font.spec.design
        span.size = font.spec.size
        span.weight = font.spec.weight
        span.italic = font.spec.italic
        span.width = font.spec.width
        if let color = attributes[.foregroundColor] as? UIColor {
            let c = UITraitCollection.current.userInterfaceStyle == .dark ? color.dynamic.dark : color.dynamic.light
            span.color = (c.r, c.g, c.b, c.a)
        }
        span.underline = ((attributes[.underlineStyle] as? Int) ?? (attributes[.underlineStyle] as? NSUnderlineStyle)?.rawValue ?? 0) != 0
        span.strikethrough = ((attributes[.strikethroughStyle] as? Int) ?? (attributes[.strikethroughStyle] as? NSUnderlineStyle)?.rawValue ?? 0) != 0
        span.kern = CGFloat(_cfNumber(attributes[.kern]) ?? 0)
        span.baselineOffset = CGFloat(_cfNumber(attributes[.baselineOffset]) ?? 0)
        if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
            alignment = style.alignment == .center ? 1 : style.alignment == .right ? 2 : 0
        }
        result.append(span)
    }
    return (result, alignment)
}

extension NSAttributedString {
    /// The size the text takes wrapped at `size.width` (and not limited by its height), as UIKit measures it.
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) -> CGRect {
        guard length > 0 else { return .zero }
        let (list, alignment) = spans(of: self)
        let width: CGFloat? = options.contains(.usesLineFragmentOrigin) && size.width < 1e6 ? size.width : nil
        guard Thread.isMainThread else { return CGRect(x: 0, y: 0, width: CGFloat(length) * 8, height: 20) }
        let measured = MainActor.assumeIsolated { _measureText(list, width: width, alignment: alignment) }
        return CGRect(origin: .zero, size: measured)
    }
    public func size() -> CGSize { boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), context: nil).size }
    /// Draws into the current graphics context (see UIGraphicsImageRenderer).
    public func draw(at point: CGPoint) {
        draw(in: CGRect(origin: point, size: CGSize(width: CGFloat.infinity, height: .infinity)))
    }
    public func draw(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), length > 0, Thread.isMainThread else { return }
        let (list, alignment) = spans(of: self)
        context.saveGState()
        MainActor.assumeIsolated { _drawText(list, in: rect, context: context, alignment: alignment) }
        context.restoreGState()
    }
    public func draw(with rect: CGRect, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) { draw(in: rect) }
}

extension NSString {
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil,
                             context: NSStringDrawingContext?) -> CGRect {
        NSAttributedString(string: self as String, attributes: attributes).boundingRect(with: size, options: options, context: context)
    }
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize {
        NSAttributedString(string: self as String, attributes: attributes).size()
    }
    public func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        NSAttributedString(string: self as String, attributes: attributes).draw(at: point)
    }
    public func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        NSAttributedString(string: self as String, attributes: attributes).draw(in: rect)
    }
    public func draw(with rect: CGRect, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext?) {
        draw(in: rect, withAttributes: attributes)
    }
}

extension String {
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize { (self as NSString).size(withAttributes: attributes) }
}

// MARK: - TextKit

/// Attributed text that edits in place: what UITextView's `textStorage` is.
open class NSTextStorage: NSMutableAttributedString, @unchecked Sendable {
    public struct EditActions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let editedAttributes = EditActions(rawValue: 1)
        public static let editedCharacters = EditActions(rawValue: 2)
    }
    open weak var delegate: AnyObject?
    open var layoutManagers: [NSLayoutManager] = []
    open var editedMask: EditActions { [] }
    open var editedRange: NSRange { NSRange(location: NSNotFound, length: 0) }
    open var changeInLength: Int { 0 }
    open func addLayoutManager(_ manager: NSLayoutManager) { layoutManagers.append(manager) }
    open func removeLayoutManager(_ manager: NSLayoutManager) { layoutManagers.removeAll { $0 === manager } }
    open func processEditing() {}
    open func edited(_ editedMask: EditActions, range editedRange: NSRange, changeInLength delta: Int) {}
}
open class NSTextContainer: NSObject {
    open var size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    open var lineFragmentPadding: CGFloat = 5
    open var maximumNumberOfLines = 0
    open var lineBreakMode = NSLineBreakMode.byWordWrapping
    open var widthTracksTextView = true
    open var heightTracksTextView = false
    open var exclusionPaths: [UIBezierPath] = []
    public init(size: CGSize) { self.size = size; super.init() }
    public convenience override init() { self.init(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)) }
}
open class NSLayoutManager: NSObject {
    open private(set) var textContainers: [NSTextContainer] = []
    open weak var textStorage: NSTextStorage?
    open var allowsNonContiguousLayout = false
    public override init() { super.init() }
    open func addTextContainer(_ container: NSTextContainer) { textContainers.append(container) }
    open func ensureLayout(for container: NSTextContainer) {}
    open func usedRect(for container: NSTextContainer) -> CGRect {
        guard let storage = textStorage else { return .zero }
        return storage.boundingRect(with: container.size, options: [.usesLineFragmentOrigin], context: nil)
    }
    open func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange: UnsafeMutablePointer<NSRange>?) -> NSRange { charRange }
    open func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> CGRect { .zero }
    open var numberOfGlyphs: Int { textStorage?.length ?? 0 }
}

// MARK: - UIBezierPath

/// A path with drawing state, bridged to CGPath (and from there to SwiftUI's `Path`).
open class UIBezierPath: NSObject {
    let cgPathStorage = CGMutablePath()
    open var cgPath: CGPath {
        get { cgPathStorage.copy() ?? CGPath(rect: .zero, transform: nil) }
        set { cgPathStorage.data = newValue.data }
    }
    open var lineWidth: CGFloat = 1
    open var lineCapStyle = CGLineCap.butt
    open var lineJoinStyle = CGLineJoin.miter
    open var miterLimit: CGFloat = 10
    open var flatness: CGFloat = 0.6
    open var usesEvenOddFillRule = false
    private var dash: [CGFloat] = []
    private var dashPhase: CGFloat = 0

    public override init() { super.init() }
    public convenience init(rect: CGRect) { self.init(); cgPathStorage.addRect(rect) }
    public convenience init(ovalIn rect: CGRect) { self.init(); cgPathStorage.addEllipse(in: rect) }
    public convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        self.init()
        cgPathStorage.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    }
    public convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()
        let r = SwiftUI.Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: corners.contains(.topLeft) ? cornerRadii.width : 0, bottomLeading: corners.contains(.bottomLeft) ? cornerRadii.width : 0,
            bottomTrailing: corners.contains(.bottomRight) ? cornerRadii.width : 0, topTrailing: corners.contains(.topRight) ? cornerRadii.width : 0),
            style: .circular)
        cgPathStorage.addPath(r.cgPath)
    }
    public convenience init(arcCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        self.init()
        // UIKit's `clockwise` is visual in its flipped space, the opposite of CoreGraphics' flag.
        cgPathStorage.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: !clockwise)
    }
    public convenience init(cgPath: CGPath) { self.init(); cgPathStorage.addPath(cgPath) }

    open var isEmpty: Bool { cgPathStorage.isEmpty }
    open var bounds: CGRect { cgPathStorage.boundingBoxOfPath }
    open var currentPoint: CGPoint { cgPathStorage.currentPoint }
    open func move(to point: CGPoint) { cgPathStorage.move(to: point) }
    open func addLine(to point: CGPoint) { cgPathStorage.addLine(to: point) }
    open func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        cgPathStorage.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
    }
    open func addQuadCurve(to endPoint: CGPoint, controlPoint: CGPoint) { cgPathStorage.addQuadCurve(to: endPoint, control: controlPoint) }
    open func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        cgPathStorage.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: !clockwise)
    }
    open func close() { cgPathStorage.closeSubpath() }
    open func removeAllPoints() { cgPathStorage.data = PathData() }
    open func append(_ bezierPath: UIBezierPath) { cgPathStorage.addPath(bezierPath.cgPathStorage) }
    open func apply(_ transform: CGAffineTransform) { cgPathStorage.data = cgPathStorage.data.applying(transform) }
    open func contains(_ point: CGPoint) -> Bool { cgPathStorage.contains(point, using: usesEvenOddFillRule ? .evenOdd : .winding) }
    open func reversing() -> UIBezierPath { UIBezierPath(cgPath: cgPathStorage) }
    open func setLineDash(_ pattern: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        dash = pattern.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
        dashPhase = phase
    }
    /// Fills in the current graphics context with its fill color.
    open func fill() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.addPath(cgPathStorage)
        context.fillPath(using: usesEvenOddFillRule ? .evenOdd : .winding)
        context.restoreGState()
    }
    open func fill(with blendMode: CGBlendMode, alpha: CGFloat) {
        UIGraphicsGetCurrentContext()?.saveGState()
        UIGraphicsGetCurrentContext()?.setBlendMode(blendMode)
        UIGraphicsGetCurrentContext()?.setAlpha(alpha)
        fill()
        UIGraphicsGetCurrentContext()?.restoreGState()
    }
    open func stroke() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(lineCapStyle)
        context.setLineJoin(lineJoinStyle)
        context.setMiterLimit(miterLimit)
        context.setLineDash(phase: dashPhase, lengths: dash)
        context.addPath(cgPathStorage)
        context.strokePath()
        context.restoreGState()
    }
    open func addClip() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.addPath(cgPathStorage)
        context.clip(using: usesEvenOddFillRule ? .evenOdd : .winding)
    }
}

