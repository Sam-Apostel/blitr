internal import CSkia

// CGPath / CGMutablePath, and the path storage CGContext builds its current path in.
// SwiftUI's `Path(_: CGPath)` and `Path.cgPath` convert through `PathData.elements`.

public enum CGPathFillRule: Int, Sendable { case evenOdd, winding }
public enum CGPathDrawingMode: Int32, Sendable { case fill, eoFill, stroke, fillStroke, eoFillStroke }
public enum CGPathElementType: Int32, Sendable { case moveToPoint, addLineToPoint, addQuadCurveToPoint, addCurveToPoint, closeSubpath }

public struct CGPathElement {
    public var type: CGPathElementType
    public var points: UnsafeMutablePointer<CGPoint>
}

/// Path elements in one coordinate space, with the geometry CoreGraphics' path functions need.
package struct PathData: Equatable, Sendable {
    package enum Element: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, control: CGPoint)
        case curve(CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }
    package var elements: [Element] = []
    package init() {}
    package init(_ elements: [Element]) { self.elements = elements }

    package var isEmpty: Bool { elements.isEmpty }
    package var currentPoint: CGPoint? {
        var start: CGPoint?, current: CGPoint?
        for e in elements {
            switch e {
            case .move(let p): start = p; current = p
            case .line(let p), .quad(let p, _), .curve(let p, _, _): current = p
            case .close: current = start
            }
        }
        return current
    }

    package mutating func move(to p: CGPoint) { elements.append(.move(p)) }
    package mutating func line(to p: CGPoint) { elements.append(elements.isEmpty ? .move(p) : .line(p)) }
    package mutating func quad(to p: CGPoint, control c: CGPoint) {
        if elements.isEmpty { move(to: c) }
        elements.append(.quad(p, control: c))
    }
    package mutating func curve(to p: CGPoint, control1 c1: CGPoint, control2 c2: CGPoint) {
        if elements.isEmpty { move(to: c1) }
        elements.append(.curve(p, control1: c1, control2: c2))
    }
    package mutating func close() { if !elements.isEmpty { elements.append(.close) } }

    package mutating func addRect(_ r: CGRect, _ t: CGAffineTransform = .identity) {
        move(to: CGPoint(x: r.minX, y: r.minY).applying(t))
        line(to: CGPoint(x: r.maxX, y: r.minY).applying(t))
        line(to: CGPoint(x: r.maxX, y: r.maxY).applying(t))
        line(to: CGPoint(x: r.minX, y: r.maxY).applying(t))
        close()
    }
    package mutating func addEllipse(in r: CGRect, _ t: CGAffineTransform = .identity) {
        let k: CGFloat = 0.5522847498
        let (cx, cy, rx, ry) = (r.midX, r.midY, r.width / 2, r.height / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
        move(to: p(cx + rx, cy))
        curve(to: p(cx, cy + ry), control1: p(cx + rx, cy + k * ry), control2: p(cx + k * rx, cy + ry))
        curve(to: p(cx - rx, cy), control1: p(cx - k * rx, cy + ry), control2: p(cx - rx, cy + k * ry))
        curve(to: p(cx, cy - ry), control1: p(cx - rx, cy - k * ry), control2: p(cx - k * rx, cy - ry))
        curve(to: p(cx + rx, cy), control1: p(cx + k * rx, cy - ry), control2: p(cx + rx, cy - k * ry))
        close()
    }
    package mutating func addRoundedRect(_ r: CGRect, cornerWidth cw: CGFloat, cornerHeight ch: CGFloat, _ t: CGAffineTransform = .identity) {
        let rx = max(0, min(cw, r.width / 2)), ry = max(0, min(ch, r.height / 2))
        guard rx > 0, ry > 0 else { addRect(r, t); return }
        let k: CGFloat = 0.5522847498
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
        move(to: p(r.minX + rx, r.minY))
        line(to: p(r.maxX - rx, r.minY))
        curve(to: p(r.maxX, r.minY + ry), control1: p(r.maxX - rx + k * rx, r.minY), control2: p(r.maxX, r.minY + ry - k * ry))
        line(to: p(r.maxX, r.maxY - ry))
        curve(to: p(r.maxX - rx, r.maxY), control1: p(r.maxX, r.maxY - ry + k * ry), control2: p(r.maxX - rx + k * rx, r.maxY))
        line(to: p(r.minX + rx, r.maxY))
        curve(to: p(r.minX, r.maxY - ry), control1: p(r.minX + rx - k * rx, r.maxY), control2: p(r.minX, r.maxY - ry + k * ry))
        line(to: p(r.minX, r.minY + ry))
        curve(to: p(r.minX + rx, r.minY), control1: p(r.minX, r.minY + ry - k * ry), control2: p(r.minX + rx - k * rx, r.minY))
        close()
    }
    /// CoreGraphics' arc: `clockwise` is in the path's own coordinate space (y down reads the other way).
    package mutating func addArc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, clockwise: Bool, _ t: CGAffineTransform = .identity) {
        var (s, e) = (Double(start), Double(end))
        let twoPi = 2 * Double.pi
        if clockwise {
            while e > s { e -= twoPi }
            if s - e > twoPi { e = s - twoPi }
        } else {
            while e < s { e += twoPi }
            if e - s > twoPi { e = s + twoPi }
        }
        if start != end && abs(e - s) < 1e-9 { e = s + (clockwise ? -twoPi : twoPi) }
        addArcSegments(center: center, radius: radius, start: s, delta: e - s, t)
    }
    package mutating func addArcSegments(center: CGPoint, radius: CGFloat, start: Double, delta: Double, _ t: CGAffineTransform) {
        func point(_ a: Double) -> CGPoint { CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a))) }
        let first = point(start).applying(t)
        if currentPoint == nil { move(to: first) } else { line(to: first) }
        guard delta != 0 else { return }
        let segments = max(1, Int(ceil(abs(delta) / (Double.pi / 2))))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a = start
        for _ in 0..<segments {
            let b = a + step
            let p0 = point(a), p3 = point(b)
            let c1 = CGPoint(x: p0.x - CGFloat(k * sin(a)) * radius, y: p0.y + CGFloat(k * cos(a)) * radius)
            let c2 = CGPoint(x: p3.x + CGFloat(k * sin(b)) * radius, y: p3.y - CGFloat(k * cos(b)) * radius)
            curve(to: p3.applying(t), control1: c1.applying(t), control2: c2.applying(t))
            a = b
        }
    }
    package mutating func addArc(tangent1End p1: CGPoint, tangent2End p2: CGPoint, radius: CGFloat, _ t: CGAffineTransform = .identity) {
        guard let current = currentPoint else { move(to: p1.applying(t)); return }
        let inverse = t.inverted()
        let p0 = current.applying(inverse)
        let v1 = CGPoint(x: p0.x - p1.x, y: p0.y - p1.y), v2 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
        guard l1 > 0, l2 > 0, radius > 0 else { line(to: p1.applying(t)); return }
        let u1 = CGPoint(x: v1.x / l1, y: v1.y / l1), u2 = CGPoint(x: v2.x / l2, y: v2.y / l2)
        let theta = acos(Double(max(-1, min(1, u1.x * u2.x + u1.y * u2.y))))
        guard theta > 1e-6, abs(theta - .pi) > 1e-6 else { line(to: p1.applying(t)); return }
        let dist = radius / CGFloat(tan(theta / 2))
        let t1 = CGPoint(x: p1.x + u1.x * dist, y: p1.y + u1.y * dist), t2 = CGPoint(x: p1.x + u2.x * dist, y: p1.y + u2.y * dist)
        let bis = CGPoint(x: u1.x + u2.x, y: u1.y + u2.y), bl = hypot(bis.x, bis.y)
        let centerDist = radius / CGFloat(sin(theta / 2))
        let c = CGPoint(x: p1.x + bis.x / bl * centerDist, y: p1.y + bis.y / bl * centerDist)
        let a1 = atan2(Double(t1.y - c.y), Double(t1.x - c.x)), a2 = atan2(Double(t2.y - c.y), Double(t2.x - c.x))
        var delta = a2 - a1
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        line(to: t1.applying(t))
        addArcSegments(center: c, radius: radius, start: a1, delta: delta, t)
    }

    package func applying(_ t: CGAffineTransform) -> PathData {
        guard !t.isIdentity else { return self }
        return PathData(elements.map { e in
            switch e {
            case .move(let p): return .move(p.applying(t))
            case .line(let p): return .line(p.applying(t))
            case .quad(let p, let c): return .quad(p.applying(t), control: c.applying(t))
            case .curve(let p, let c1, let c2): return .curve(p.applying(t), control1: c1.applying(t), control2: c2.applying(t))
            case .close: return .close
            }
        })
    }

    /// The box around every point, control points included.
    package var controlBounds: CGRect {
        var points: [CGPoint] = []
        for e in elements {
            switch e {
            case .move(let p), .line(let p): points.append(p)
            case .quad(let p, let c): points += [p, c]
            case .curve(let p, let c1, let c2): points += [p, c1, c2]
            case .close: break
            }
        }
        guard let first = points.first else { return .null }
        var (x0, y0, x1, y1) = (first.x, first.y, first.x, first.y)
        for p in points { x0 = min(x0, p.x); y0 = min(y0, p.y); x1 = max(x1, p.x); y1 = max(y1, p.y) }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    package var tightBounds: CGRect {
        guard !isEmpty else { return .null }
        return withSkPath { sk in
            var r = sk_rect_t()
            sk_path_compute_tight_bounds(sk, &r)
            return CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.right - r.left), height: CGFloat(r.bottom - r.top))
        }
    }
    package func contains(_ p: CGPoint, evenOdd: Bool) -> Bool { withSkPath(evenOdd: evenOdd) { sk_path_contains($0, Float(p.x), Float(p.y)) } }

    /// The outline of the path stroked (or, with a zero width and a dash, its dashed centre lines).
    package func stroked(width: CGFloat, cap: CGLineCap, join: CGLineJoin, miter: CGFloat, dash: [CGFloat] = [], phase: CGFloat = 0) -> PathData {
        withSkPath { sk in
            let paint = sk_paint_new()!
            defer { sk_paint_delete(paint) }
            PathData.applyStroke(to: paint, width: width, cap: cap, join: join, miter: miter, dash: dash, phase: phase)
            let builder = sk_pathbuilder_new()
            var identity = sk_matrix_t(scaleX: 1, skewX: 0, transX: 0, skewY: 0, scaleY: 1, transY: 0, persp0: 0, persp1: 0, persp2: 1)
            _ = sk_paint_get_fill_path(paint, sk, builder, nil, &identity)
            let out = sk_pathbuilder_detach_path(builder)!
            sk_pathbuilder_delete(builder)
            defer { sk_path_delete(out) }
            return PathData(skPath: out)
        }
    }

    static func applyStroke(to paint: OpaquePointer, width: CGFloat, cap: CGLineCap, join: CGLineJoin, miter: CGFloat, dash: [CGFloat], phase: CGFloat) {
        sk_paint_set_style(paint, STROKE_SK_PAINT_STYLE)
        sk_paint_set_stroke_width(paint, Float(width))
        sk_paint_set_stroke_miter(paint, Float(miter))
        sk_paint_set_stroke_cap(paint, [BUTT_SK_STROKE_CAP, ROUND_SK_STROKE_CAP, SQUARE_SK_STROKE_CAP][Int(cap.rawValue)])
        sk_paint_set_stroke_join(paint, [MITER_SK_STROKE_JOIN, ROUND_SK_STROKE_JOIN, BEVEL_SK_STROKE_JOIN][Int(join.rawValue)])
        if !dash.isEmpty {
            var intervals = dash.map { Float($0) }
            if intervals.count % 2 == 1 { intervals += intervals }
            let effect = sk_path_effect_create_dash(intervals, Int32(intervals.count), Float(phase))
            sk_paint_set_path_effect(paint, effect)
            sk_path_effect_unref(effect)
        }
    }

    init(skPath: OpaquePointer) {
        let iter = sk_path_create_rawiter(skPath)
        defer { sk_path_rawiter_destroy(iter) }
        var pts = [sk_point_t](repeating: sk_point_t(), count: 4)
        func p(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(pts[i].x), y: CGFloat(pts[i].y)) }
        while true {
            switch sk_path_rawiter_next(iter, &pts) {
            case MOVE_SK_PATH_VERB: elements.append(.move(p(0)))
            case LINE_SK_PATH_VERB: elements.append(.line(p(1)))
            case QUAD_SK_PATH_VERB: elements.append(.quad(p(2), control: p(1)))
            case CONIC_SK_PATH_VERB:
                let w = CGFloat(sk_path_rawiter_conic_weight(iter)), k = 4 * w / (3 * (1 + w))
                let c1 = CGPoint(x: p(0).x + (p(1).x - p(0).x) * k, y: p(0).y + (p(1).y - p(0).y) * k)
                let c2 = CGPoint(x: p(2).x + (p(1).x - p(2).x) * k, y: p(2).y + (p(1).y - p(2).y) * k)
                elements.append(.curve(p(2), control1: c1, control2: c2))
            case CUBIC_SK_PATH_VERB: elements.append(.curve(p(3), control1: p(1), control2: p(2)))
            case CLOSE_SK_PATH_VERB: elements.append(.close)
            default: return
            }
        }
    }

    func withSkPath<R>(evenOdd: Bool = false, _ body: (OpaquePointer) -> R) -> R {
        let builder = sk_pathbuilder_new()
        if evenOdd { sk_pathbuilder_set_filltype(builder, EVENODD_SK_PATH_FILLTYPE) }
        for e in elements {
            switch e {
            case .move(let p): sk_pathbuilder_move_to(builder, Float(p.x), Float(p.y))
            case .line(let p): sk_pathbuilder_line_to(builder, Float(p.x), Float(p.y))
            case .quad(let p, let c): sk_pathbuilder_quad_to(builder, Float(c.x), Float(c.y), Float(p.x), Float(p.y))
            case .curve(let p, let c1, let c2): sk_pathbuilder_cubic_to(builder, Float(c1.x), Float(c1.y), Float(c2.x), Float(c2.y), Float(p.x), Float(p.y))
            case .close: sk_pathbuilder_close(builder)
            }
        }
        let path = sk_pathbuilder_detach_path(builder)!
        sk_pathbuilder_delete(builder)
        defer { sk_path_delete(path) }
        return body(path)
    }
}

public class CGPath: Hashable, @unchecked Sendable {
    package var data: PathData
    package init(data: PathData) { self.data = data }

    public convenience init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        var p = PathData()
        p.addRect(rect, transform?.pointee ?? .identity)
        self.init(data: p)
    }
    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        var p = PathData()
        p.addEllipse(in: rect, transform?.pointee ?? .identity)
        self.init(data: p)
    }
    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) {
        var p = PathData()
        p.addRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform?.pointee ?? .identity)
        self.init(data: p)
    }

    public var isEmpty: Bool { data.isEmpty }
    public var currentPoint: CGPoint { data.currentPoint ?? .zero }
    public var boundingBox: CGRect { data.controlBounds }
    public var boundingBoxOfPath: CGRect { data.tightBounds }
    public func isRect(_ rect: UnsafeMutablePointer<CGRect>?) -> Bool {
        let e = data.elements
        guard e.count >= 5, e.count <= 6, case .move(let a) = e[0], case .line(let b) = e[1], case .line(let c) = e[2], case .line(let d) = e[3] else { return false }
        let axisAligned = (a.y == b.y && b.x == c.x && c.y == d.y && d.x == a.x) || (a.x == b.x && b.y == c.y && c.x == d.x && d.y == a.y)
        if axisAligned { rect?.pointee = data.controlBounds }
        return axisAligned
    }
    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        data.contains(point.applying(transform), evenOdd: rule == .evenOdd)
    }

    public func copy() -> CGPath? { CGPath(data: data) }
    public func mutableCopy() -> CGMutablePath? { CGMutablePath(data: data) }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? { CGPath(data: data.applying(transform?.pointee ?? .identity)) }
    public func mutableCopy(using transform: UnsafePointer<CGAffineTransform>?) -> CGMutablePath? {
        CGMutablePath(data: data.applying(transform?.pointee ?? .identity))
    }
    public func copy(strokingWithWidth lineWidth: CGFloat, lineCap: CGLineCap, lineJoin: CGLineJoin, miterLimit: CGFloat,
                     transform: CGAffineTransform = .identity) -> CGPath {
        CGPath(data: data.stroked(width: lineWidth, cap: lineCap, join: lineJoin, miter: miterLimit).applying(transform))
    }
    public func copy(dashingWithPhase phase: CGFloat, lengths: [CGFloat], transform: CGAffineTransform = .identity) -> CGPath {
        CGPath(data: data.stroked(width: 0, cap: .butt, join: .miter, miter: 10, dash: lengths, phase: phase).applying(transform))
    }

    public func applyWithBlock(_ block: (UnsafePointer<CGPathElement>) -> Void) {
        let points = UnsafeMutablePointer<CGPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for element in data.elements {
            let type: CGPathElementType
            switch element {
            case .move(let p): type = .moveToPoint; points[0] = p
            case .line(let p): type = .addLineToPoint; points[0] = p
            case .quad(let p, let c): type = .addQuadCurveToPoint; points[0] = c; points[1] = p
            case .curve(let p, let c1, let c2): type = .addCurveToPoint; points[0] = c1; points[1] = c2; points[2] = p
            case .close: type = .closeSubpath
            }
            var e = CGPathElement(type: type, points: points)
            block(&e)
        }
    }

    public static func == (a: CGPath, b: CGPath) -> Bool { a.data == b.data }
    public func hash(into hasher: inout Hasher) { hasher.combine(data.elements.count) }
}

public final class CGMutablePath: CGPath {
    public init() { super.init(data: PathData()) }
    override package init(data: PathData) { super.init(data: data) }

    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) { data.move(to: point.applying(transform)) }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) { data.line(to: point.applying(transform)) }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        guard let first = points.first else { return }
        data.move(to: first.applying(transform))
        for p in points.dropFirst() { data.line(to: p.applying(transform)) }
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        data.quad(to: end.applying(transform), control: control.applying(transform))
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        data.curve(to: end.applying(transform), control1: control1.applying(transform), control2: control2.applying(transform))
    }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { data.addRect(rect, transform) }
    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { rects.forEach { data.addRect($0, transform) } }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { data.addEllipse(in: rect, transform) }
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {
        data.addRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform)
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) {
        data.addArc(center: center, radius: radius, start: startAngle, end: endAngle, clockwise: clockwise, transform)
    }
    public func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, delta: CGFloat, transform: CGAffineTransform = .identity) {
        data.addArcSegments(center: center, radius: radius, start: Double(startAngle), delta: Double(delta), transform)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        data.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius, transform)
    }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) { data.elements += path.data.applying(transform).elements }
    public func closeSubpath() { data.close() }
}
