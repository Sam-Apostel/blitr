// GeometryEffect is the one animation-flavoured API with a visible result in a static frame:
// the transform returned by `effectValue(size:)` is applied once, to the settled content.

public struct ProjectionTransform: Equatable, Sendable {
    public var m11: CGFloat = 1.0, m12: CGFloat = 0.0, m13: CGFloat = 0.0
    public var m21: CGFloat = 0.0, m22: CGFloat = 1.0, m23: CGFloat = 0.0
    public var m31: CGFloat = 0.0, m32: CGFloat = 0.0, m33: CGFloat = 1.0

    public init() {}
    public init(_ m: CGAffineTransform) {
        m11 = m.a; m12 = m.b
        m21 = m.c; m22 = m.d
        m31 = m.tx; m32 = m.ty
    }

    public var isIdentity: Bool { self == ProjectionTransform() }
    public var isAffine: Bool { m13 == 0 && m23 == 0 && m33 == 1 }

    public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
        var r = ProjectionTransform()
        r.m11 = m11 * rhs.m11 + m12 * rhs.m21 + m13 * rhs.m31
        r.m12 = m11 * rhs.m12 + m12 * rhs.m22 + m13 * rhs.m32
        r.m13 = m11 * rhs.m13 + m12 * rhs.m23 + m13 * rhs.m33
        r.m21 = m21 * rhs.m11 + m22 * rhs.m21 + m23 * rhs.m31
        r.m22 = m21 * rhs.m12 + m22 * rhs.m22 + m23 * rhs.m32
        r.m23 = m21 * rhs.m13 + m22 * rhs.m23 + m23 * rhs.m33
        r.m31 = m31 * rhs.m11 + m32 * rhs.m21 + m33 * rhs.m31
        r.m32 = m31 * rhs.m12 + m32 * rhs.m22 + m33 * rhs.m32
        r.m33 = m31 * rhs.m13 + m32 * rhs.m23 + m33 * rhs.m33
        return r
    }

    public func inverted() -> ProjectionTransform {
        let det = m11 * (m22 * m33 - m23 * m32) - m12 * (m21 * m33 - m23 * m31) + m13 * (m21 * m32 - m22 * m31)
        guard det != 0 else { return self }
        var r = ProjectionTransform()
        r.m11 = (m22 * m33 - m23 * m32) / det
        r.m12 = (m13 * m32 - m12 * m33) / det
        r.m13 = (m12 * m23 - m13 * m22) / det
        r.m21 = (m23 * m31 - m21 * m33) / det
        r.m22 = (m11 * m33 - m13 * m31) / det
        r.m23 = (m13 * m21 - m11 * m23) / det
        r.m31 = (m21 * m32 - m22 * m31) / det
        r.m32 = (m12 * m31 - m11 * m32) / det
        r.m33 = (m11 * m22 - m12 * m21) / det
        return r
    }

    /// Row-major 4x4 for `Painter.concat(matrix44:)`, which treats points as column vectors;
    /// this type follows CoreGraphics (row vectors, translation in the third row), hence the transpose.
    var matrix44: [Float] {
        [Float(m11), Float(m21), 0, Float(m31),
         Float(m12), Float(m22), 0, Float(m32),
         0, 0, 1, 0,
         Float(m13), Float(m23), 0, Float(m33)]
    }
}

public protocol GeometryEffect: Animatable, ViewModifier {
    func effectValue(size: CGSize) -> ProjectionTransform
}

extension GeometryEffect {
    @MainActor
    public func body(content: Content) -> some View {
        content.effect { painter, size, draw in
            let transform = self.effectValue(size: size)
            painter.save()
            painter.concat(matrix44: transform.matrix44)
            draw()
            painter.restore()
        }
    }

    public func ignoredByLayout() -> _IgnoredByLayoutEffect<Self> { _IgnoredByLayoutEffect(base: self) }
}

public struct _IgnoredByLayoutEffect<Base: GeometryEffect>: GeometryEffect {
    var base: Base
    public init(base: Base) { self.base = base }
    public var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }
    public func effectValue(size: CGSize) -> ProjectionTransform { base.effectValue(size: size) }
}
