// SwiftUI API that takes or gives Core Graphics types (Apple's SwiftUI re-exports CoreGraphics).

extension Color {
    public init(cgColor: CGColor) { self.init(RGBA(cgColor.rgba.r, cgColor.rgba.g, cgColor.rgba.b, cgColor.rgba.a)) }
    @available(*, deprecated, renamed: "init(cgColor:)")
    public init(_ cgColor: CGColor) { self.init(cgColor: cgColor) }

    /// The color as a `CGColor`. Asset-catalog colors have none, as on Apple platforms; adaptive colors
    /// resolve in the appearance being rendered.
    public var cgColor: CGColor? {
        if case .named = storage { return nil }
        var env = EnvironmentValues()
        env.colorScheme = _currentConfiguration().colorScheme
        let c = rgba(in: env)
        return CGColor(r: c.r, g: c.g, b: c.b, a: c.a)
    }
}

extension Path {
    public init(_ path: CGPath) {
        self.init()
        for element in path.data.elements {
            switch element {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quad(let p, let c): addQuadCurve(to: p, control: c)
            case .curve(let p, let c1, let c2): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
    public init(_ path: CGMutablePath) { self.init(path as CGPath) }
    public var cgPath: CGPath {
        var data = PathData()
        forEach { element in
            switch element {
            case .move(let p): data.move(to: p)
            case .line(let p): data.line(to: p)
            case .quadCurve(let p, let c): data.quad(to: p, control: c)
            case .curve(let p, let c1, let c2): data.curve(to: p, control1: c1, control2: c2)
            case .closeSubpath: data.close()
            }
        }
        return CGPath(data: data)
    }
}

extension GraphicsContext {
    /// Core Graphics drawing inside a Canvas is not available: the closure is not called.
    public func withCGContext(content: (CGContext) throws -> Void) rethrows {
        ShimDiagnostics.warn("GraphicsContext.withCGContext is not supported; its drawing was skipped")
    }
}
