internal import CSkia

public enum RoundedCornerStyle: Hashable, Sendable { case circular, continuous }

public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true) { isEOFilled = eoFill; isAntialiased = antialiased }
}

public enum CGLineCap: Int32, Sendable { case butt, round, square }
public enum CGLineJoin: Int32, Sendable { case miter, round, bevel }

public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter,
                miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin
        self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
    }
}

public struct Path: Equatable, Sendable {
    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }
    var elements: [Element] = []

    public init() {}
    public init(_ rect: CGRect) { addRect(rect) }
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        addUnevenRoundedRect(rect, cornerRadii)
    }
    public init(ellipseIn rect: CGRect) { addEllipse(in: rect) }
    public init(_ callback: (inout Path) -> Void) { callback(&self) }

    public var isEmpty: Bool { elements.isEmpty }
    public var currentPoint: CGPoint? {
        var start: CGPoint?, current: CGPoint?
        for e in elements {
            switch e {
            case .move(let p): start = p; current = p
            case .line(let p): current = p
            case .quadCurve(let p, _): current = p
            case .curve(let p, _, _): current = p
            case .closeSubpath: current = start
            }
        }
        return current
    }
    public func forEach(_ body: (Element) -> Void) { elements.forEach(body) }

    // MARK: Building

    public mutating func move(to p: CGPoint) { elements.append(.move(to: p)) }
    public mutating func addLine(to p: CGPoint) {
        if elements.isEmpty { elements.append(.move(to: p)) } else { elements.append(.line(to: p)) }
    }
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { elements.append(.quadCurve(to: p, control: control)) }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.curve(to: p, control1: control1, control2: control2))
    }
    public mutating func closeSubpath() { elements.append(.closeSubpath) }

    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        addPath(p, transform: transform)
    }
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        for r in rects { addRect(r, transform: transform) }
    }
    public mutating func addLines(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for p in points.dropFirst() { addLine(to: p) }
    }
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let k: CGFloat = 0.5522847498
        let (cx, cy, rx, ry) = (rect.midX, rect.midY, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: cx + rx, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + k * ry), control2: CGPoint(x: cx + k * rx, y: cy + ry))
        p.addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - k * rx, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + k * ry))
        p.addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - k * ry), control2: CGPoint(x: cx - k * rx, y: cy - ry))
        p.addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + k * rx, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - k * ry))
        p.closeSubpath()
        addPath(p, transform: transform)
    }
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) {
        let r = min(cornerSize.width, cornerSize.height)
        var p = Path()
        p.addUnevenRoundedRect(rect, RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r), style: style)
        addPath(p, transform: transform)
    }
    public mutating func addRoundedRect(in rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) {
        var p = Path()
        p.addUnevenRoundedRect(rect, cornerRadii, style: style)
        addPath(p, transform: transform)
    }

    mutating func addUnevenRoundedRect(_ rect: CGRect, _ radii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        let limit = min(rect.width, rect.height) / 2
        let tl = max(0, min(radii.topLeading, limit)), tr = max(0, min(radii.topTrailing, limit))
        let bl = max(0, min(radii.bottomLeading, limit)), br = max(0, min(radii.bottomTrailing, limit))
        if tl == 0 && tr == 0 && bl == 0 && br == 0 { addRect(rect); return }
        // Apple's "continuous" corner extends 1.528665 * r along each edge. When the corner is too
        // large for that to fit it degrades towards a circular arc, which is what we fall back to.
        let continuous = style == .continuous && max(tl, tr, bl, br) * 1.528665 <= limit + 0.001
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)

        // Each corner is drawn in a local frame: `c` is the corner point, `u` runs along the incoming
        // edge towards the corner and `v` along the outgoing edge away from it.
        func corner(_ c: CGPoint, _ u: CGVector, _ v: CGVector, _ r: CGFloat, first: Bool) {
            func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
                // a: distance back along the incoming edge, b: distance forward along the outgoing edge
                CGPoint(x: c.x - u.dx * a * r + v.dx * b * r, y: c.y - u.dy * a * r + v.dy * b * r)
            }
            if r == 0 { first ? move(to: c) : addLine(to: c); return }
            if continuous {
                let start = pt(1.528665, 0)
                first ? move(to: start) : addLine(to: start)
                addCurve(to: pt(0.63149379, 0.07491139), control1: pt(1.08849296, 0), control2: pt(0.86840694, 0))
                addCurve(to: pt(0.07491139, 0.63149379), control1: pt(0.37282383, 0.16905956), control2: pt(0.16905956, 0.37282383))
                addCurve(to: pt(0, 1.528665), control1: pt(0, 0.86840694), control2: pt(0, 1.08849296))
            } else {
                let k: CGFloat = 0.5522847498
                let start = pt(1, 0)
                first ? move(to: start) : addLine(to: start)
                addCurve(to: pt(0, 1), control1: pt(1 - k, 0), control2: pt(0, 1 - k))
            }
        }
        corner(CGPoint(x: x1, y: y0), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1), tr, first: true)
        corner(CGPoint(x: x1, y: y1), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), br, first: false)
        corner(CGPoint(x: x0, y: y1), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), bl, first: false)
        corner(CGPoint(x: x0, y: y0), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0), tl, first: false)
        closeSubpath()
    }

    /// Angles follow CoreGraphics in a y-down space: `clockwise: false` sweeps visually clockwise.
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool,
                                transform: CGAffineTransform = .identity) {
        var start = startAngle.radians, end = endAngle.radians
        let twoPi = 2 * Double.pi
        if clockwise {
            while end > start { end -= twoPi }
            if start - end > twoPi { end = start - twoPi }
        } else {
            while end < start { end += twoPi }
            if end - start > twoPi { end = start + twoPi }
        }
        if startAngle.radians != endAngle.radians && abs(end - start) < 1e-9 { end = start + (clockwise ? -twoPi : twoPi) }
        addArcSegments(center: center, radius: radius, start: start, delta: end - start, transform: transform)
    }

    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle,
                                        transform: CGAffineTransform = .identity) {
        addArcSegments(center: center, radius: radius, start: startAngle.radians, delta: delta.radians, transform: transform)
    }

    private mutating func addArcSegments(center: CGPoint, radius: CGFloat, start: Double, delta: Double, transform t: CGAffineTransform) {
        func point(_ a: Double) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a))).applying(t)
        }
        let first = point(start)
        if elements.isEmpty || currentPoint == nil { move(to: first) } else { addLine(to: first) }
        guard delta != 0 else { return }
        let segments = max(1, Int(ceil(abs(delta) / (Double.pi / 2))))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a = start
        for _ in 0..<segments {
            let b = a + step
            let p0 = CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
            let p3 = CGPoint(x: center.x + radius * CGFloat(cos(b)), y: center.y + radius * CGFloat(sin(b)))
            let c1 = CGPoint(x: p0.x - CGFloat(k * sin(a)) * radius, y: p0.y + CGFloat(k * cos(a)) * radius)
            let c2 = CGPoint(x: p3.x + CGFloat(k * sin(b)) * radius, y: p3.y - CGFloat(k * cos(b)) * radius)
            addCurve(to: p3.applying(t), control1: c1.applying(t), control2: c2.applying(t))
            a = b
        }
    }

    public mutating func addArc(tangent1End p1: CGPoint, tangent2End p2: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        guard let p0 = currentPoint else { move(to: p1); return }
        let v1 = CGPoint(x: p0.x - p1.x, y: p0.y - p1.y), v2 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
        guard l1 > 0, l2 > 0, radius > 0 else { addLine(to: p1); return }
        let u1 = CGPoint(x: v1.x / l1, y: v1.y / l1), u2 = CGPoint(x: v2.x / l2, y: v2.y / l2)
        let cosTheta = max(-1, min(1, u1.x * u2.x + u1.y * u2.y))
        let theta = acos(Double(cosTheta))
        guard theta > 1e-6, abs(theta - .pi) > 1e-6 else { addLine(to: p1); return }
        let dist = radius / CGFloat(tan(theta / 2))
        let t1 = CGPoint(x: p1.x + u1.x * dist, y: p1.y + u1.y * dist)
        let t2 = CGPoint(x: p1.x + u2.x * dist, y: p1.y + u2.y * dist)
        let bis = CGPoint(x: u1.x + u2.x, y: u1.y + u2.y), bl = hypot(bis.x, bis.y)
        let centerDist = radius / CGFloat(sin(theta / 2))
        let c = CGPoint(x: p1.x + bis.x / bl * centerDist, y: p1.y + bis.y / bl * centerDist)
        let a1 = atan2(Double(t1.y - c.y), Double(t1.x - c.x)), a2 = atan2(Double(t2.y - c.y), Double(t2.x - c.x))
        var delta = a2 - a1
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        addLine(to: t1.applying(transform))
        addArcSegments(center: c, radius: radius, start: a1, delta: delta, transform: transform)
    }

    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        if transform.isIdentity { elements.append(contentsOf: path.elements) } else { elements.append(contentsOf: path.applying(transform).elements) }
    }

    // MARK: Derived paths

    public func applying(_ t: CGAffineTransform) -> Path {
        var result = Path()
        result.elements = elements.map { e in
            switch e {
            case .move(let p): return .move(to: p.applying(t))
            case .line(let p): return .line(to: p.applying(t))
            case .quadCurve(let p, let c): return .quadCurve(to: p.applying(t), control: c.applying(t))
            case .curve(let p, let c1, let c2): return .curve(to: p.applying(t), control1: c1.applying(t), control2: c2.applying(t))
            case .closeSubpath: return .closeSubpath
            }
        }
        return result
    }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { applying(CGAffineTransform(translationX: dx, y: dy)) }

    public var boundingRect: CGRect {
        guard !isEmpty else { return .null }
        return withSkPath { sk in
            var r = sk_rect_t()
            sk_path_compute_tight_bounds(sk, &r)
            return CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.right - r.left), height: CGFloat(r.bottom - r.top))
        }
    }

    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        withSkPath(evenOdd: eoFill) { sk_path_contains($0, Float(p.x), Float(p.y)) }
    }

    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let from = max(0, min(1, from)), to = max(0, min(1, to))
        guard to > from else { return Path() }
        if from == 0 && to == 1 { return self }
        return withSkPath { sk in
            // Total length over all contours, then cut the requested window out of each contour.
            var lengths: [Float] = []
            let pm = sk_pathmeasure_new_with_path(sk, false, 1)
            repeat { lengths.append(sk_pathmeasure_get_length(pm)) } while sk_pathmeasure_next_contour(pm)
            sk_pathmeasure_destroy(pm)
            let total = lengths.reduce(0, +)
            let start = Float(from) * total, stop = Float(to) * total
            let builder = sk_pathbuilder_new()
            let pm2 = sk_pathmeasure_new_with_path(sk, false, 1)
            var offset: Float = 0, index = 0
            repeat {
                let length = lengths[index]
                let a = max(start - offset, 0), b = min(stop - offset, length)
                if b > a { _ = sk_pathmeasure_get_segment(pm2, a, b, builder, true) }
                offset += length
                index += 1
            } while sk_pathmeasure_next_contour(pm2) && index < lengths.count
            sk_pathmeasure_destroy(pm2)
            let out = sk_pathbuilder_detach_path(builder)
            sk_pathbuilder_delete(builder)
            defer { sk_path_delete(out) }
            return Path(skPath: out!)
        }
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        withSkPath { sk in
            let paint = sk_paint_new()
            defer { sk_paint_delete(paint) }
            Painter.applyStroke(style, to: paint!)
            let builder = sk_pathbuilder_new()
            // Skia dereferences the matrix, so identity must be passed explicitly.
            var identity = sk_matrix_t(scaleX: 1, skewX: 0, transX: 0, skewY: 0, scaleY: 1, transY: 0, persp0: 0, persp1: 0, persp2: 1)
            _ = sk_paint_get_fill_path(paint, sk, builder, nil, &identity)
            let out = sk_pathbuilder_detach_path(builder)
            sk_pathbuilder_delete(builder)
            defer { sk_path_delete(out) }
            return Path(skPath: out!)
        }
    }

    // MARK: Skia bridging

    init(skPath: OpaquePointer) {
        let iter = sk_path_create_rawiter(skPath)
        defer { sk_path_rawiter_destroy(iter) }
        var pts = [sk_point_t](repeating: sk_point_t(), count: 4)
        func p(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(pts[i].x), y: CGFloat(pts[i].y)) }
        while true {
            let verb = sk_path_rawiter_next(iter, &pts)
            switch verb {
            case MOVE_SK_PATH_VERB: elements.append(.move(to: p(0)))
            case LINE_SK_PATH_VERB: elements.append(.line(to: p(1)))
            case QUAD_SK_PATH_VERB: elements.append(.quadCurve(to: p(2), control: p(1)))
            case CONIC_SK_PATH_VERB:
                // Approximate the conic by a cubic through the same control point.
                let w = CGFloat(sk_path_rawiter_conic_weight(iter))
                let k = 4 * w / (3 * (1 + w))
                let c1 = CGPoint(x: p(0).x + (p(1).x - p(0).x) * k, y: p(0).y + (p(1).y - p(0).y) * k)
                let c2 = CGPoint(x: p(2).x + (p(1).x - p(2).x) * k, y: p(2).y + (p(1).y - p(2).y) * k)
                elements.append(.curve(to: p(2), control1: c1, control2: c2))
            case CUBIC_SK_PATH_VERB: elements.append(.curve(to: p(3), control1: p(1), control2: p(2)))
            case CLOSE_SK_PATH_VERB: elements.append(.closeSubpath)
            default: return
            }
        }
    }

    /// Builds a temporary Skia path for the duration of `body`.
    func withSkPath<R>(evenOdd: Bool = false, _ body: (OpaquePointer) -> R) -> R {
        let builder = sk_pathbuilder_new()
        if evenOdd { sk_pathbuilder_set_filltype(builder, EVENODD_SK_PATH_FILLTYPE) }
        for e in elements {
            switch e {
            case .move(let p): sk_pathbuilder_move_to(builder, Float(p.x), Float(p.y))
            case .line(let p): sk_pathbuilder_line_to(builder, Float(p.x), Float(p.y))
            case .quadCurve(let p, let c): sk_pathbuilder_quad_to(builder, Float(c.x), Float(c.y), Float(p.x), Float(p.y))
            case .curve(let p, let c1, let c2):
                sk_pathbuilder_cubic_to(builder, Float(c1.x), Float(c1.y), Float(c2.x), Float(c2.y), Float(p.x), Float(p.y))
            case .closeSubpath: sk_pathbuilder_close(builder)
            }
        }
        let path = sk_pathbuilder_detach_path(builder)!
        sk_pathbuilder_delete(builder)
        defer { sk_path_delete(path) }
        return body(path)
    }
}

public struct RectangleCornerRadii: Equatable, Sendable {
    public var topLeading: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat, topTrailing: CGFloat
    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading; self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing; self.topTrailing = topTrailing
    }
}
