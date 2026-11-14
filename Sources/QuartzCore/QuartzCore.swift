@_exported import CoreGraphics
@_exported import ObjectiveC
// QuartzCore: layer and animation classes as stores of their properties (UIKit views drawn by the
// representable host read corner radius, border and background from their layer), a monotonic
// clock, and a display link that never fires: one frame is rendered, not a run of them.

public func CACurrentMediaTime() -> CFTimeInterval { ProcessInfo.processInfo.systemUptime }

public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0, m14: CGFloat = 0
    public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0, m24: CGFloat = 0
    public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1, m34: CGFloat = 0
    public var m41: CGFloat = 0, m42: CGFloat = 0, m43: CGFloat = 0, m44: CGFloat = 1
    public init() {}
}
public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m41 = tx; t.m42 = ty; t.m43 = tz; return t
}
public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m11 = sx; t.m22 = sy; t.m33 = sz; return t
}
public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    let length = (x * x + y * y + z * z).squareRoot()
    guard length > 0 else { return CATransform3D() }
    let (x, y, z) = (x / length, y / length, z / length)
    let c = CGFloat(cos(Double(angle))), s = CGFloat(sin(Double(angle))), k = 1 - c
    var t = CATransform3D()
    t.m11 = c + x * x * k; t.m12 = y * x * k + z * s; t.m13 = z * x * k - y * s
    t.m21 = x * y * k - z * s; t.m22 = c + y * y * k; t.m23 = z * y * k + x * s
    t.m31 = x * z * k + y * s; t.m32 = y * z * k - x * s; t.m33 = c + z * z * k
    return t
}
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D {
    let l = [[a.m11, a.m12, a.m13, a.m14], [a.m21, a.m22, a.m23, a.m24], [a.m31, a.m32, a.m33, a.m34], [a.m41, a.m42, a.m43, a.m44]]
    let r = [[b.m11, b.m12, b.m13, b.m14], [b.m21, b.m22, b.m23, b.m24], [b.m31, b.m32, b.m33, b.m34], [b.m41, b.m42, b.m43, b.m44]]
    var m = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: 4), count: 4)
    for i in 0..<4 { for j in 0..<4 { for k in 0..<4 { m[i][j] += l[i][k] * r[k][j] } } }
    var t = CATransform3D()
    t.m11 = m[0][0]; t.m12 = m[0][1]; t.m13 = m[0][2]; t.m14 = m[0][3]
    t.m21 = m[1][0]; t.m22 = m[1][1]; t.m23 = m[1][2]; t.m24 = m[1][3]
    t.m31 = m[2][0]; t.m32 = m[2][1]; t.m33 = m[2][2]; t.m34 = m[2][3]
    t.m41 = m[3][0]; t.m42 = m[3][1]; t.m43 = m[3][2]; t.m44 = m[3][3]
    return t
}
public func CATransform3DTranslate(_ t: CATransform3D, _ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t)
}
public func CATransform3DScale(_ t: CATransform3D, _ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t)
}
public func CATransform3DRotate(_ t: CATransform3D, _ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t)
}
public func CATransform3DMakeAffineTransform(_ m: CGAffineTransform) -> CATransform3D {
    var t = CATransform3D(); t.m11 = m.a; t.m12 = m.b; t.m21 = m.c; t.m22 = m.d; t.m41 = m.tx; t.m42 = m.ty; return t
}
public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t == CATransform3D() }

public struct CACornerMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let layerMinXMinYCorner = CACornerMask(rawValue: 1)
    public static let layerMaxXMinYCorner = CACornerMask(rawValue: 2)
    public static let layerMinXMaxYCorner = CACornerMask(rawValue: 4)
    public static let layerMaxXMaxYCorner = CACornerMask(rawValue: 8)
    static let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
}
public struct CALayerCornerCurve: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}
public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
}
public struct CAMediaTimingFunctionName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
}
public final class CAMediaTimingFunction: NSObject {
    public init(name: CAMediaTimingFunctionName) { super.init() }
    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) { super.init() }
}
public struct CAMediaTimingFillMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let forwards = CAMediaTimingFillMode(rawValue: "forwards")
    public static let backwards = CAMediaTimingFillMode(rawValue: "backwards")
    public static let both = CAMediaTimingFillMode(rawValue: "both")
    public static let removed = CAMediaTimingFillMode(rawValue: "removed")
}
public struct CAShapeLayerLineCap: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = CAShapeLayerLineCap(rawValue: "butt")
    public static let round = CAShapeLayerLineCap(rawValue: "round")
    public static let square = CAShapeLayerLineCap(rawValue: "square")
}
public struct CAShapeLayerLineJoin: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = CAShapeLayerLineJoin(rawValue: "miter")
    public static let round = CAShapeLayerLineJoin(rawValue: "round")
    public static let bevel = CAShapeLayerLineJoin(rawValue: "bevel")
}
public struct CAShapeLayerFillRule: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = CAShapeLayerFillRule(rawValue: "non-zero")
    public static let evenOdd = CAShapeLayerFillRule(rawValue: "even-odd")
}
public struct CAGradientLayerType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let axial = CAGradientLayerType(rawValue: "axial")
    public static let radial = CAGradientLayerType(rawValue: "radial")
    public static let conic = CAGradientLayerType(rawValue: "conic")
}

open class CAAnimation: NSObject {
    public var duration: CFTimeInterval = 0
    public var beginTime: CFTimeInterval = 0
    public var repeatCount: Float = 0
    public var autoreverses = false
    public var isRemovedOnCompletion = true
    public var fillMode = CAMediaTimingFillMode.removed
    public var timingFunction: CAMediaTimingFunction?
    public var speed: Float = 1
    public weak var delegate: AnyObject?
    public override init() { super.init() }
}
open class CAPropertyAnimation: CAAnimation {
    public var keyPath: String?
    public var isAdditive = false
    public var isCumulative = false
    public convenience init(keyPath: String?) { self.init(); self.keyPath = keyPath }
}
open class CABasicAnimation: CAPropertyAnimation {
    public var fromValue: Any?
    public var toValue: Any?
    public var byValue: Any?
}
open class CAKeyframeAnimation: CAPropertyAnimation {
    public var values: [Any]?
    public var keyTimes: [NSNumber]?
    public var path: CGPath?
}
open class CASpringAnimation: CABasicAnimation {
    public var mass: CGFloat = 1
    public var stiffness: CGFloat = 100
    public var damping: CGFloat = 10
    public var initialVelocity: CGFloat = 0
    public var settlingDuration: CFTimeInterval { 0 }
}
open class CAAnimationGroup: CAAnimation { public var animations: [CAAnimation]? }
open class CATransition: CAAnimation {
    public var type = "fade"
    public var subtype: String?
}

/// Changes apply at once: there is no animation to group.
public enum CATransaction {
    public static func begin() {}
    public static func commit() {}
    public static func flush() {}
    public static func setDisableActions(_ flag: Bool) {}
    public static func disableActions() -> Bool { true }
    public static func setAnimationDuration(_ duration: CFTimeInterval) {}
    public static func animationDuration() -> CFTimeInterval { 0 }
    public static func setAnimationTimingFunction(_ function: CAMediaTimingFunction?) {}
    public static func setCompletionBlock(_ block: (() -> Void)?) { block?() }
}

open class CALayer: NSObject {
    public var frame: CGRect = .zero
    public var bounds: CGRect { get { CGRect(origin: .zero, size: frame.size) } set { frame.size = newValue.size } }
    public var position: CGPoint { get { CGPoint(x: frame.midX, y: frame.midY) } set { frame.origin = CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2) } }
    public var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    public var zPosition: CGFloat = 0
    public var transform = CATransform3D()
    public var backgroundColor: CGColor?
    public var cornerRadius: CGFloat = 0
    public var cornerCurve = CALayerCornerCurve.circular
    public var maskedCorners = CACornerMask.all
    public var borderWidth: CGFloat = 0
    public var borderColor: CGColor?
    public var masksToBounds = false
    public var opacity: Float = 1
    public var isHidden = false
    public var shadowOpacity: Float = 0
    public var shadowRadius: CGFloat = 3
    public var shadowOffset = CGSize(width: 0, height: -3)
    public var shadowColor: CGColor? = .black
    public var shadowPath: CGPath?
    public var contents: Any?
    public var contentsGravity = CALayerContentsGravity.resize
    public var contentsScale: CGFloat = 1
    public var rasterizationScale: CGFloat = 1
    public var shouldRasterize = false
    public var allowsEdgeAntialiasing = false
    public var isDoubleSided = true
    public var isGeometryFlipped = false
    public var name: String?
    public var mask: CALayer?
    public var compositingFilter: Any?
    public var filters: [Any]?
    public weak var delegate: AnyObject?
    public private(set) var sublayers: [CALayer]?
    public private(set) weak var superlayer: CALayer?
    var animations: [String: CAAnimation] = [:]

    public required override init() { super.init() }
    public init(layer: Any) { super.init() }

    open func addSublayer(_ layer: CALayer) {
        layer.removeFromSuperlayer()
        layer.superlayer = self
        sublayers = (sublayers ?? []) + [layer]
    }
    open func insertSublayer(_ layer: CALayer, at index: UInt32) {
        layer.removeFromSuperlayer()
        layer.superlayer = self
        var list = sublayers ?? []
        list.insert(layer, at: min(Int(index), list.count))
        sublayers = list
    }
    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        insertSublayer(layer, at: UInt32(sublayers?.firstIndex { $0 === sibling } ?? 0))
    }
    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        insertSublayer(layer, at: UInt32((sublayers?.firstIndex { $0 === sibling }).map { $0 + 1 } ?? (sublayers?.count ?? 0)))
    }
    open func removeFromSuperlayer() {
        superlayer?.sublayers?.removeAll { $0 === self }
        superlayer = nil
    }
    open func add(_ animation: CAAnimation, forKey key: String?) { if let key { animations[key] = animation } }
    open func removeAnimation(forKey key: String) { animations[key] = nil }
    open func removeAllAnimations() { animations = [:] }
    open func animation(forKey key: String) -> CAAnimation? { animations[key] }
    open func animationKeys() -> [String]? { animations.isEmpty ? nil : Array(animations.keys) }
    open func setNeedsDisplay() {}
    open func setNeedsLayout() {}
    open func layoutIfNeeded() {}
    open func displayIfNeeded() {}
    open func layoutSublayers() {}
    open func draw(in context: CGContext) {}
    open func render(in context: CGContext) {}
    open func presentation() -> Self? { self }
    open func setAffineTransform(_ m: CGAffineTransform) { transform = CATransform3DMakeAffineTransform(m) }
    open func affineTransform() -> CGAffineTransform {
        CGAffineTransform(a: transform.m11, b: transform.m12, c: transform.m21, d: transform.m22, tx: transform.m41, ty: transform.m42)
    }
}

open class CAShapeLayer: CALayer {
    public var path: CGPath?
    public var fillColor: CGColor? = .black
    public var strokeColor: CGColor?
    public var lineWidth: CGFloat = 1
    public var lineCap = CAShapeLayerLineCap.butt
    public var lineJoin = CAShapeLayerLineJoin.miter
    public var miterLimit: CGFloat = 10
    public var lineDashPattern: [NSNumber]?
    public var lineDashPhase: CGFloat = 0
    public var strokeStart: CGFloat = 0
    public var strokeEnd: CGFloat = 1
    public var fillRule = CAShapeLayerFillRule.nonZero
}
open class CAGradientLayer: CALayer {
    public var colors: [Any]?
    public var locations: [NSNumber]?
    public var startPoint = CGPoint(x: 0.5, y: 0)
    public var endPoint = CGPoint(x: 0.5, y: 1)
    public var type = CAGradientLayerType.axial
}
open class CATextLayer: CALayer {
    public var string: Any?
    public var fontSize: CGFloat = 36
    public var foregroundColor: CGColor? = .white
    public var isWrapped = false
    public var alignmentMode = "natural"
}
open class CAEmitterLayer: CALayer {
    public var emitterCells: [CAEmitterCell]?
    public var emitterPosition = CGPoint.zero
    public var emitterSize = CGSize.zero
    public var birthRate: Float = 1
}
open class CAEmitterCell: NSObject {
    public var birthRate: Float = 0
    public var lifetime: Float = 0
    public var velocity: CGFloat = 0
    public var scale: CGFloat = 1
    public var contents: Any?
    public var color: CGColor?
    public override init() { super.init() }
}
open class CAReplicatorLayer: CALayer {
    public var instanceCount = 1
    public var instanceDelay: CFTimeInterval = 0
    public var instanceTransform = CATransform3D()
}
open class CAMetalLayer: CALayer {}

public struct CAFrameRateRange: Equatable, Sendable {
    public var minimum: Float, maximum: Float, preferred: Float
    public init() { minimum = 0; maximum = 0; preferred = 0 }
    public init(minimum: Float, maximum: Float, preferred: Float? = nil) {
        self.minimum = minimum; self.maximum = maximum; self.preferred = preferred ?? 0
    }
    public static let `default` = CAFrameRateRange()
}

/// A display link that never calls its target: a screenshot is one frame. Timestamps read the clock.
public final class CADisplayLink: NSObject {
    public var isPaused = false
    public var preferredFramesPerSecond = 0
    public var preferredFrameRateRange = CAFrameRateRange.default
    public var timestamp: CFTimeInterval { CACurrentMediaTime() }
    public var targetTimestamp: CFTimeInterval { CACurrentMediaTime() + duration }
    public var duration: CFTimeInterval { 1.0 / 60 }

    public init(target: Any, selector sel: Selector) { super.init() }
    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func invalidate() {}
}
