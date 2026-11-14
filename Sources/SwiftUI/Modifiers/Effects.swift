internal import CSkia

// Drawing effects: opacity, clipping, shadows, blur, transforms, color adjustments,
// and the style-based background/overlay/border modifiers.

/// Wraps a child and draws it through a transform/layer described by a closure.
final class EffectNode: WrapperNode {
    let effect: (Painter, CGSize, () -> Void) -> Void
    init(child: Node, effect: @escaping (Painter, CGSize, () -> Void) -> Void) {
        self.effect = effect
        super.init(child: child)
    }
    override func drawContent(_ p: Painter) {
        effect(p, frame.size) { self.drawChildren(p) }
    }
}

struct EffectModifier: ViewModifier, NodeModifier {
    let effect: (EnvironmentValues) -> (Painter, CGSize, () -> Void) -> Void
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { EffectNode(child: child, effect: effect(ctx.env)) }
}

extension View {
    func effect(_ body: @escaping (Painter, CGSize, () -> Void) -> Void) -> ModifiedContent<Self, EffectModifier> {
        modifier(EffectModifier { _ in body })
    }
    func effect(env body: @escaping (EnvironmentValues) -> (Painter, CGSize, () -> Void) -> Void) -> ModifiedContent<Self, EffectModifier> {
        modifier(EffectModifier(effect: body))
    }

    /// Draws the content through an offscreen layer with the given options.
    func layer(_ options: @escaping (Painter, CGSize) -> Painter.LayerOptions) -> ModifiedContent<Self, EffectModifier> {
        effect { p, size, draw in
            p.saveLayer(options(p, size))
            draw()
            p.restore()
        }
    }

    // MARK: Opacity / visibility

    public func opacity(_ opacity: Double) -> some View { animatableEffect(.opacity(opacity)) }
    public func hidden() -> some View { effect { _, _, _ in } }
    public func compositingGroup() -> some View { layer { _, _ in .init() } }
    public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View { layer { _, _ in .init() } }
    public func blendMode(_ blendMode: BlendMode) -> some View { layer { _, _ in .init(blendMode: blendMode) } }

    // MARK: Clipping

    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        effect { p, size, draw in
            p.save()
            p.clip(shape.path(in: CGRect(origin: .zero, size: size)), evenOdd: style.isEOFilled)
            draw()
            p.restore()
        }
    }
    public func clipped(antialiased: Bool = false) -> some View { clipShape(Rectangle()) }
    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
    }
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { self }
    public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View { self }
    public func containerShape<S: InsettableShape>(_ shape: S) -> some View { self }

    public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        modifier(MaskModifier(mask: mask(), alignment: alignment))
    }
    @_disfavoredOverload
    public func mask<Mask: View>(_ mask: Mask) -> some View { modifier(MaskModifier(mask: mask, alignment: .center)) }

    // MARK: Shadow / blur

    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        animatableEffect(env: { env in .shadow(color.rgba(in: env), radius: radius, x: x, y: y) })
    }
    public func blur(radius: CGFloat, opaque: Bool = false) -> some View { animatableEffect(.blur(radius)) }

    // MARK: Geometry effects (do not affect layout)

    func transformEffect(anchor: UnitPoint, _ apply: @escaping (Painter) -> Void) -> ModifiedContent<Self, EffectModifier> {
        effect { p, size, draw in
            let a = anchor.point(in: CGRect(origin: .zero, size: size))
            p.save()
            p.translate(a.x, a.y)
            apply(p)
            p.translate(-a.x, -a.y)
            draw()
            p.restore()
        }
    }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        animatableEffect(.rotation(angle, anchor))
    }
    public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        animatableEffect(.scale(scale, anchor))
    }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        animatableEffect(.scale(CGSize(width: s, height: s), anchor))
    }
    public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        animatableEffect(.scale(CGSize(width: x, height: y), anchor))
    }
    public func transformEffect(_ transform: CGAffineTransform) -> some View {
        effect { p, _, draw in
            p.save()
            p.concat(transform)
            draw()
            p.restore()
        }
    }
    public func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center,
                                 anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some View {
        transformEffect(anchor: anchor) { p in
            // Rodrigues rotation followed by a simple perspective divide (m34 = -perspective / 1000, like CATransform3D).
            let len = max(0.0001, sqrt(Double(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)))
            let (x, y, z) = (Float(Double(axis.x) / len), Float(Double(axis.y) / len), Float(Double(axis.z) / len))
            let c = Float(cos(angle.radians)), s = Float(sin(angle.radians)), t = 1 - c
            let persp = Float(-perspective / 1000)
            var m: [Float] = [t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0,
                              t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0,
                              t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0,
                              0, 0, 0, 1]
            // Row 3 = perspective * row 2, so w = 1 + persp * z'.
            m[12] = persp * m[8]; m[13] = persp * m[9]; m[14] = persp * m[10]
            p.concat(matrix44: m)
        }
    }

    // MARK: Color adjustments

    func colorMatrix(_ matrix: [Float]) -> ModifiedContent<Self, EffectModifier> {
        layer { _, _ in .init(colorFilter: Painter.colorMatrixFilter(matrix)) }
    }
    public func saturation(_ amount: Double) -> some View { colorMatrix(Painter.saturationMatrix(Float(amount))) }
    public func grayscale(_ amount: Double) -> some View { colorMatrix(Painter.saturationMatrix(Float(1 - max(0, min(1, amount))))) }
    public func brightness(_ amount: Double) -> some View {
        let b = Float(amount)
        return colorMatrix([1, 0, 0, 0, b, 0, 1, 0, 0, b, 0, 0, 1, 0, b, 0, 0, 0, 1, 0])
    }
    public func contrast(_ amount: Double) -> some View {
        let c = Float(amount), o = (1 - c) / 2
        return colorMatrix([c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0])
    }
    public func colorInvert() -> some View {
        colorMatrix([-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0])
    }
    public func colorMultiply(_ color: Color) -> some View {
        effect(env: { env in
            let c = color.rgba(in: env)
            let m: [Float] = [Float(c.r), 0, 0, 0, 0, 0, Float(c.g), 0, 0, 0, 0, 0, Float(c.b), 0, 0, 0, 0, 0, Float(c.a), 0]
            return { p, _, draw in
                p.saveLayer(.init(colorFilter: Painter.colorMatrixFilter(m)))
                draw()
                p.restore()
            }
        })
    }
    public func hueRotation(_ angle: Angle) -> some View {
        let c = Float(cos(angle.radians)), s = Float(sin(angle.radians))
        let (lr, lg, lb): (Float, Float, Float) = (0.213, 0.715, 0.072)
        return colorMatrix([
            lr + c * (1 - lr) + s * (-lr), lg + c * (-lg) + s * (-lg), lb + c * (-lb) + s * (1 - lb), 0, 0,
            lr + c * (-lr) + s * 0.143, lg + c * (1 - lg) + s * 0.140, lb + c * (-lb) + s * (-0.283), 0, 0,
            lr + c * (-lr) + s * (-(1 - lr)), lg + c * (-lg) + s * lg, lb + c * (1 - lb) + s * lb, 0, 0,
            0, 0, 0, 1, 0])
    }
    public func luminanceToAlpha() -> some View {
        colorMatrix([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0])
    }
}

public enum ColorRenderingMode: Sendable { case nonLinear, linear, extendedLinear }
public struct ContentShapeKinds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let interaction = ContentShapeKinds(rawValue: 1)
    public static let dragPreview = ContentShapeKinds(rawValue: 2)
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 4)
    public static let hoverEffect = ContentShapeKinds(rawValue: 8)
    public static let accessibility = ContentShapeKinds(rawValue: 16)
}

// MARK: - Mask

final class MaskNode: Node {
    let alignment: Alignment
    init(content: Node, mask: Node, alignment: Alignment) {
        self.alignment = alignment
        super.init(children: [content, mask])
        traits = content.traits
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { children[0].sizeThatFits(proposal) }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        children[0].place(at: .zero, size: size, ctx)
        let m = children[1].sizeThatFits(ProposedViewSize(size))
        placeAligned(children[1], childSize: m, in: size, alignment: alignment, ctx)
    }
    override func spacing(_ edge: Edge) -> CGFloat? { children[0].spacing(edge) }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? { children[0].explicitAlignment(key, size: size) }
    override func drawContent(_ p: Painter) {
        // Content in a layer, then the mask composited with destination-in (keeps content where the mask is opaque).
        p.saveLayer(.init())
        children[0].draw(p)
        p.saveLayer(.init(rawBlend: DSTIN_SK_BLENDMODE))
        children[1].draw(p)
        p.restore()
        p.restore()
    }
}

struct MaskModifier<Mask: View>: ViewModifier, PrimitiveModifier {
    let mask: Mask
    let alignment: Alignment
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, node) in content.nodes(ctx).enumerated() {
            let maskNode = resolveSingle(mask, ctx.child("mask\(i)").with { $0.stackAxis = nil })
            out.append(MaskNode(content: node, mask: maskNode, alignment: alignment))
        }
    }
}

// MARK: - Style backgrounds, overlays, borders

/// Draws a style behind (or in front of) the child, optionally inside a shape. Without a shape the
/// fill bleeds into the safe area on the edges it touches, as `.background(Color)` does on iOS.
final class StyleLayerNode: WrapperNode {
    let paint: _Paint
    let shape: ((CGRect) -> Path)?
    let inFront: Bool
    let ignoredEdges: Edge.Set
    private var bleed = EdgeInsets()

    init(child: Node, paint: _Paint, shape: ((CGRect) -> Path)?, inFront: Bool, ignoredEdges: Edge.Set) {
        self.paint = paint
        self.shape = shape
        self.inFront = inFront
        self.ignoredEdges = ignoredEdges
        super.init(child: child)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        super.layout(size: size, ctx)
        bleed = shape == nil ? ctx.safeAreaBleed(for: CGRect(origin: ctx.origin, size: size), edges: ignoredEdges) : EdgeInsets()
    }
    override func drawContent(_ p: Painter) {
        if inFront { drawChildren(p) }
        let bounds = CGRect(origin: .zero, size: frame.size)
        if let shape {
            p.fill(shape(bounds), with: paint, in: bounds)
        } else {
            let rect = bounds.outset(by: bleed)
            p.fill(Path(rect), with: paint, in: rect)
        }
        if !inFront { drawChildren(p) }
    }
}

extension PlaceContext {
    /// How far a rect touching the safe-area boundary extends to reach the container edge.
    func safeAreaBleed(for rect: CGRect, edges: Edge.Set) -> EdgeInsets {
        let e: CGFloat = 0.5
        var insets = EdgeInsets()
        if edges.contains(.top), rect.minY <= safeRect.minY + e { insets.top = max(0, rect.minY - container.minY) }
        if edges.contains(.bottom), rect.maxY >= safeRect.maxY - e { insets.bottom = max(0, container.maxY - rect.maxY) }
        if edges.contains(.leading), rect.minX <= safeRect.minX + e { insets.leading = max(0, rect.minX - container.minX) }
        if edges.contains(.trailing), rect.maxX >= safeRect.maxX - e { insets.trailing = max(0, container.maxX - rect.maxX) }
        return insets
    }
}

struct StyleLayerModifier<S: ShapeStyle>: ViewModifier, NodeModifier {
    let style: S
    let shape: ((CGRect) -> Path)?
    let inFront: Bool
    var ignoredEdges: Edge.Set = []
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        StyleLayerNode(child: child, paint: style._paint(in: ctx.env), shape: shape, inFront: inFront, ignoredEdges: ignoredEdges)
    }
}

extension View {
    public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(StyleLayerModifier(style: style, shape: nil, inFront: false, ignoredEdges: edges))
    }
    public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(StyleLayerModifier(style: BackgroundStyle(), shape: nil, inFront: false, ignoredEdges: edges))
    }
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(StyleLayerModifier(style: style, shape: { shape.path(in: $0) }, inFront: false))
    }
    public func background<T: Shape>(in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(StyleLayerModifier(style: BackgroundStyle(), shape: { shape.path(in: $0) }, inFront: false))
    }
    public func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(StyleLayerModifier(style: style, shape: nil, inFront: true, ignoredEdges: edges))
    }
    public func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(StyleLayerModifier(style: style, shape: { shape.path(in: $0) }, inFront: true))
    }
    public func border<S: ShapeStyle>(_ content: S, width: CGFloat = 1) -> some View {
        overlay(Rectangle().strokeBorder(content, lineWidth: width))
    }
}

// MARK: - Environment used by drawing

enum DisplayScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 3 }
enum PixelLengthKey: EnvironmentKey { static let defaultValue: CGFloat = 1.0 / 3 }

extension EnvironmentValues {
    public var displayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue; self[PixelLengthKey.self] = 1 / newValue }
    }
    public var pixelLength: CGFloat { self[PixelLengthKey.self] }
}
