// Core Graphics geometry that Foundation on Linux lacks (CGFloat, CGPoint, CGSize and CGRect are Foundation's).

public struct CGVector: Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public static let zero = CGVector()
}

public struct CGAffineTransform: Hashable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    public init() { a = 1; b = 0; c = 0; d = 1; tx = 0; ty = 0 }
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle r: CGFloat) {
        let (s, c) = (CGFloat(sin(Double(r))), CGFloat(cos(Double(r))))
        self.init(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }
    public static let identity = CGAffineTransform()
    public var isIdentity: Bool { self == .identity }
    /// Returns `self` followed by `t2` (matches CoreGraphics' `concatenating`).
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: a * t2.a + b * t2.c, b: a * t2.b + b * t2.d,
            c: c * t2.a + d * t2.c, d: c * t2.b + d * t2.d,
            tx: tx * t2.a + ty * t2.c + t2.tx, ty: tx * t2.b + ty * t2.d + t2.ty)
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).concatenating(self)
    }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y).concatenating(self)
    }
    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(self)
    }
    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return CGAffineTransform(a: d / det, b: -b / det, c: -c / det, d: a / det,
                                 tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

public enum CGLineCap: Int32, Sendable { case butt, round, square }
public enum CGLineJoin: Int32, Sendable { case miter, round, bevel }

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

extension CGRect {
    public func applying(_ t: CGAffineTransform) -> CGRect {
        let pts = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                   CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)].map { $0.applying(t) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
