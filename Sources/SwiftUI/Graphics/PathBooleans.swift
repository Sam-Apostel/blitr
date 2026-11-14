internal import CSkia

// iOS 17 path boolean operations, computed with Skia's path ops. The line operations keep the parts of
// this path's outline (its lines, not its fill) inside or outside the other path's filled area.

extension Path {
    public func union(_ other: Path, eoFill: Bool = false) -> Path { booleanOp(other, UNION_SK_PATHOP, eoFill) }
    public func intersection(_ other: Path, eoFill: Bool = false) -> Path { booleanOp(other, INTERSECT_SK_PATHOP, eoFill) }
    public func subtracting(_ other: Path, eoFill: Bool = false) -> Path { booleanOp(other, DIFFERENCE_SK_PATHOP, eoFill) }
    public func symmetricDifference(_ other: Path, eoFill: Bool = false) -> Path { booleanOp(other, XOR_SK_PATHOP, eoFill) }
    /// This path with overlapping and self-intersecting parts resolved into non-overlapping contours.
    public func normalized(eoFill: Bool = true) -> Path { booleanOp(Path(), UNION_SK_PATHOP, eoFill) }

    public func lineIntersection(_ other: Path, eoFill: Bool = false) -> Path { lineParts(of: other, inside: true, eoFill: eoFill) }
    public func lineSubtracting(_ other: Path, eoFill: Bool = false) -> Path { lineParts(of: other, inside: false, eoFill: eoFill) }

    private func booleanOp(_ other: Path, _ op: sk_pathop_t, _ eoFill: Bool) -> Path {
        withSkPath(evenOdd: eoFill) { a in
            other.withSkPath(evenOdd: eoFill) { b in
                guard let out = sk_path_new() else { return Path() }
                defer { sk_path_delete(out) }
                guard sk_pathop_op(a, b, op, out) else {
                    ShimDiagnostics.warn("A path boolean operation failed; the result is empty")
                    return Path()
                }
                return Path(skPath: out)
            }
        }
    }

    /// Flattens the outline into short pieces and keeps those whose midpoint is inside (or outside) `other`.
    private func lineParts(of other: Path, inside: Bool, eoFill: Bool) -> Path {
        var result = Path()
        var start = CGPoint.zero, current = CGPoint.zero
        var penDown = false
        func emit(_ points: [CGPoint]) {
            for (a, b) in zip(points, points.dropFirst()) {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if other.contains(mid, eoFill: eoFill) == inside {
                    if !penDown || result.currentPoint != a { result.move(to: a) }
                    result.addLine(to: b)
                    penDown = true
                } else {
                    penDown = false
                }
            }
        }
        func samples(_ point: (CGFloat) -> CGPoint, count: Int) -> [CGPoint] { (0...count).map { point(CGFloat($0) / CGFloat(count)) } }
        forEach { element in
            switch element {
            case .move(let p):
                start = p; current = p; penDown = false
            case .line(let p):
                emit(samples({ t in CGPoint(x: current.x + (p.x - current.x) * t, y: current.y + (p.y - current.y) * t) }, count: 32))
                current = p
            case .quadCurve(let p, let c):
                let p0 = current
                emit(samples({ t in
                    let u = 1 - t
                    return CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p.y)
                }, count: 32))
                current = p
            case .curve(let p, let c1, let c2):
                let p0 = current
                emit(samples({ t in
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p.x, y: a * p0.y + b * c1.y + c * c2.y + d * p.y)
                }, count: 32))
                current = p
            case .closeSubpath:
                let p0 = current
                emit(samples({ t in CGPoint(x: p0.x + (start.x - p0.x) * t, y: p0.y + (start.y - p0.y) * t) }, count: 32))
                current = start
            }
        }
        return result
    }
}

extension Shape {
    public func union<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape { _BooleanShape(a: self, b: other) { $0.union($1, eoFill: eoFill) } }
    public func intersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape { _BooleanShape(a: self, b: other) { $0.intersection($1, eoFill: eoFill) } }
    public func subtracting<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape { _BooleanShape(a: self, b: other) { $0.subtracting($1, eoFill: eoFill) } }
    public func symmetricDifference<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other) { $0.symmetricDifference($1, eoFill: eoFill) }
    }
    public func lineIntersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape { _BooleanShape(a: self, b: other) { $0.lineIntersection($1, eoFill: eoFill) } }
    public func lineSubtracting<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape { _BooleanShape(a: self, b: other) { $0.lineSubtracting($1, eoFill: eoFill) } }
}

struct _BooleanShape<A: Shape, B: Shape>: Shape {
    let a: A
    let b: B
    let op: @Sendable (Path, Path) -> Path
    nonisolated func path(in rect: CGRect) -> Path { op(a.path(in: rect), b.path(in: rect)) }
}
