// The public Liquid Glass API (iOS 26+): Glass, glassEffect, GlassEffectContainer.

public struct Glass: Equatable, Sendable {
    enum Variant: Equatable, Sendable { case regular, clear, identity }
    var variant: Variant
    var tintColor: Color?
    var isInteractive = false

    public static var regular: Glass { Glass(variant: .regular) }
    public static var clear: Glass { Glass(variant: .clear) }
    public static var identity: Glass { Glass(variant: .identity) }

    public func tint(_ color: Color?) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }
    public func interactive(_ isEnabled: Bool = true) -> Glass {
        var copy = self
        copy.isInteractive = isEnabled
        return copy
    }
}

/// The shape glass takes when none is given: a capsule.
public struct DefaultGlassEffectShape: Shape {
    public init() {}
    public nonisolated func path(in rect: CGRect) -> Path { Capsule().path(in: rect) }
}

extension Shape {
    /// The outline to draw glass in. Shapes that are rounded rectangles get edge refraction.
    func glassOutline(in rect: CGRect) -> GlassOutline {
        switch self {
        case is Capsule, is DefaultGlassEffectShape: return .roundedRect(rect, radius: min(rect.width, rect.height) / 2)
        case is Circle:
            let side = min(rect.width, rect.height)
            return .roundedRect(CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), radius: side / 2)
        case let rounded as RoundedRectangle: return .roundedRect(rect, radius: min(rounded.cornerSize.width, rounded.cornerSize.height))
        case is Rectangle: return .roundedRect(rect, radius: 0)
        case is ContainerRelativeShape: return .roundedRect(rect, radius: 16)
        default: return .path(path(in: rect))
        }
    }
}

/// Draws glass behind its child.
final class GlassNode: WrapperNode {
    let outline: (CGRect) -> GlassOutline
    let appearance: GlassAppearance
    init(child: Node, outline: @escaping (CGRect) -> GlassOutline, appearance: GlassAppearance) {
        self.outline = outline
        self.appearance = appearance
        super.init(child: child)
    }
    override func drawContent(_ p: Painter) {
        p.fillGlass(outline(CGRect(origin: .zero, size: frame.size)), appearance: appearance)
        drawChildren(p)
    }
}

extension GlassAppearance {
    /// The appearance for a `Glass` value in an environment, including its tint.
    static func resolve(_ glass: Glass, in env: EnvironmentValues) -> GlassAppearance {
        var appearance = GlassAppearance.system(glass.variant, scheme: env.colorScheme, design: env.designLanguage)
        if let tint = glass.tintColor {
            // Tinted glass: the color replaces the neutral tint and stays translucent.
            let color = tint.rgba(in: env)
            appearance.tint = RGBA(color.r, color.g, color.b, 0.78 * color.a)
            appearance.brightness = 0
            appearance.saturation = 1
        }
        return appearance
    }
}

struct GlassEffectModifier<S: Shape>: ViewModifier, NodeModifier {
    let glass: Glass
    let shape: S
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        if glass.variant == .identity { return child }
        let shape = self.shape
        guard ctx.env.designLanguage.isGlass else {
            // Rendering an older iOS: code that reaches glass anyway gets the closest older look.
            return StyleLayerNode(child: child, paint: Material.ultraThinMaterial._paint(in: ctx.env),
                                  shape: { shape.path(in: $0) }, inFront: false, ignoredEdges: [])
        }
        return GlassNode(child: child, outline: { shape.glassOutline(in: $0) }, appearance: .resolve(glass, in: ctx.env))
    }
}

extension View {
    public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S = DefaultGlassEffectShape()) -> some View {
        modifier(GlassEffectModifier(glass: glass, shape: shape))
    }
    public func glassEffectID<ID: Hashable & Sendable>(_ id: ID?, in namespace: Namespace.ID) -> some View { self }
    public func glassEffectUnion<ID: Hashable & Sendable>(id: ID?, namespace: Namespace.ID) -> some View { self }
    public func glassEffectTransition(_ transition: GlassEffectTransition) -> some View { self }
}

public struct GlassEffectTransition: Sendable {
    public static let identity = GlassEffectTransition()
    public static let matchedGeometry = GlassEffectTransition()
    public static let materialize = GlassEffectTransition()
}

/// Groups glass shapes so they can blend into each other. Blending is a motion effect; in a
/// static frame the shapes are drawn individually.
public struct GlassEffectContainer<Content: View>: View {
    let content: Content
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { content }
}
