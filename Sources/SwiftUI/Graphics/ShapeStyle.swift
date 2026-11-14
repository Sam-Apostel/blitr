// ShapeStyle and its resolved form (`_Paint`), which is what the painter draws with.

public struct _Paint: Sendable {
    indirect enum Kind: Sendable {
        case color(RGBA)
        case linear(stops: [GradientStop], start: UnitPoint, end: UnitPoint)
        case radial(stops: [GradientStop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat)
        case elliptical(stops: [GradientStop], center: UnitPoint, startFraction: CGFloat, endFraction: CGFloat)
        case angular(stops: [GradientStop], center: UnitPoint, start: Angle, end: Angle)
        case material(MaterialKind, ColorScheme)
        case opacity(Kind, Double)
    }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
    static func color(_ c: RGBA) -> _Paint { _Paint(.color(c)) }

    /// A single representative color (used where only flat colors make sense, e.g. shadows, text decoration).
    var representativeColor: RGBA {
        func go(_ k: Kind) -> RGBA {
            switch k {
            case .color(let c): return c
            case .linear(let s, _, _), .radial(let s, _, _, _), .elliptical(let s, _, _, _), .angular(let s, _, _, _):
                return s.first?.color ?? .clear
            case .material(let m, let scheme): return m.tint(scheme)
            case .opacity(let inner, let o): return go(inner).opacity(o)
            }
        }
        return go(kind)
    }
}

struct GradientStop: Sendable { var color: RGBA; var location: CGFloat }

public protocol ShapeStyle: Sendable {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
    func _paint(in environment: EnvironmentValues) -> _Paint
}

extension Never: ShapeStyle {
    public typealias Resolved = Never
    public func resolve(in environment: EnvironmentValues) -> Never { fatalError() }
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(.clear) }
}

extension ShapeStyle where Resolved == Never {
    public func resolve(in environment: EnvironmentValues) -> Never { fatalError("\(Self.self) cannot be resolved") }
}

extension ShapeStyle {
    /// Custom styles describe themselves through `resolve(in:)`.
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        if Resolved.self == Never.self { return .color(.clear) }
        return resolve(in: environment)._paint(in: environment)
    }
}

extension Color: ShapeStyle {
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(rgba(in: environment)) }
}

extension Color.Resolved: ShapeStyle {
    public typealias Resolved = Never
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        .color(RGBA(Double(red), Double(green), Double(blue), Double(opacity)))
    }
}

public struct AnyShapeStyle: ShapeStyle {
    let paint: @Sendable (EnvironmentValues) -> _Paint
    public init<S: ShapeStyle>(_ style: S) { paint = { style._paint(in: $0) } }
    public func _paint(in environment: EnvironmentValues) -> _Paint { paint(environment) }
}

// MARK: - Semantic styles

/// The current foreground style (set by `.foregroundStyle`), defaulting to the label color.
public struct ForegroundStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        environment.foregroundStyle?._paint(in: environment) ?? .color(SystemColor.label.resolve(environment.colorScheme))
    }
}

public struct BackgroundStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        environment.backgroundStyle?._paint(in: environment) ?? .color(SystemColor.background.resolve(environment.colorScheme))
    }
}

public struct TintShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(Color.accentColor.rgba(in: environment)) }
}

public struct SeparatorShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(SystemColor.separator.resolve(environment.colorScheme)) }
}

public struct PlaceholderTextShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(SystemColor.placeholderText.resolve(environment.colorScheme)) }
}

public struct LinkShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(Color.accentColor.rgba(in: environment)) }
}

public struct SelectionShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(Color.accentColor.rgba(in: environment)) }
}

public struct FillShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(SystemColor.fill.resolve(environment.colorScheme)) }
}

public struct WindowBackgroundShapeStyle: ShapeStyle {
    public init() {}
    public func _paint(in environment: EnvironmentValues) -> _Paint { .color(SystemColor.background.resolve(environment.colorScheme)) }
}

/// `.primary`, `.secondary`, ... : levels of the current foreground style.
public struct HierarchicalShapeStyle: ShapeStyle {
    let level: Int
    public static let primary = HierarchicalShapeStyle(level: 0)
    public static let secondary = HierarchicalShapeStyle(level: 1)
    public static let tertiary = HierarchicalShapeStyle(level: 2)
    public static let quaternary = HierarchicalShapeStyle(level: 3)
    public static let quinary = HierarchicalShapeStyle(level: 4)

    public func _paint(in environment: EnvironmentValues) -> _Paint {
        if let explicit = environment.foregroundStyleLevels, level < explicit.count {
            return explicit[level]._paint(in: environment)
        }
        if let base = environment.foregroundStyle {
            let opacity = [1, 0.5, 0.25, 0.18, 0.1][min(level, 4)]
            return opacity == 1 ? base._paint(in: environment) : _Paint(.opacity(base._paint(in: environment).kind, opacity))
        }
        let scheme = environment.colorScheme
        switch level {
        case 0: return .color(SystemColor.label.resolve(scheme))
        case 1: return .color(SystemColor.secondaryLabel.resolve(scheme))
        case 2: return .color(SystemColor.tertiaryLabel.resolve(scheme))
        default: return .color(SystemColor.quaternaryLabel.resolve(scheme))
        }
    }
}

public struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let opacity: Double
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.opacity(base._paint(in: environment).kind, opacity))
    }
}

extension ShapeStyle {
    public func opacity(_ opacity: Double) -> some ShapeStyle { _OpacityShapeStyle(base: self, opacity: opacity) }
    public func blendMode(_ mode: BlendMode) -> some ShapeStyle { self }
    public func shadow(_ style: ShadowStyle) -> some ShapeStyle { self }
    public var secondary: some ShapeStyle { _OpacityShapeStyle(base: self, opacity: 0.5) }
    public var tertiary: some ShapeStyle { _OpacityShapeStyle(base: self, opacity: 0.25) }
    public var quaternary: some ShapeStyle { _OpacityShapeStyle(base: self, opacity: 0.18) }
    public var quinary: some ShapeStyle { _OpacityShapeStyle(base: self, opacity: 0.1) }
}

public struct ShadowStyle: Equatable, Sendable {
    public static func drop(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle { ShadowStyle() }
    public static func inner(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.55), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle { ShadowStyle() }
}

extension ShapeStyle where Self == Color {
    public static var red: Color { .red }
    public static var orange: Color { .orange }
    public static var yellow: Color { .yellow }
    public static var green: Color { .green }
    public static var mint: Color { .mint }
    public static var teal: Color { .teal }
    public static var cyan: Color { .cyan }
    public static var blue: Color { .blue }
    public static var indigo: Color { .indigo }
    public static var purple: Color { .purple }
    public static var pink: Color { .pink }
    public static var brown: Color { .brown }
    public static var white: Color { .white }
    public static var gray: Color { .gray }
    public static var black: Color { .black }
    public static var clear: Color { .clear }
}

extension ShapeStyle where Self == ForegroundStyle { public static var foreground: ForegroundStyle { ForegroundStyle() } }
extension ShapeStyle where Self == BackgroundStyle { public static var background: BackgroundStyle { BackgroundStyle() } }
extension ShapeStyle where Self == TintShapeStyle { public static var tint: TintShapeStyle { TintShapeStyle() } }
extension ShapeStyle where Self == SeparatorShapeStyle { public static var separator: SeparatorShapeStyle { SeparatorShapeStyle() } }
extension ShapeStyle where Self == PlaceholderTextShapeStyle { public static var placeholder: PlaceholderTextShapeStyle { PlaceholderTextShapeStyle() } }
extension ShapeStyle where Self == LinkShapeStyle { public static var link: LinkShapeStyle { LinkShapeStyle() } }
extension ShapeStyle where Self == SelectionShapeStyle { public static var selection: SelectionShapeStyle { SelectionShapeStyle() } }
extension ShapeStyle where Self == FillShapeStyle { public static var fill: FillShapeStyle { FillShapeStyle() } }
extension ShapeStyle where Self == WindowBackgroundShapeStyle { public static var windowBackground: WindowBackgroundShapeStyle { WindowBackgroundShapeStyle() } }
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
    public static var quinary: HierarchicalShapeStyle { .quinary }
}

// MARK: - Materials

enum MaterialKind: Sendable {
    case ultraThin, thin, regular, thick, ultraThick, bar
    /// Flat tint laid over the blurred backdrop.
    func tint(_ scheme: ColorScheme) -> RGBA {
        let dark = scheme == .dark
        switch self {
        case .ultraThin: return dark ? RGBA(0.15, 0.15, 0.15, 0.35) : RGBA(1, 1, 1, 0.3)
        case .thin: return dark ? RGBA(0.15, 0.15, 0.15, 0.5) : RGBA(1, 1, 1, 0.45)
        case .regular: return dark ? RGBA(0.13, 0.13, 0.13, 0.68) : RGBA(0.98, 0.98, 0.98, 0.7)
        case .thick: return dark ? RGBA(0.12, 0.12, 0.12, 0.82) : RGBA(0.97, 0.97, 0.97, 0.84)
        case .ultraThick: return dark ? RGBA(0.11, 0.11, 0.11, 0.9) : RGBA(0.96, 0.96, 0.96, 0.92)
        case .bar: return dark ? RGBA(0.11, 0.11, 0.11, 0.8) : RGBA(0.97, 0.97, 0.97, 0.8)
        }
    }
    var blurRadius: CGFloat { 30 }
}

public struct Material: ShapeStyle {
    let kind: MaterialKind
    public static let ultraThinMaterial = Material(kind: .ultraThin)
    public static let thinMaterial = Material(kind: .thin)
    public static let regularMaterial = Material(kind: .regular)
    public static let thickMaterial = Material(kind: .thick)
    public static let ultraThickMaterial = Material(kind: .ultraThick)
    public static let bar = Material(kind: .bar)
    public static let ultraThin = Material(kind: .ultraThin)
    public static let thin = Material(kind: .thin)
    public static let regular = Material(kind: .regular)
    public static let thick = Material(kind: .thick)
    public static let ultraThick = Material(kind: .ultraThick)
    public func _paint(in environment: EnvironmentValues) -> _Paint { _Paint(.material(kind, environment.colorScheme)) }
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThinMaterial }
    public static var thinMaterial: Material { .thinMaterial }
    public static var regularMaterial: Material { .regularMaterial }
    public static var thickMaterial: Material { .thickMaterial }
    public static var ultraThickMaterial: Material { .ultraThickMaterial }
    public static var bar: Material { .bar }
}

// MARK: - Gradients

public struct Gradient: Equatable, Hashable, Sendable, ShapeStyle {
    public struct Stop: Equatable, Hashable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) { self.color = color; self.location = location }
    }
    public struct ColorSpace: Hashable, Sendable {
        public static let device = ColorSpace()
        public static let perceptual = ColorSpace()
    }
    public var stops: [Stop]
    public init(stops: [Stop]) { self.stops = stops }
    public init(colors: [Color]) {
        let n = colors.count
        stops = colors.enumerated().map { Stop(color: $1, location: n > 1 ? CGFloat($0) / CGFloat(n - 1) : 0) }
    }
    public func colorSpace(_ space: ColorSpace) -> AnyGradient { AnyGradient(self) }
    func resolved(_ env: EnvironmentValues) -> [GradientStop] {
        stops.map { GradientStop(color: $0.color.rgba(in: env), location: $0.location) }
    }
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.linear(stops: resolved(environment), start: .top, end: .bottom))
    }
}

public struct AnyGradient: Hashable, ShapeStyle, Sendable {
    let gradient: Gradient
    public init(_ gradient: Gradient) { self.gradient = gradient }
    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient { self }
    public func _paint(in environment: EnvironmentValues) -> _Paint { gradient._paint(in: environment) }
}

extension Color {
    /// The standard subtle top-to-bottom gradient derived from a color.
    public var gradient: AnyGradient {
        AnyGradient(Gradient(colors: [self.mix(with: .white, by: 0.22), self]))
    }
}

public struct LinearGradient: ShapeStyle, View, Sendable {
    let gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient; self.startPoint = startPoint; self.endPoint = endPoint
    }
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.linear(stops: gradient.resolved(environment), start: startPoint, end: endPoint))
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct RadialGradient: ShapeStyle, View, Sendable {
    let gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat
    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient; self.center = center; self.startRadius = startRadius; self.endRadius = endRadius
    }
    public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
    }
    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
    }
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.radial(stops: gradient.resolved(environment), center: center, startRadius: startRadius, endRadius: endRadius))
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct EllipticalGradient: ShapeStyle, View, Sendable {
    let gradient: Gradient, center: UnitPoint, startRadiusFraction: CGFloat, endRadiusFraction: CGFloat
    public init(gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.gradient = gradient; self.center = center
        self.startRadiusFraction = startRadiusFraction; self.endRadiusFraction = endRadiusFraction
    }
    public init(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    public init(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.elliptical(stops: gradient.resolved(environment), center: center, startFraction: startRadiusFraction, endFraction: endRadiusFraction))
    }
    public var body: some View { Rectangle().fill(self) }
}

public struct AngularGradient: ShapeStyle, View, Sendable {
    let gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle
    public init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) {
        self.gradient = gradient; self.center = center; self.startAngle = startAngle
        self.endAngle = endAngle == startAngle ? startAngle + .degrees(360) : endAngle
    }
    public init(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
        self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public init(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
        self.init(gradient: Gradient(stops: stops), center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public init(gradient: Gradient, center: UnitPoint, angle: Angle) {
        self.init(gradient: gradient, center: center, startAngle: angle, endAngle: angle + .degrees(360))
    }
    public init(colors: [Color], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
    }
    public init(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(stops: stops), center: center, angle: angle)
    }
    public func _paint(in environment: EnvironmentValues) -> _Paint {
        _Paint(.angular(stops: gradient.resolved(environment), center: center, start: startAngle, end: endAngle))
    }
    public var body: some View { Rectangle().fill(self) }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}
extension ShapeStyle where Self == RadialGradient {
    public static func radialGradient(_ gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }
    public static func radialGradient(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(colors: colors, center: center, startRadius: startRadius, endRadius: endRadius)
    }
}
extension ShapeStyle where Self == EllipticalGradient {
    public static func ellipticalGradient(_ gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(gradient: gradient, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    public static func ellipticalGradient(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(colors: colors, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
}
extension ShapeStyle where Self == AngularGradient {
    public static func angularGradient(_ gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func angularGradient(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(colors: colors, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func conicGradient(_ gradient: Gradient, center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
        AngularGradient(gradient: gradient, center: center, angle: angle)
    }
    public static func conicGradient(colors: [Color], center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
        AngularGradient(colors: colors, center: center, angle: angle)
    }
}

// MARK: - Environment + modifiers

enum ForegroundStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }
enum ForegroundStyleLevelsKey: EnvironmentKey { static let defaultValue: [AnyShapeStyle]? = nil }
enum BackgroundStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }

extension EnvironmentValues {
    var foregroundStyle: AnyShapeStyle? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }
    var foregroundStyleLevels: [AnyShapeStyle]? {
        get { self[ForegroundStyleLevelsKey.self] }
        set { self[ForegroundStyleLevelsKey.self] = newValue }
    }
    public var backgroundStyle: AnyShapeStyle? {
        get { self[BackgroundStyleKey.self] }
        set { self[BackgroundStyleKey.self] = newValue }
    }
}

extension View {
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        env {
            // `.foregroundStyle(.secondary)` is relative to the style already in effect.
            let outer = $0
            $0.foregroundStyle = style is ForegroundStyle ? outer.foregroundStyle : AnyShapeStyle(_FixedPaintStyle(style._paint(in: outer)))
            $0.foregroundStyleLevels = nil
        }
    }
    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        env { $0.foregroundStyle = AnyShapeStyle(primary); $0.foregroundStyleLevels = [AnyShapeStyle(primary), AnyShapeStyle(secondary)] }
    }
    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(_ primary: S1, _ secondary: S2, _ tertiary: S3) -> some View {
        env { $0.foregroundStyle = AnyShapeStyle(primary); $0.foregroundStyleLevels = [AnyShapeStyle(primary), AnyShapeStyle(secondary), AnyShapeStyle(tertiary)] }
    }
    public func foregroundColor(_ color: Color?) -> some View {
        env { $0.foregroundStyle = color.map { AnyShapeStyle($0) }; $0.foregroundStyleLevels = nil }
    }
    public func backgroundStyle<S: ShapeStyle>(_ style: S) -> some View { env { $0.backgroundStyle = AnyShapeStyle(style) } }
    public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
        env { e in e.accentColor = tint.map { Color($0._paint(in: e).representativeColor) } }
    }
}

struct _FixedPaintStyle: ShapeStyle {
    let paint: _Paint
    init(_ paint: _Paint) { self.paint = paint }
    func _paint(in environment: EnvironmentValues) -> _Paint { paint }
}

public enum BlendMode: Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver, destinationOut
    case plusDarker, plusLighter
}
