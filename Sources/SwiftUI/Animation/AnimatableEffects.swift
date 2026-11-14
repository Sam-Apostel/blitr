// Drawing effects whose parameters a capture can interpolate: opacity, scale, rotation, blur, shadow.
// `Modifiers/Effects.swift` builds these modifiers through `EffectParams`, so a still render draws
// exactly what it drew before, and a capture can redraw a node with in-between parameters.

@MainActor
enum EffectParams {
    case opacity(Double)
    case scale(CGSize, UnitPoint)
    case rotation(Angle, UnitPoint)
    case blur(CGFloat)
    case shadow(RGBA, radius: CGFloat, x: CGFloat, y: CGFloat)

    /// Same kind of effect (interpolation only happens between two of a kind).
    func sameKind(_ o: EffectParams) -> Bool {
        switch (self, o) {
        case (.opacity, .opacity), (.scale, .scale), (.rotation, .rotation), (.blur, .blur), (.shadow, .shadow): return true
        default: return false
        }
    }

    func interpolated(to o: EffectParams, _ t: Double) -> EffectParams {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(t) }
        switch (self, o) {
        case (.opacity(let a), .opacity(let b)): return .opacity(mix(a, b))
        case (.scale(let a, _), .scale(let b, let anchor)):
            return .scale(CGSize(width: mix(a.width, b.width), height: mix(a.height, b.height)), anchor)
        case (.rotation(let a, _), .rotation(let b, let anchor)): return .rotation(.radians(mix(a.radians, b.radians)), anchor)
        case (.blur(let a), .blur(let b)): return .blur(mix(a, b))
        case (.shadow(let ca, let ra, let xa, let ya), .shadow(let cb, let rb, let xb, let yb)):
            return .shadow(ca.mixed(with: cb, t), radius: mix(ra, rb), x: mix(xa, xb), y: mix(ya, yb))
        default: return o
        }
    }

    func differs(from o: EffectParams) -> Bool {
        switch (self, o) {
        case (.opacity(let a), .opacity(let b)): return a != b
        case (.scale(let a, _), .scale(let b, _)): return a != b
        case (.rotation(let a, _), .rotation(let b, _)): return a.radians != b.radians
        case (.blur(let a), .blur(let b)): return a != b
        case (.shadow(let ca, let ra, let xa, let ya), .shadow(let cb, let rb, let xb, let yb)):
            return ca != cb || ra != rb || xa != xb || ya != yb
        default: return true
        }
    }

    /// The drawing of the effect: the code the modifiers in Effects.swift always used.
    var draw: (Painter, CGSize, () -> Void) -> Void {
        switch self {
        case .opacity(let opacity):
            return { p, _, draw in
                if opacity <= 0 { return }
                if opacity >= 1 { draw(); return }
                p.saveLayer(.init(opacity: opacity))
                draw()
                p.restore()
            }
        case .scale(let s, let anchor):
            return EffectParams.transform(anchor) { $0.scale(s.width, s.height) }
        case .rotation(let angle, let anchor):
            return EffectParams.transform(anchor) { $0.rotate(angle) }
        case .blur(let radius):
            return { p, _, draw in
                guard radius > 0 else { draw(); return }
                p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: radius, scale: p.scale)))
                draw()
                p.restore()
            }
        case .shadow(let rgba, let radius, let x, let y):
            return { p, _, draw in
                guard rgba.a > 0 else { draw(); return }
                p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: rgba, radius: radius, x: x, y: y, scale: p.scale)))
                draw()
                p.restore()
            }
        }
    }

    private static func transform(_ anchor: UnitPoint, _ apply: @escaping (Painter) -> Void) -> (Painter, CGSize, () -> Void) -> Void {
        { p, size, draw in
            let a = anchor.point(in: CGRect(origin: .zero, size: size))
            p.save()
            p.translate(a.x, a.y)
            apply(p)
            p.translate(-a.x, -a.y)
            draw()
            p.restore()
        }
    }
}

/// An `EffectNode` drawn from `EffectParams`; the parameters are recorded for a capture.
struct AnimatableEffectModifier: ViewModifier, NodeModifier {
    let params: (EnvironmentValues) -> EffectParams
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        let p = params(ctx.env)
        let node = EffectNode(child: child, effect: p.draw)
        if CaptureInfo.isRecording { CaptureInfo.of(node).effect = p }
        return node
    }
}

extension View {
    func animatableEffect(_ params: EffectParams) -> ModifiedContent<Self, AnimatableEffectModifier> {
        modifier(AnimatableEffectModifier { _ in params })
    }
    func animatableEffect(env params: @escaping (EnvironmentValues) -> EffectParams) -> ModifiedContent<Self, AnimatableEffectModifier> {
        modifier(AnimatableEffectModifier(params: params))
    }
}

extension RGBA {
    func mixed(with o: RGBA, _ t: Double) -> RGBA {
        // Premultiplied mixing, so fading to or from clear keeps the hue.
        let a = self.a + (o.a - self.a) * t
        guard a > 0.0001 else { return RGBA(o.r, o.g, o.b, 0) }
        func ch(_ x: Double, _ y: Double) -> Double { ((x * self.a) + ((y * o.a) - (x * self.a)) * t) / a }
        return RGBA(ch(r, o.r), ch(g, o.g), ch(b, o.b), a)
    }
}

// MARK: - Paints

extension _Paint {
    /// The paint `t` of the way to `o`: colors and gradients with the same number of stops interpolate;
    /// anything else switches at the end.
    func interpolated(to o: _Paint, _ t: Double) -> _Paint {
        _Paint(_Paint.mix(kind, o.kind, t) ?? (t < 1 ? kind : o.kind))
    }

    func differs(from o: _Paint) -> Bool { !_Paint.same(kind, o.kind) }

    private static func mixStops(_ a: [GradientStop], _ b: [GradientStop], _ t: Double) -> [GradientStop]? {
        guard a.count == b.count else { return nil }
        return zip(a, b).map { GradientStop(color: $0.color.mixed(with: $1.color, t), location: $0.location + ($1.location - $0.location) * CGFloat(t)) }
    }
    private static func mixPoint(_ a: UnitPoint, _ b: UnitPoint, _ t: Double) -> UnitPoint {
        UnitPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }

    private static func mix(_ a: Kind, _ b: Kind, _ t: Double) -> Kind? {
        switch (a, b) {
        case (.color(let x), .color(let y)): return .color(x.mixed(with: y, t))
        case (.opacity(let x, let ox), .opacity(let y, let oy)):
            return mix(x, y, t).map { .opacity($0, ox + (oy - ox) * t) }
        case (.opacity(let x, let ox), _): return mix(x, b, t).map { .opacity($0, ox + (1 - ox) * t) }
        case (_, .opacity(let y, let oy)): return mix(a, y, t).map { .opacity($0, 1 + (oy - 1) * t) }
        case (.linear(let s1, let a1, let e1), .linear(let s2, let a2, let e2)):
            return mixStops(s1, s2, t).map { .linear(stops: $0, start: mixPoint(a1, a2, t), end: mixPoint(e1, e2, t)) }
        case (.radial(let s1, let c1, let r1, let q1), .radial(let s2, let c2, let r2, let q2)):
            return mixStops(s1, s2, t).map { .radial(stops: $0, center: mixPoint(c1, c2, t), startRadius: r1 + (r2 - r1) * CGFloat(t), endRadius: q1 + (q2 - q1) * CGFloat(t)) }
        case (.angular(let s1, let c1, let a1, let e1), .angular(let s2, let c2, let a2, let e2)):
            return mixStops(s1, s2, t).map {
                .angular(stops: $0, center: mixPoint(c1, c2, t), start: .radians(a1.radians + (a2.radians - a1.radians) * t),
                         end: .radians(e1.radians + (e2.radians - e1.radians) * t))
            }
        case (.color(let x), .linear(let s, let st, let e)):
            return mixStops(s.map { GradientStop(color: x, location: $0.location) }, s, t).map { .linear(stops: $0, start: st, end: e) }
        case (.linear(let s, let st, let e), .color(let y)):
            return mixStops(s, s.map { GradientStop(color: y, location: $0.location) }, t).map { .linear(stops: $0, start: st, end: e) }
        default: return nil
        }
    }

    private static func same(_ a: Kind, _ b: Kind) -> Bool {
        switch (a, b) {
        case (.color(let x), .color(let y)): return x == y
        case (.opacity(let x, let ox), .opacity(let y, let oy)): return ox == oy && same(x, y)
        case (.linear(let s1, let a1, let e1), .linear(let s2, let a2, let e2)): return stopsEqual(s1, s2) && a1 == a2 && e1 == e2
        case (.radial(let s1, let c1, let r1, let q1), .radial(let s2, let c2, let r2, let q2)):
            return stopsEqual(s1, s2) && c1 == c2 && r1 == r2 && q1 == q2
        case (.elliptical(let s1, let c1, let r1, let q1), .elliptical(let s2, let c2, let r2, let q2)):
            return stopsEqual(s1, s2) && c1 == c2 && r1 == r2 && q1 == q2
        case (.angular(let s1, let c1, let a1, let e1), .angular(let s2, let c2, let a2, let e2)):
            return stopsEqual(s1, s2) && c1 == c2 && a1 == a2 && e1 == e2
        case (.material(let m1, let k1), .material(let m2, let k2)): return m1 == m2 && k1 == k2
        default: return false
        }
    }
    private static func stopsEqual(_ a: [GradientStop], _ b: [GradientStop]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.color == $1.color && $0.location == $1.location }
    }
}

// MARK: - Shapes

extension RoundedRectangle {
    public var animatableData: CGSize.AnimatableData {
        get { cornerSize.animatableData }
        set { cornerSize.animatableData = newValue }
    }
}

extension UnevenRoundedRectangle {
    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(cornerRadii.topLeading, cornerRadii.bottomLeading),
                           AnimatablePair(cornerRadii.bottomTrailing, cornerRadii.topTrailing))
        }
        set {
            cornerRadii = RectangleCornerRadii(topLeading: newValue.first.first, bottomLeading: newValue.first.second,
                                               bottomTrailing: newValue.second.first, topTrailing: newValue.second.second)
        }
    }
}

/// `Shape.trim(from:to:)`: the trimmed part animates.
public struct _TrimmedShape<Content: Shape>: Shape {
    var shape: Content
    var from: CGFloat
    var to: CGFloat
    public nonisolated func path(in rect: CGRect) -> Path { shape.path(in: rect).trimmedPath(from: from, to: to) }
    public nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }
    public var animatableData: AnimatablePair<Content.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(from, to)) }
        set {
            shape.animatableData = newValue.first
            from = newValue.second.first
            to = newValue.second.second
        }
    }
}
