// Color, including the iOS system palette with its light/dark variants.

/// Non-premultiplied sRGB (gamma-encoded) components.
package struct RGBA: Hashable, Sendable {
    package var r: Double, g: Double, b: Double, a: Double
    package init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }
    package static let clear = RGBA(0, 0, 0, 0)
    package static let black = RGBA(0, 0, 0, 1)
    package static let white = RGBA(1, 1, 1, 1)
    func opacity(_ o: Double) -> RGBA { RGBA(r, g, b, a * o) }
    func mix(_ other: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
    /// Relative luminance, used to pick contrasting foregrounds.
    package var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// A color with separate light and dark appearances.
package struct DynamicColor: Hashable, Sendable {
    package var light: RGBA, dark: RGBA
    package init(_ light: UInt32, _ dark: UInt32, alpha: Double = 1, darkAlpha: Double? = nil) {
        self.light = RGBA(hex: light, alpha: alpha)
        self.dark = RGBA(hex: dark, alpha: darkAlpha ?? alpha)
    }
    func resolve(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? dark : light }
}

/// The UIKit semantic palette (values from the iOS system colors).
package enum SystemColor {
    package static let red = DynamicColor(0xFF3B30, 0xFF453A)
    package static let orange = DynamicColor(0xFF9500, 0xFF9F0A)
    package static let yellow = DynamicColor(0xFFCC00, 0xFFD60A)
    package static let green = DynamicColor(0x34C759, 0x30D158)
    package static let mint = DynamicColor(0x00C7BE, 0x63E6E2)
    package static let teal = DynamicColor(0x30B0C7, 0x40C8E0)
    package static let cyan = DynamicColor(0x32ADE6, 0x64D2FF)
    package static let blue = DynamicColor(0x007AFF, 0x0A84FF)
    package static let indigo = DynamicColor(0x5856D6, 0x5E5CE6)
    package static let purple = DynamicColor(0xAF52DE, 0xBF5AF2)
    package static let pink = DynamicColor(0xFF2D55, 0xFF375F)
    package static let brown = DynamicColor(0xA2845E, 0xAC8E68)
    package static let gray = DynamicColor(0x8E8E93, 0x8E8E93)
    package static let gray2 = DynamicColor(0xAEAEB2, 0x636366)
    package static let gray3 = DynamicColor(0xC7C7CC, 0x48484A)
    package static let gray4 = DynamicColor(0xD1D1D6, 0x3A3A3C)
    package static let gray5 = DynamicColor(0xE5E5EA, 0x2C2C2E)
    package static let gray6 = DynamicColor(0xF2F2F7, 0x1C1C1E)
    package static let label = DynamicColor(0x000000, 0xFFFFFF)
    package static let secondaryLabel = DynamicColor(0x3C3C43, 0xEBEBF5, alpha: 0.6)
    package static let tertiaryLabel = DynamicColor(0x3C3C43, 0xEBEBF5, alpha: 0.3)
    package static let quaternaryLabel = DynamicColor(0x3C3C43, 0xEBEBF5, alpha: 0.18, darkAlpha: 0.16)
    package static let placeholderText = DynamicColor(0x3C3C43, 0xEBEBF5, alpha: 0.3)
    package static let separator = DynamicColor(0x3C3C43, 0x545458, alpha: 0.29, darkAlpha: 0.6)
    package static let opaqueSeparator = DynamicColor(0xC6C6C8, 0x38383A)
    package static let link = DynamicColor(0x007AFF, 0x0984FF)
    package static let background = DynamicColor(0xFFFFFF, 0x000000)
    package static let secondaryBackground = DynamicColor(0xF2F2F7, 0x1C1C1E)
    package static let tertiaryBackground = DynamicColor(0xFFFFFF, 0x2C2C2E)
    package static let groupedBackground = DynamicColor(0xF2F2F7, 0x000000)
    package static let secondaryGroupedBackground = DynamicColor(0xFFFFFF, 0x1C1C1E)
    package static let tertiaryGroupedBackground = DynamicColor(0xF2F2F7, 0x2C2C2E)
    package static let fill = DynamicColor(0x787880, 0x787880, alpha: 0.2, darkAlpha: 0.36)
    package static let secondaryFill = DynamicColor(0x787880, 0x787880, alpha: 0.16, darkAlpha: 0.32)
    package static let tertiaryFill = DynamicColor(0x767680, 0x767680, alpha: 0.12, darkAlpha: 0.24)
    package static let quaternaryFill = DynamicColor(0x747480, 0x767680, alpha: 0.08, darkAlpha: 0.18)
    package static let white = DynamicColor(0xFFFFFF, 0xFFFFFF)
    package static let black = DynamicColor(0x000000, 0x000000)
}

public struct Color: Hashable, Sendable {
    indirect enum Storage: Hashable, Sendable {
        case rgba(RGBA)
        case dynamic(DynamicColor)
        case opacity(Storage, Double)
        case mix(Storage, Storage, Double)
        case accent
        case named(String)
    }
    let storage: Storage

    init(_ storage: Storage) { self.storage = storage }
    package init(_ rgba: RGBA) { storage = .rgba(rgba) }
    package init(_ dynamic: DynamicColor) { storage = .dynamic(dynamic) }

    public enum RGBColorSpace: Hashable, Sendable { case sRGB, sRGBLinear, displayP3 }

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        if colorSpace == .sRGBLinear {
            func encode(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
            storage = .rgba(RGBA(encode(red), encode(green), encode(blue), opacity))
        } else {
            storage = .rgba(RGBA(red, green, blue, opacity))
        }
    }
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let h = (hue - floor(hue)) * 6, s = saturation, v = brightness
        let i = floor(h), f = h - i
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch Int(i) % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        storage = .rgba(RGBA(r, g, b, opacity))
    }
    /// A color from an asset catalog.
    public init(_ name: String, bundle: Bundle? = nil) { storage = .named(name) }

    public func opacity(_ opacity: Double) -> Color { Color(.opacity(storage, opacity)) }

    public func mix(with rhs: Color, by fraction: Double, in colorSpace: Gradient.ColorSpace = .perceptual) -> Color {
        Color(.mix(storage, rhs.storage, fraction))
    }

    public static let clear = Color(RGBA.clear)
    public static let black = Color(RGBA.black)
    public static let white = Color(RGBA.white)
    public static let red = Color(SystemColor.red)
    public static let orange = Color(SystemColor.orange)
    public static let yellow = Color(SystemColor.yellow)
    public static let green = Color(SystemColor.green)
    public static let mint = Color(SystemColor.mint)
    public static let teal = Color(SystemColor.teal)
    public static let cyan = Color(SystemColor.cyan)
    public static let blue = Color(SystemColor.blue)
    public static let indigo = Color(SystemColor.indigo)
    public static let purple = Color(SystemColor.purple)
    public static let pink = Color(SystemColor.pink)
    public static let brown = Color(SystemColor.brown)
    public static let gray = Color(SystemColor.gray)
    public static let primary = Color(SystemColor.label)
    public static let secondary = Color(SystemColor.secondaryLabel)
    public static let accentColor = Color(.accent)

    package func rgba(in env: EnvironmentValues) -> RGBA { Color.resolve(storage, env) }

    private static func resolve(_ storage: Storage, _ env: EnvironmentValues) -> RGBA {
        switch storage {
        case .rgba(let c): return c
        case .dynamic(let d): return d.resolve(env.colorScheme)
        case .opacity(let base, let o): return resolve(base, env).opacity(o)
        case .mix(let a, let b, let t): return resolve(a, env).mix(resolve(b, env), t)
        case .accent: return (env.accentColor ?? Color.blue).rgba(in: env)
        case .named(let name):
            if let color = MainActor.assumeIsolated({ AssetCatalog.shared.color(named: name, scheme: env.colorScheme) }) { return color }
            MainActor.assumeIsolated { Runtime.current?.warn("Color asset \"\(name)\" not found; rendered as magenta") }
            return RGBA(1, 0, 1, 1)
        }
    }

    public struct Resolved: Hashable, Sendable {
        public var red: Float, green: Float, blue: Float, opacity: Float
        public init(colorSpace: RGBColorSpace = .sRGB, red: Float, green: Float, blue: Float, opacity: Float = 1) {
            self.red = red; self.green = green; self.blue = blue; self.opacity = opacity
        }
    }
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        let c = rgba(in: environment)
        return Resolved(red: Float(c.r), green: Float(c.g), blue: Float(c.b), opacity: Float(c.a))
    }
}

extension Color: CustomStringConvertible {
    public var description: String { "Color(\(storage))" }
}

// MARK: - Environment

enum ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }
enum AccentColorKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
    var accentColor: Color? {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

extension View {
    public func colorScheme(_ colorScheme: ColorScheme) -> some View { env { $0.colorScheme = colorScheme } }
    public func accentColor(_ accentColor: Color?) -> some View { env { $0.accentColor = accentColor } }
    public func tint(_ tint: Color?) -> some View { env { $0.accentColor = tint } }
}
