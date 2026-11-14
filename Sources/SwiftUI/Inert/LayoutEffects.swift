// Visible APIs that depend on layout results: containerRelativeFrame and visualEffect.

// MARK: - containerRelativeFrame

/// Containers (a ScrollView, say) can publish the size they offer by writing this value; when it is
/// absent the render container (the screen minus bars and safe areas) is used.
enum ContainerRelativeSizeKey: EnvironmentKey { static let defaultValue: CGSize? = nil }

extension EnvironmentValues {
    var containerRelativeSize: CGSize? {
        get { self[ContainerRelativeSizeKey.self] }
        set { self[ContainerRelativeSizeKey.self] = newValue }
    }
}

extension RenderConfiguration {
    /// Size of the area the root view is laid out in.
    var containerSize: CGSize {
        let full = CGSize(width: width ?? device.size.width, height: height ?? device.size.height)
        guard layout == .device, width == nil, height == nil else { return full }
        let inset = device.safeArea
        return CGSize(width: max(0, full.width - inset.leading - inset.trailing), height: max(0, full.height - inset.top - inset.bottom))
    }
}

struct ContainerRelativeFrameModifier: ViewModifier, NodeModifier {
    let axes: Axis.Set
    let alignment: Alignment
    let length: (CGFloat, Axis) -> CGFloat
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        let container = ctx.env.containerRelativeSize ?? ctx.runtime.config.containerSize
        let width = axes.contains(.horizontal) ? length(container.width, .horizontal) : nil
        let height = axes.contains(.vertical) ? length(container.height, .vertical) : nil
        return FrameNode(child: child, width: width, height: height, alignment: alignment)
    }
}

extension View {
    public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
        modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment) { length, _ in length })
    }
    public func containerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat,
                                       alignment: Alignment = .center) -> some View {
        modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment) { length, _ in
            let count = CGFloat(max(1, count)), span = CGFloat(max(1, span))
            return max(0, (length - spacing * (count - 1)) / count * span + spacing * (span - 1))
        })
    }
    public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center,
                                       _ length: @escaping (CGFloat, Axis) -> CGFloat) -> some View {
        modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment, length: length))
    }

    public func geometryGroup() -> some View { self }
}

// MARK: - visualEffect

public struct _VisualOp: Sendable {
    enum Kind: Sendable {
        case offset(CGSize)
        case scale(CGSize, UnitPoint)
        case rotation(Angle, UnitPoint)
        case opacity(Double)
        case blur(CGFloat)
        case colorMatrix([Float])
    }
    let kind: Kind
}

public protocol VisualEffect: Animatable, Sendable {
    var _visualOps: [_VisualOp] { get }
}

public struct EmptyVisualEffect: VisualEffect {
    public init() {}
    public var _visualOps: [_VisualOp] { [] }
}

public struct _AppliedVisualEffect: VisualEffect {
    public var _visualOps: [_VisualOp]
}

extension VisualEffect {
    private func adding(_ kind: _VisualOp.Kind) -> _AppliedVisualEffect {
        _AppliedVisualEffect(_visualOps: _visualOps + [_VisualOp(kind: kind)])
    }
    public func offset(_ offset: CGSize) -> some VisualEffect { adding(.offset(offset)) }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some VisualEffect { adding(.offset(CGSize(width: x, height: y))) }
    public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some VisualEffect { adding(.scale(scale, anchor)) }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some VisualEffect { adding(.scale(CGSize(width: s, height: s), anchor)) }
    public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some VisualEffect {
        adding(.scale(CGSize(width: x, height: y), anchor))
    }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some VisualEffect { adding(.rotation(angle, anchor)) }
    public func opacity(_ opacity: Double) -> some VisualEffect { adding(.opacity(opacity)) }
    public func blur(radius: CGFloat, opaque: Bool = false) -> some VisualEffect { adding(.blur(radius)) }
    public func saturation(_ amount: Double) -> some VisualEffect { adding(.colorMatrix(Painter.saturationMatrix(Float(amount)))) }
    public func grayscale(_ amount: Double) -> some VisualEffect {
        adding(.colorMatrix(Painter.saturationMatrix(Float(1 - max(0, min(1, amount))))))
    }
    public func brightness(_ amount: Double) -> some VisualEffect {
        let b = Float(amount)
        return adding(.colorMatrix([1, 0, 0, 0, b, 0, 1, 0, 0, b, 0, 0, 1, 0, b, 0, 0, 0, 1, 0]))
    }
    public func contrast(_ amount: Double) -> some VisualEffect {
        let c = Float(amount), o = (1 - c) / 2
        return adding(.colorMatrix([c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0]))
    }
    public func colorInvert() -> some VisualEffect {
        adding(.colorMatrix([-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0]))
    }
    public func hueRotation(_ angle: Angle) -> some VisualEffect {
        let c = Float(cos(angle.radians)), s = Float(sin(angle.radians))
        let (lr, lg, lb): (Float, Float, Float) = (0.213, 0.715, 0.072)
        return adding(.colorMatrix([
            lr + c * (1 - lr) + s * (-lr), lg + c * (-lg) + s * (-lg), lb + c * (-lb) + s * (1 - lb), 0, 0,
            lr + c * (-lr) + s * 0.143, lg + c * (1 - lg) + s * 0.140, lb + c * (-lb) + s * (-0.283), 0, 0,
            lr + c * (-lr) + s * (-(1 - lr)), lg + c * (-lg) + s * lg, lb + c * (1 - lb) + s * lb, 0, 0,
            0, 0, 0, 1, 0]))
    }
}

/// Runs the effect closure at layout time (it needs the view's geometry) and draws the result.
final class VisualEffectNode: WrapperNode {
    let effect: (GeometryProxy) -> [_VisualOp]
    let runtime: Runtime
    private var ops: [_VisualOp] = []
    init(child: Node, runtime: Runtime, effect: @escaping (GeometryProxy) -> [_VisualOp]) {
        self.effect = effect
        self.runtime = runtime
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let bleed = ctx.safeAreaBleed(for: CGRect(origin: ctx.origin, size: size), edges: .all)
        ops = effect(GeometryProxy(size: size, safeAreaInsets: bleed, absoluteOrigin: ctx.origin,
                                   namedSpaces: runtime.namedCoordinateSpaces))
        super.layout(size: size, ctx)
    }
    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        var restores = 1
        var hidden = false
        p.save()
        func about(_ anchor: UnitPoint, _ apply: () -> Void) {
            let a = anchor.point(in: bounds)
            p.translate(a.x, a.y)
            apply()
            p.translate(-a.x, -a.y)
        }
        for op in ops {
            switch op.kind {
            case .offset(let o): p.translate(o.width, o.height)
            case .scale(let s, let anchor): about(anchor) { p.scale(s.width, s.height) }
            case .rotation(let angle, let anchor): about(anchor) { p.rotate(angle) }
            case .opacity(let o):
                if o <= 0 { hidden = true } else if o < 1 { p.saveLayer(.init(opacity: o)); restores += 1 }
            case .blur(let r):
                if r > 0 { p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: r, scale: p.scale))); restores += 1 }
            case .colorMatrix(let m):
                p.saveLayer(.init(colorFilter: Painter.colorMatrixFilter(m))); restores += 1
            }
        }
        if !hidden { drawChildren(p) }
        for _ in 0..<restores { p.restore() }
    }
}

struct VisualEffectModifier: ViewModifier, NodeModifier {
    let effect: (GeometryProxy) -> [_VisualOp]
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        VisualEffectNode(child: child, runtime: ctx.runtime, effect: effect)
    }
}

extension View {
    public func visualEffect<E: VisualEffect>(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> E) -> some View {
        modifier(VisualEffectModifier { proxy in effect(EmptyVisualEffect(), proxy)._visualOps })
    }
}
