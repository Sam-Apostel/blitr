internal import CSkia

// Canvas and GraphicsContext: immediate-mode drawing inside a view.
//
// A GraphicsContext is a value (state: transform, clips, opacity, blend mode, filters) in front of the
// shared Painter. Every drawing operation brings the Painter to the context's state, draws, and restores,
// so contexts can be copied freely (`drawLayer`) without leaking state.

public struct GraphicsContext: @unchecked Sendable {
    let painter: Painter
    let canvasSize: CGSize
    let symbols: [AnyHashable: Node]

    public var environment: EnvironmentValues
    public var opacity: Double = 1
    public var blendMode: BlendMode = .normal
    public var transform: CGAffineTransform = .identity

    /// Clip paths in canvas coordinates.
    private var clips: [(path: Path, evenOdd: Bool)] = []
    private var filters: [Filter] = []
    /// What the painter already has applied (non-identity inside `drawLayer`).
    private var appliedTransform: CGAffineTransform = .identity
    private var appliedClips = 0

    init(painter: Painter, size: CGSize, environment: EnvironmentValues, symbols: [AnyHashable: Node]) {
        self.painter = painter
        self.canvasSize = size
        self.environment = environment
        self.symbols = symbols
    }

    // MARK: Types

    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let `repeat` = GradientOptions(rawValue: 1)
        public static let mirror = GradientOptions(rawValue: 2)
        public static let linearColor = GradientOptions(rawValue: 4)
    }
    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let linearColor = FilterOptions(rawValue: 1)
    }
    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let opaque = BlurOptions(rawValue: 1)
        public static let dithersResult = BlurOptions(rawValue: 2)
    }
    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let shadowAbove = ShadowOptions(rawValue: 1)
        public static let shadowOnly = ShadowOptions(rawValue: 2)
        public static let invertsAlpha = ShadowOptions(rawValue: 4)
        public static let disablesGroup = ShadowOptions(rawValue: 8)
    }
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let inverse = ClipOptions(rawValue: 1)
    }

    /// How a path is painted. Gradient points are in the context's coordinate space.
    public struct Shading: Sendable {
        let make: @Sendable (EnvironmentValues) -> _Paint
        /// Absolute shadings use canvas coordinates; style shadings are relative to the painted path.
        let isAbsolute: Bool

        public static func color(_ color: Color) -> Shading {
            Shading(make: { _Paint.color(color.rgba(in: $0)) }, isAbsolute: false)
        }
        public static func color(red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            Shading(make: { _ in _Paint.color(RGBA(red, green, blue, opacity)) }, isAbsolute: false)
        }
        public static func color(white: Double, opacity: Double = 1) -> Shading {
            Shading(make: { _ in _Paint.color(RGBA(white, white, white, opacity)) }, isAbsolute: false)
        }
        public static func style<S: ShapeStyle>(_ style: S) -> Shading {
            Shading(make: { style._paint(in: $0) }, isAbsolute: false)
        }
        public static var foreground: Shading { .style(ForegroundStyle()) }
        public static var backgroundStyle: Shading { .style(BackgroundStyle()) }

        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint,
                                          options: GradientOptions = GradientOptions()) -> Shading {
            Shading(make: { env in
                _Paint(.linear(stops: gradient.resolved(env), start: UnitPoint(x: startPoint.x, y: startPoint.y),
                               end: UnitPoint(x: endPoint.x, y: endPoint.y)))
            }, isAbsolute: true)
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat,
                                          options: GradientOptions = GradientOptions()) -> Shading {
            Shading(make: { env in
                _Paint(.radial(stops: gradient.resolved(env), center: UnitPoint(x: center.x, y: center.y),
                               startRadius: startRadius, endRadius: endRadius))
            }, isAbsolute: true)
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = .zero,
                                         options: GradientOptions = GradientOptions()) -> Shading {
            Shading(make: { env in
                _Paint(.angular(stops: gradient.resolved(env), center: UnitPoint(x: center.x, y: center.y),
                                start: angle, end: angle + .degrees(360)))
            }, isAbsolute: true)
        }
    }

    /// A filter applied to everything drawn after `addFilter`.
    public struct Filter: Sendable {
        let make: @Sendable (EnvironmentValues, CGFloat) -> Painter.LayerOptions

        public static func blur(radius: CGFloat, options: BlurOptions = BlurOptions()) -> Filter {
            Filter { _, scale in .init(imageFilter: Painter.blurFilter(radius: radius, scale: scale)) }
        }
        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0,
                                  y: CGFloat = 0, blendMode: BlendMode = .normal, options: ShadowOptions = ShadowOptions()) -> Filter {
            Filter { env, scale in
                .init(imageFilter: Painter.shadowFilter(color: color.rgba(in: env), radius: radius, x: x, y: y, scale: scale))
            }
        }
        static func matrix(_ m: [Float]) -> Filter { Filter { _, _ in .init(colorFilter: Painter.colorMatrixFilter(m)) } }

        public static func saturation(_ amount: Double) -> Filter { matrix(Painter.saturationMatrix(Float(amount))) }
        public static func grayscale(_ amount: Double) -> Filter { matrix(Painter.saturationMatrix(Float(1 - amount))) }
        public static func brightness(_ amount: Double) -> Filter {
            let b = Float(amount)
            return matrix([1, 0, 0, 0, b, 0, 1, 0, 0, b, 0, 0, 1, 0, b, 0, 0, 0, 1, 0])
        }
        public static func contrast(_ amount: Double) -> Filter {
            let c = Float(amount), t = (1 - c) / 2
            return matrix([c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0])
        }
        public static func colorInvert(_ amount: Double = 1) -> Filter {
            let a = Float(amount), d = 1 - 2 * a
            return matrix([d, 0, 0, 0, a, 0, d, 0, 0, a, 0, 0, d, 0, a, 0, 0, 0, 1, 0])
        }
        public static func colorMultiply(_ color: Color) -> Filter {
            Filter { env, _ in
                let c = color.rgba(in: env)
                let m: [Float] = [Float(c.r), 0, 0, 0, 0, 0, Float(c.g), 0, 0, 0, 0, 0, Float(c.b), 0, 0, 0, 0, 0, Float(c.a), 0]
                return .init(colorFilter: Painter.colorMatrixFilter(m))
            }
        }
        public static func hueRotation(_ angle: Angle) -> Filter {
            let c = Float(cos(angle.radians)), s = Float(sin(angle.radians))
            return matrix([0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
                           0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
                           0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
                           0, 0, 0, 1, 0])
        }
        public static var luminanceToAlpha: Filter {
            matrix([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0])
        }
    }

    // MARK: Resolved content

    public struct ResolvedText: @unchecked Sendable {
        let runs: [TextRun]
        let options: TextLayoutOptions
        public var shading: Shading

        @MainActor fileprivate func layout(width: CGFloat?) -> TextLayout { TextLayout(runs: runs, width: width, options: options) }

        public func measure(in size: CGSize) -> CGSize {
            MainActor.assumeIsolated { layout(width: size.width.isFinite ? size.width : nil).size }
        }
        public func firstBaseline(in size: CGSize) -> CGFloat {
            MainActor.assumeIsolated { layout(width: size.width.isFinite ? size.width : nil).firstBaseline }
        }
        public func lastBaseline(in size: CGSize) -> CGFloat {
            MainActor.assumeIsolated { layout(width: size.width.isFinite ? size.width : nil).lastBaseline }
        }
    }

    public struct ResolvedImage: @unchecked Sendable {
        let content: ImageContent
        public var shading: Shading?
        public var size: CGSize { content.naturalSize }
        public var baseline: CGFloat { 0 }
        public var shadingStyle: Shading? { shading }
    }

    public struct ResolvedSymbol: @unchecked Sendable {
        let node: Node
        public var size: CGSize { MainActor.assumeIsolated { node.frame.size } }
    }

    // MARK: Painting state

    /// Brings the painter to this context's state, returning how many `restore()`s undo it.
    @MainActor private func begin(opacityAndBlend: Bool = true) -> Int {
        var saves = 1
        painter.save()
        let inverse = appliedTransform.inverted()
        for clip in clips[min(appliedClips, clips.count)...] {
            painter.clip(clip.path.applying(inverse), evenOdd: clip.evenOdd)
        }
        let delta = transform.concatenating(inverse)
        if !delta.isIdentity { painter.concat(delta) }
        if opacityAndBlend, opacity < 1 || blendMode != .normal {
            painter.saveLayer(.init(opacity: opacity, blendMode: blendMode))
            saves += 1
        }
        // The last filter added wraps the earlier ones.
        for filter in filters {
            painter.saveLayer(filter.make(environment, painter.scale))
            saves += 1
        }
        return saves
    }

    @MainActor private func end(_ saves: Int) { for _ in 0..<saves { painter.restore() } }

    private func paint(_ shading: Shading, bounds: CGRect) -> (_Paint, CGRect) {
        let paint = shading.make(environment)
        return (paint, shading.isAbsolute ? CGRect(x: 0, y: 0, width: 1, height: 1) : bounds)
    }

    // MARK: Fill / stroke

    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        MainActor.assumeIsolated {
            let (paint, bounds) = self.paint(shading, bounds: path.boundingRect)
            let n = begin()
            painter.fill(path, with: paint, in: bounds, style: style)
            end(n)
        }
    }
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        MainActor.assumeIsolated {
            let (paint, bounds) = self.paint(shading, bounds: path.boundingRect)
            let n = begin()
            painter.stroke(path, with: paint, style: style, in: bounds)
            end(n)
        }
    }
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    // MARK: Text

    public func resolve(_ text: Text) -> ResolvedText {
        MainActor.assumeIsolated {
            var options = TextLayoutOptions()
            options.lineLimit = environment.lineLimit
            options.alignment = environment.multilineTextAlignment
            options.truncation = environment.truncationMode
            options.lineSpacing = environment.lineSpacing
            options.minimumScaleFactor = environment.minimumScaleFactor
            options.scale = environment.displayScale
            let runs = text.runs(in: environment)
            return ResolvedText(runs: runs, options: options, shading: .foreground)
        }
    }

    private func drawText(_ text: ResolvedText, rect: CGRect?, point: CGPoint, anchor: UnitPoint) {
        MainActor.assumeIsolated {
            let layout = text.layout(width: rect?.width)
            let size = layout.size
            let origin = rect?.origin ?? CGPoint(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y)
            let bounds = CGRect(origin: .zero, size: rect?.size ?? size)
            let n = begin()
            painter.translate(origin.x, origin.y)
            layout.draw(painter, in: bounds)
            end(n)
        }
    }

    public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        drawText(text, rect: nil, point: point, anchor: anchor)
    }
    public func draw(_ text: ResolvedText, in rect: CGRect) { drawText(text, rect: rect, point: .zero, anchor: .topLeading) }
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) { draw(resolve(text), at: point, anchor: anchor) }
    public func draw(_ text: Text, in rect: CGRect) { draw(resolve(text), in: rect) }

    // MARK: Images and symbols

    public func resolve(_ image: Image) -> ResolvedImage {
        MainActor.assumeIsolated { ResolvedImage(content: image.content(in: environment), shading: nil) }
    }
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        MainActor.assumeIsolated {
            let n = begin()
            image.content.draw(painter, in: rect)
            end(n)
        }
    }
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = image.size
        draw(image, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) { draw(resolve(image), in: rect, style: style) }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) { draw(resolve(image), at: point, anchor: anchor) }

    public func resolveSymbol<ID: Hashable>(id: ID) -> ResolvedSymbol? {
        symbols[AnyHashable(id)].map { ResolvedSymbol(node: $0) }
    }
    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = symbol.size
        draw(symbol, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
    }
    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        MainActor.assumeIsolated {
            let n = begin()
            painter.translate(rect.minX, rect.minY)
            symbol.node.draw(painter)
            end(n)
        }
    }

    // MARK: State

    public var clipBoundingRect: CGRect {
        var rect = CGRect(origin: .zero, size: canvasSize)
        for clip in clips { rect = rect.intersection(clip.path.boundingRect) }
        return rect.applying(transform.inverted())
    }

    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()) {
        var p = path.applying(transform)
        if options.contains(.inverse) {
            var outer = Path(CGRect(origin: .zero, size: canvasSize).insetBy(dx: -1e4, dy: -1e4))
            outer.addPath(p)
            p = outer
            clips.append((p, true))
        } else {
            clips.append((p, style.isEOFilled))
        }
    }
    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = CGAffineTransform(translationX: x, y: y).concatenating(transform) }
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = CGAffineTransform(scaleX: x, y: y).concatenating(transform) }
    public mutating func rotate(by angle: Angle) { transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians)).concatenating(transform) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }
    public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) { filters.append(filter) }

    /// Renders `content` into an offscreen layer that is composited with this context's opacity, blend mode and filters.
    public func drawLayer(content: (inout GraphicsContext) -> Void) {
        MainActor.assumeIsolated {
            let n = begin()
            var child = self
            child.opacity = 1
            child.blendMode = .normal
            child.filters = []
            child.appliedTransform = transform
            child.appliedClips = clips.count
            // A layer needs its own offscreen target even when nothing else asks for one.
            painter.saveLayer(.init())
            content(&child)
            painter.restore()
            end(n)
        }
    }
}

// MARK: - Canvas view

final class CanvasNode: Node {
    let renderer: (inout GraphicsContext, CGSize) -> Void
    let env: EnvironmentValues
    let symbolNodes: [AnyHashable: Node]

    init(renderer: @escaping (inout GraphicsContext, CGSize) -> Void, env: EnvironmentValues, symbols: [AnyHashable: Node]) {
        self.renderer = renderer
        self.env = env
        self.symbolNodes = symbols
        super.init()
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        for node in symbolNodes.values { node.place(at: .zero, size: node.sizeThatFits(.unspecified), ctx) }
    }
    override func drawContent(_ p: Painter) {
        guard frame.width > 0, frame.height > 0 else { return }
        p.save()
        p.clip(CGRect(origin: .zero, size: frame.size))
        var context = GraphicsContext(painter: p, size: frame.size, environment: env, symbols: symbolNodes)
        renderer(&context, frame.size)
        p.restore()
    }
}

public struct Canvas<Symbols: View>: View, PrimitiveView {
    public typealias Body = Never
    let renderer: (inout GraphicsContext, CGSize) -> Void
    let symbols: Symbols

    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols) {
        self.renderer = renderer
        self.symbols = symbols()
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        var table: [AnyHashable: Node] = [:]
        for (i, node) in resolveNodes(symbols, ctx.child("symbols").with { $0.stackAxis = nil }).enumerated() {
            table[node.traits[TagTraitKey.self] ?? node.traits[IDTraitKey.self] ?? AnyHashable(i)] = node
        }
        out.append(CanvasNode(renderer: renderer, env: ctx.env, symbols: table))
    }
}

extension Canvas where Symbols == EmptyView {
    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer) { EmptyView() }
    }
}
