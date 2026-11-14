// Shapes: the protocol, the built-in shapes, and the node that draws them.

// MARK: - Animatable (inert, kept for source compatibility)

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}
extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}
extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    public init() {}
    public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    public static func + (l: Self, r: Self) -> Self { l }
    public static func - (l: Self, r: Self) -> Self { l }
    public mutating func scale(by rhs: Double) {}
    public var magnitudeSquared: Double { 0 }
}
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) { self.first = first; self.second = second }
    public static var zero: Self { .init(.zero, .zero) }
    public static func + (l: Self, r: Self) -> Self { .init(l.first + r.first, l.second + r.second) }
    public static func - (l: Self, r: Self) -> Self { .init(l.first - r.first, l.second - r.second) }
    public mutating func scale(by rhs: Double) { first.scale(by: rhs); second.scale(by: rhs) }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}
extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic = EmptyAnimatableData
    var animatableData: AnimatableData { get set }
}
extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
}

// MARK: - Shape

public enum ShapeRole: Sendable { case fill, stroke, separator }

public protocol Shape: Sendable, Animatable, View {
    nonisolated func path(in rect: CGRect) -> Path
    nonisolated static var role: ShapeRole { get }
    nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
}

extension Shape {
    public nonisolated static var role: ShapeRole { .fill }
    public nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    public var body: _ShapeView<Self, ForegroundStyle> { _ShapeView(shape: self, layers: [.init(op: .fill(FillStyle()), style: AnyShapeStyle(ForegroundStyle()))]) }
}

public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    nonisolated func inset(by amount: CGFloat) -> InsetShape
}

enum ShapeLayerOp {
    case fill(FillStyle), stroke(StrokeStyle), strokeBorder(StrokeStyle, inset: @Sendable (CGRect) -> Path)
}

/// A shape plus the fills/strokes to draw with it, back to front.
public struct _ShapeView<Content: Shape, Style: ShapeStyle>: View, PrimitiveView {
    public typealias Body = Never
    struct Layer {
        typealias Op = ShapeLayerOp
        var op: Op
        var style: AnyShapeStyle
    }
    let shape: Content
    var layers: [Layer]

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let shape = self.shape
        let resolved = layers.map { ShapeNode.Layer(op: $0.op, paint: $0.style._paint(in: ctx.env)) }
        out.append(ShapeNode(path: { shape.path(in: $0) }, size: { shape.sizeThatFits($0) }, layers: resolved))
    }

    func adding<S: ShapeStyle>(_ op: Layer.Op, _ style: S) -> _ShapeView<Content, Style> {
        var copy = self
        copy.layers.append(Layer(op: op, style: AnyShapeStyle(style)))
        return copy
    }

    public func fill<S: ShapeStyle>(_ content: S = ForegroundStyle(), style: FillStyle = FillStyle()) -> _ShapeView<Content, Style> {
        adding(.fill(style), content)
    }
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> _ShapeView<Content, Style> {
        adding(.stroke(style), content)
    }
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> _ShapeView<Content, Style> {
        adding(.stroke(StrokeStyle(lineWidth: lineWidth)), content)
    }
}

extension _ShapeView where Content: InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S = ForegroundStyle(), style: StrokeStyle, antialiased: Bool = true) -> _ShapeView<Content, Style> {
        let inset = shape.inset(by: style.lineWidth / 2)
        return adding(.strokeBorder(style, inset: { inset.path(in: $0) }), content)
    }
    public func strokeBorder<S: ShapeStyle>(_ content: S = ForegroundStyle(), lineWidth: CGFloat = 1, antialiased: Bool = true) -> _ShapeView<Content, Style> {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
}

final class ShapeNode: Node {
    struct Layer {
        var op: ShapeLayerOp
        var paint: _Paint
    }
    let path: (CGRect) -> Path
    let size: (ProposedViewSize) -> CGSize
    let layers: [Layer]

    init(path: @escaping (CGRect) -> Path, size: @escaping (ProposedViewSize) -> CGSize = { $0.replacingUnspecifiedDimensions() }, layers: [Layer]) {
        self.path = path
        self.size = size
        self.layers = layers
        super.init()
    }

    convenience init(path: @escaping (CGRect) -> Path, fill: _Paint) {
        self.init(path: path, layers: [Layer(op: .fill(FillStyle()), paint: fill)])
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { size(proposal) }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        for layer in layers {
            switch layer.op {
            case .fill(let style): p.fill(path(bounds), with: layer.paint, in: bounds, style: style)
            case .stroke(let style): p.stroke(path(bounds), with: layer.paint, style: style, in: bounds)
            case .strokeBorder(let style, let inset): p.stroke(inset(bounds), with: layer.paint, style: style, in: bounds)
            }
        }
    }
}

extension Shape {
    public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> {
        _ShapeView(shape: self, layers: [.init(op: .fill(style), style: AnyShapeStyle(content))])
    }
    public func fill(style: FillStyle = FillStyle()) -> _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, layers: [.init(op: .fill(style), style: AnyShapeStyle(ForegroundStyle()))])
    }
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> _ShapeView<Self, S> {
        _ShapeView(shape: self, layers: [.init(op: .stroke(style), style: AnyShapeStyle(content))])
    }
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> _ShapeView<Self, S> {
        stroke(content, style: StrokeStyle(lineWidth: lineWidth))
    }
    public func stroke(style: StrokeStyle) -> _StrokedShape<Self> { _StrokedShape(shape: self, style: style) }
    public func stroke(lineWidth: CGFloat = 1) -> _StrokedShape<Self> { _StrokedShape(shape: self, style: StrokeStyle(lineWidth: lineWidth)) }

    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> _TransformedShape<Self> {
        _TransformedShape(shape: self) { path, _ in path.trimmedPath(from: startFraction, to: endFraction) }
    }
    public func offset(_ offset: CGSize) -> _TransformedShape<Self> {
        _TransformedShape(shape: self) { path, _ in path.offsetBy(dx: offset.width, dy: offset.height) }
    }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> _TransformedShape<Self> { offset(CGSize(width: x, height: y)) }
    public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> _TransformedShape<Self> {
        _TransformedShape(shape: self) { path, rect in
            let a = anchor.point(in: rect)
            return path.applying(CGAffineTransform(translationX: -a.x, y: -a.y)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(angle.radians)))
                .concatenating(CGAffineTransform(translationX: a.x, y: a.y)))
        }
    }
    public func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> _TransformedShape<Self> {
        _TransformedShape(shape: self) { path, rect in
            let a = anchor.point(in: rect)
            return path.applying(CGAffineTransform(translationX: -a.x, y: -a.y)
                .concatenating(CGAffineTransform(scaleX: x, y: y))
                .concatenating(CGAffineTransform(translationX: a.x, y: a.y)))
        }
    }
    public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> _TransformedShape<Self> { self.scale(x: scale, y: scale, anchor: anchor) }
    public func transform(_ transform: CGAffineTransform) -> _TransformedShape<Self> {
        _TransformedShape(shape: self) { path, _ in path.applying(transform) }
    }
    public func size(_ size: CGSize) -> _TransformedShape<Rectangle> {
        let shape = self
        return _TransformedShape(shape: Rectangle()) { _, _ in shape.path(in: CGRect(origin: .zero, size: size)) }
    }
    public func size(width: CGFloat, height: CGFloat) -> _TransformedShape<Rectangle> { size(CGSize(width: width, height: height)) }
}

extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> _ShapeView<Self, S> {
        let inset = self.inset(by: style.lineWidth / 2)
        return _ShapeView(shape: self, layers: [.init(op: .strokeBorder(style, inset: { inset.path(in: $0) }), style: AnyShapeStyle(content))])
    }
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> _ShapeView<Self, S> {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> _ShapeView<Self, ForegroundStyle> {
        strokeBorder(ForegroundStyle(), style: style, antialiased: antialiased)
    }
    public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> _ShapeView<Self, ForegroundStyle> {
        strokeBorder(ForegroundStyle(), style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
}

public struct _TransformedShape<Content: Shape>: Shape {
    let shape: Content
    let transform: @Sendable (Path, CGRect) -> Path
    public nonisolated func path(in rect: CGRect) -> Path { transform(shape.path(in: rect), rect) }
    public nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }
}

public struct _StrokedShape<Content: Shape>: Shape {
    let shape: Content
    let style: StrokeStyle
    public nonisolated func path(in rect: CGRect) -> Path { shape.path(in: rect).strokedPath(style) }
}

public struct AnyShape: Shape {
    let make: @Sendable (CGRect) -> Path
    let fit: @Sendable (ProposedViewSize) -> CGSize
    public init<S: Shape>(_ shape: S) {
        make = { shape.path(in: $0) }
        fit = { shape.sizeThatFits($0) }
    }
    public nonisolated func path(in rect: CGRect) -> Path { make(rect) }
    public nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { fit(proposal) }
}

extension Path: Shape {
    public nonisolated func path(in rect: CGRect) -> Path { self }
}

// MARK: - Built-in shapes

public struct Rectangle: InsettableShape {
    var insetAmount: CGFloat = 0
    public init() {}
    public nonisolated func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: insetAmount, dy: insetAmount)) }
    public nonisolated func inset(by amount: CGFloat) -> Rectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct RoundedRectangle: InsettableShape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    var insetAmount: CGFloat = 0
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { self.cornerSize = cornerSize; self.style = style }
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
    public nonisolated func path(in rect: CGRect) -> Path {
        let size = CGSize(width: max(0, cornerSize.width - insetAmount), height: max(0, cornerSize.height - insetAmount))
        return Path(roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount), cornerSize: size, style: style)
    }
    public nonisolated func inset(by amount: CGFloat) -> RoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct UnevenRoundedRectangle: InsettableShape {
    public var cornerRadii: RectangleCornerRadii
    public var style: RoundedCornerStyle
    var insetAmount: CGFloat = 0
    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) { self.cornerRadii = cornerRadii; self.style = style }
    public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
                topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadii: RectangleCornerRadii(topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius,
                                                    bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius), style: style)
    }
    public nonisolated func path(in rect: CGRect) -> Path {
        var radii = cornerRadii
        radii.topLeading = max(0, radii.topLeading - insetAmount); radii.topTrailing = max(0, radii.topTrailing - insetAmount)
        radii.bottomLeading = max(0, radii.bottomLeading - insetAmount); radii.bottomTrailing = max(0, radii.bottomTrailing - insetAmount)
        var p = Path()
        p.addUnevenRoundedRect(rect.insetBy(dx: insetAmount, dy: insetAmount), radii, style: style)
        return p
    }
    public nonisolated func inset(by amount: CGFloat) -> UnevenRoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct Capsule: InsettableShape {
    public var style: RoundedCornerStyle
    var insetAmount: CGFloat = 0
    public init(style: RoundedCornerStyle = .continuous) { self.style = style }
    public nonisolated func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(roundedRect: r, cornerRadius: min(r.width, r.height) / 2, style: .circular)
    }
    public nonisolated func inset(by amount: CGFloat) -> Capsule {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct Ellipse: InsettableShape {
    var insetAmount: CGFloat = 0
    public init() {}
    public nonisolated func path(in rect: CGRect) -> Path { Path(ellipseIn: rect.insetBy(dx: insetAmount, dy: insetAmount)) }
    public nonisolated func inset(by amount: CGFloat) -> Ellipse {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct Circle: InsettableShape {
    var insetAmount: CGFloat = 0
    public init() {}
    public nonisolated func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(ellipseIn: square.insetBy(dx: insetAmount, dy: insetAmount))
    }
    public nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // A circle keeps a 1:1 aspect when only one dimension is proposed.
        switch (proposal.width, proposal.height) {
        case let (w?, nil): return CGSize(width: w, height: w)
        case let (nil, h?): return CGSize(width: h, height: h)
        default: return proposal.replacingUnspecifiedDimensions()
        }
    }
    public nonisolated func inset(by amount: CGFloat) -> Circle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct ContainerRelativeShape: InsettableShape {
    var insetAmount: CGFloat = 0
    /// The container's corner radius where the shape is created: set while a widget's content is
    /// resolved (Widgets/WidgetHost.swift), 16pt elsewhere. `.infinity` means a circle.
    nonisolated(unsafe) static var contextRadius: CGFloat?
    var radius: CGFloat? = ContainerRelativeShape.contextRadius
    public init() {}
    public nonisolated func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard let radius else { return Path(roundedRect: r, cornerRadius: 16, style: .continuous) }
        if radius == .infinity { return Path(ellipseIn: r) }
        return Path(roundedRect: r, cornerRadius: max(0, radius - insetAmount), style: .continuous)
    }
    public nonisolated func inset(by amount: CGFloat) -> ContainerRelativeShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension Shape where Self == Rectangle { public static var rect: Rectangle { Rectangle() } }
extension Shape where Self == Circle { public static var circle: Circle { Circle() } }
extension Shape where Self == Ellipse { public static var ellipse: Ellipse { Ellipse() } }
extension Shape where Self == Capsule {
    public static var capsule: Capsule { Capsule() }
    public static func capsule(style: RoundedCornerStyle) -> Capsule { Capsule(style: style) }
}
extension Shape where Self == ContainerRelativeShape { public static var containerRelative: ContainerRelativeShape { ContainerRelativeShape() } }
extension Shape where Self == RoundedRectangle {
    public static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerSize: cornerSize, style: style)
    }
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
}
extension Shape where Self == UnevenRoundedRectangle {
    public static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: style)
    }
    public static func rect(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
                            topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: topLeadingRadius, bottomLeadingRadius: bottomLeadingRadius,
                               bottomTrailingRadius: bottomTrailingRadius, topTrailingRadius: topTrailingRadius, style: style)
    }
}

// MARK: - Color and Divider as views

extension Color: View, PrimitiveView {
    public typealias Body = Never
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        out.append(ShapeNode(path: { Path($0) }, fill: _paint(in: ctx.env)))
    }
}

final class DividerNode: Node {
    let axis: Axis
    let paint: _Paint
    let thickness: CGFloat
    init(axis: Axis, paint: _Paint, thickness: CGFloat) {
        self.axis = axis
        self.paint = paint
        self.thickness = thickness
        super.init()
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        axis == .horizontal
            ? CGSize(width: proposal.width ?? 10, height: thickness)
            : CGSize(width: thickness, height: proposal.height ?? 10)
    }
    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        p.fill(Path(bounds), with: paint, in: bounds)
    }
}

public struct Divider: View, PrimitiveView {
    public typealias Body = Never
    public init() {}
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        // Inside an HStack a divider is a vertical line; everywhere else it is horizontal.
        let axis: Axis = ctx.env.stackAxis == .horizontal ? .vertical : .horizontal
        out.append(DividerNode(axis: axis, paint: .color(SystemColor.separator.resolve(ctx.env.colorScheme)),
                               thickness: 1 / ctx.env.displayScale))
    }
}
