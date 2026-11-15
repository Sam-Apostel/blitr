#if canImport(Darwin)
// The Swift API of Apple's Core Graphics overlay for the geometry structs CoreFoundation declares in C
// (CGPoint, CGSize, CGVector, CGRect, CGAffineTransform). On Linux, Foundation has it all.

extension CGPoint {
    public static var zero: CGPoint { CGPoint(x: 0 as CGFloat, y: 0 as CGFloat) }
    @_transparent public init(x: Int, y: Int) { self.init(x: CGFloat(x), y: CGFloat(y)) }
    @_transparent public init(x: Double, y: Double) { self.init(x: CGFloat(x), y: CGFloat(y)) }
}

extension CGPoint: @retroactive Equatable, @retroactive Hashable, @retroactive Codable, @retroactive CustomDebugStringConvertible {
    public static func == (l: CGPoint, r: CGPoint) -> Bool { l.x == r.x && l.y == r.y }
    public func hash(into h: inout Hasher) { h.combine(x); h.combine(y) }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(x: try c.decode(CGFloat.self), y: try c.decode(CGFloat.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer(); try c.encode(x); try c.encode(y)
    }
    public var debugDescription: String { "(\(x), \(y))" }
}

extension CGSize {
    public static var zero: CGSize { CGSize(width: 0 as CGFloat, height: 0 as CGFloat) }
    @_transparent public init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }
    @_transparent public init(width: Double, height: Double) { self.init(width: CGFloat(width), height: CGFloat(height)) }
}

extension CGSize: @retroactive Equatable, @retroactive Hashable, @retroactive Codable, @retroactive CustomDebugStringConvertible {
    public static func == (l: CGSize, r: CGSize) -> Bool { l.width == r.width && l.height == r.height }
    public func hash(into h: inout Hasher) { h.combine(width); h.combine(height) }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(width: try c.decode(CGFloat.self), height: try c.decode(CGFloat.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer(); try c.encode(width); try c.encode(height)
    }
    public var debugDescription: String { "(\(width), \(height))" }
}

extension CGVector {
    public static var zero: CGVector { CGVector(dx: 0 as CGFloat, dy: 0 as CGFloat) }
    @_transparent public init(dx: Int, dy: Int) { self.init(dx: CGFloat(dx), dy: CGFloat(dy)) }
    @_transparent public init(dx: Double, dy: Double) { self.init(dx: CGFloat(dx), dy: CGFloat(dy)) }
}

extension CGVector: @retroactive Equatable, @retroactive Hashable, @retroactive Codable, @retroactive CustomDebugStringConvertible {
    public static func == (l: CGVector, r: CGVector) -> Bool { l.dx == r.dx && l.dy == r.dy }
    public func hash(into h: inout Hasher) { h.combine(dx); h.combine(dy) }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(dx: try c.decode(CGFloat.self), dy: try c.decode(CGFloat.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer(); try c.encode(dx); try c.encode(dy)
    }
    public var debugDescription: String { "(\(dx), \(dy))" }
}

extension CGRect {
    public static var zero: CGRect { CGRect(origin: .zero, size: .zero) }
    public static var null: CGRect { CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0) }
    public static var infinite: CGRect {
        let big = CGFloat.greatestFiniteMagnitude
        return CGRect(x: -big / 2, y: -big / 2, width: big, height: big)
    }
    @_transparent public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
    @_transparent public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
    @_transparent public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    public var width: CGFloat { abs(size.width) }
    public var height: CGFloat { abs(size.height) }
    public var minX: CGFloat { isNull ? .infinity : min(origin.x, origin.x + size.width) }
    public var maxX: CGFloat { isNull ? .infinity : max(origin.x, origin.x + size.width) }
    public var midX: CGFloat { isNull ? .infinity : origin.x + size.width / 2 }
    public var minY: CGFloat { isNull ? .infinity : min(origin.y, origin.y + size.height) }
    public var maxY: CGFloat { isNull ? .infinity : max(origin.y, origin.y + size.height) }
    public var midY: CGFloat { isNull ? .infinity : origin.y + size.height / 2 }
    public var isNull: Bool { origin.x.isInfinite || origin.y.isInfinite }
    public var isEmpty: Bool { isNull || size.width == 0 || size.height == 0 }
    public var isInfinite: Bool { self == .infinite }

    public var standardized: CGRect {
        isNull ? .null : CGRect(x: minX, y: minY, width: width, height: height)
    }
    public var integral: CGRect {
        if isNull { return self }
        let r = standardized
        let x0 = r.minX.rounded(.down), y0 = r.minY.rounded(.down)
        return CGRect(x: x0, y: y0, width: r.maxX.rounded(.up) - x0, height: r.maxY.rounded(.up) - y0)
    }
    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        let r = standardized
        let w = r.width - 2 * dx, h = r.height - 2 * dy
        if w < 0 || h < 0 { return .null }
        return CGRect(x: r.minX + dx, y: r.minY + dy, width: w, height: h)
    }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        var r = standardized
        r.origin.x += dx; r.origin.y += dy
        return r
    }
    public func union(_ r2: CGRect) -> CGRect {
        if isNull { return r2 }
        if r2.isNull { return self }
        let x0 = min(minX, r2.minX), y0 = min(minY, r2.minY)
        return CGRect(x: x0, y: y0, width: max(maxX, r2.maxX) - x0, height: max(maxY, r2.maxY) - y0)
    }
    public func intersection(_ r2: CGRect) -> CGRect {
        if isNull || r2.isNull { return .null }
        let x0 = max(minX, r2.minX), y0 = max(minY, r2.minY)
        let x1 = min(maxX, r2.maxX), y1 = min(maxY, r2.maxY)
        if x1 < x0 || y1 < y0 { return .null }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    public func intersects(_ r2: CGRect) -> Bool {
        let i = intersection(r2)
        return !i.isNull && !i.isEmpty
    }
    public func contains(_ point: CGPoint) -> Bool {
        !isNull && point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
    public func contains(_ r2: CGRect) -> Bool {
        !isNull && !r2.isNull && union(r2) == self
    }
    public func divided(atDistance distance: CGFloat, from edge: CGRectEdge) -> (slice: CGRect, remainder: CGRect) {
        let r = standardized
        switch edge {
        case .minXEdge:
            let d = min(max(distance, 0), r.width)
            return (CGRect(x: r.minX, y: r.minY, width: d, height: r.height),
                    CGRect(x: r.minX + d, y: r.minY, width: r.width - d, height: r.height))
        case .maxXEdge:
            let d = min(max(distance, 0), r.width)
            return (CGRect(x: r.maxX - d, y: r.minY, width: d, height: r.height),
                    CGRect(x: r.minX, y: r.minY, width: r.width - d, height: r.height))
        case .minYEdge:
            let d = min(max(distance, 0), r.height)
            return (CGRect(x: r.minX, y: r.minY, width: r.width, height: d),
                    CGRect(x: r.minX, y: r.minY + d, width: r.width, height: r.height - d))
        case .maxYEdge:
            let d = min(max(distance, 0), r.height)
            return (CGRect(x: r.minX, y: r.maxY - d, width: r.width, height: d),
                    CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - d))
        @unknown default:
            return (r, .zero)
        }
    }
    public mutating func formUnion(_ r2: CGRect) { self = union(r2) }
    public mutating func formIntersection(_ r2: CGRect) { self = intersection(r2) }
}

extension CGRect: @retroactive Equatable, @retroactive Hashable, @retroactive Codable, @retroactive CustomDebugStringConvertible {
    public static func == (l: CGRect, r: CGRect) -> Bool {
        if l.isNull || r.isNull { return l.isNull == r.isNull }
        let a = l.standardized, b = r.standardized
        return a.origin == b.origin && a.size == b.size
    }
    public func hash(into h: inout Hasher) { h.combine(origin); h.combine(size) }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(origin: try c.decode(CGPoint.self), size: try c.decode(CGSize.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer(); try c.encode(origin); try c.encode(size)
    }
    public var debugDescription: String { "(\(origin.x), \(origin.y), \(size.width), \(size.height))" }
}

extension CGAffineTransform: @retroactive Equatable, @retroactive Hashable, @retroactive Codable {
    public static func == (l: CGAffineTransform, r: CGAffineTransform) -> Bool {
        l.a == r.a && l.b == r.b && l.c == r.c && l.d == r.d && l.tx == r.tx && l.ty == r.ty
    }
    public func hash(into h: inout Hasher) { for v in [a, b, c, d, tx, ty] { h.combine(v) } }
    public init(from decoder: Decoder) throws {
        var k = try decoder.unkeyedContainer()
        self.init(a: try k.decode(CGFloat.self), b: try k.decode(CGFloat.self), c: try k.decode(CGFloat.self),
                  d: try k.decode(CGFloat.self), tx: try k.decode(CGFloat.self), ty: try k.decode(CGFloat.self))
    }
    public func encode(to encoder: Encoder) throws {
        var k = encoder.unkeyedContainer()
        for v in [a, b, c, d, tx, ty] { try k.encode(v) }
    }
}
#endif
