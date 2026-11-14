// CGColorSpace and CGColor. Everything is drawn in sRGB: other RGB spaces keep their name but
// their components are used as sRGB values (linear spaces are gamma-encoded, Display P3 is clamped).

public enum CGColorSpaceModel: Int32, Sendable {
    case unknown = -1, monochrome, rgb, cmyk, lab, deviceN, indexed, pattern, XYZ
}

public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

public final class CGColorSpace: Hashable, @unchecked Sendable {
    public let name: CFString?
    public let model: CGColorSpaceModel

    init(model: CGColorSpaceModel, name: CFString?) { self.model = model; self.name = name }

    public init?(name: CFString) {
        let n = name as String
        guard CGColorSpace.knownNames.contains(n) else { return nil }
        self.name = name
        model = n.contains("Gray") ? .monochrome : n.contains("CMYK") ? .cmyk : n.contains("Lab") ? .lab : n.contains("XYZ") ? .XYZ : .rgb
    }

    public var numberOfComponents: Int {
        switch model {
        case .monochrome: return 1
        case .cmyk: return 4
        default: return 3
        }
    }
    public var isWideGamutRGB: Bool { ((name as String?) ?? "").contains("P3") || ((name as String?) ?? "").contains("2020") }
    public var supportsOutput: Bool { true }
    package var isLinear: Bool { ((name as String?) ?? "").contains("Linear") }

    public static func == (a: CGColorSpace, b: CGColorSpace) -> Bool { a.model == b.model && a.name == b.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(model); hasher.combine(name) }

    public static let sRGB: CFString = "kCGColorSpaceSRGB"
    public static let extendedSRGB: CFString = "kCGColorSpaceExtendedSRGB"
    public static let linearSRGB: CFString = "kCGColorSpaceLinearSRGB"
    public static let extendedLinearSRGB: CFString = "kCGColorSpaceExtendedLinearSRGB"
    public static let genericRGBLinear: CFString = "kCGColorSpaceGenericRGBLinear"
    public static let displayP3: CFString = "kCGColorSpaceDisplayP3"
    public static let extendedDisplayP3: CFString = "kCGColorSpaceExtendedDisplayP3"
    public static let linearDisplayP3: CFString = "kCGColorSpaceLinearDisplayP3"
    public static let adobeRGB1998: CFString = "kCGColorSpaceAdobeRGB1998"
    public static let itur_709: CFString = "kCGColorSpaceITUR_709"
    public static let itur_2020: CFString = "kCGColorSpaceITUR_2020"
    public static let genericGrayGamma2_2: CFString = "kCGColorSpaceGenericGrayGamma2_2"
    public static let extendedGray: CFString = "kCGColorSpaceExtendedGray"
    public static let linearGray: CFString = "kCGColorSpaceLinearGray"
    public static let extendedLinearGray: CFString = "kCGColorSpaceExtendedLinearGray"
    public static let genericCMYK: CFString = "kCGColorSpaceGenericCMYK"
    public static let genericXYZ: CFString = "kCGColorSpaceGenericXYZ"
    public static let genericLab: CFString = "kCGColorSpaceGenericLab"

    private static let knownNames: Set<String> = Set([
        sRGB, extendedSRGB, linearSRGB, extendedLinearSRGB, genericRGBLinear, displayP3, extendedDisplayP3, linearDisplayP3,
        adobeRGB1998, itur_709, itur_2020, genericGrayGamma2_2, extendedGray, linearGray, extendedLinearGray,
        genericCMYK, genericXYZ, genericLab,
    ].map { $0 as String })

    package static let deviceRGB = CGColorSpace(model: .rgb, name: "kCGColorSpaceDeviceRGB")
    package static let deviceGray = CGColorSpace(model: .monochrome, name: "kCGColorSpaceDeviceGray")
    package static let deviceCMYK = CGColorSpace(model: .cmyk, name: "kCGColorSpaceDeviceCMYK")
    package static let srgb = CGColorSpace(model: .rgb, name: sRGB)
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { .deviceRGB }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { .deviceGray }
public func CGColorSpaceCreateDeviceCMYK() -> CGColorSpace { .deviceCMYK }

public final class CGColor: Hashable, @unchecked Sendable {
    /// sRGB components, what the color draws as.
    package let rgba: (r: Double, g: Double, b: Double, a: Double)
    public let colorSpace: CGColorSpace?
    /// The color's components in its color space, alpha last.
    public let components: [CGFloat]?

    package init(r: Double, g: Double, b: Double, a: Double) {
        rgba = (r, g, b, a)
        colorSpace = .srgb
        components = [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)]
    }
    private init(rgba: (r: Double, g: Double, b: Double, a: Double), space: CGColorSpace, components: [CGFloat]) {
        self.rgba = rgba; colorSpace = space; self.components = components
    }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(rgba: (Double(red), Double(green), Double(blue), Double(alpha)), space: .deviceRGB, components: [red, green, blue, alpha])
    }
    public convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
    }
    public convenience init(gray: CGFloat, alpha: CGFloat) {
        self.init(rgba: (Double(gray), Double(gray), Double(gray), Double(alpha)), space: .deviceGray, components: [gray, alpha])
    }
    public convenience init(genericGrayGamma2_2Gray gray: CGFloat, alpha: CGFloat) {
        self.init(rgba: (Double(gray), Double(gray), Double(gray), Double(alpha)),
                  space: CGColorSpace(model: .monochrome, name: CGColorSpace.genericGrayGamma2_2), components: [gray, alpha])
    }
    public convenience init(genericCMYKCyan cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) {
        self.init(rgba: CGColor.rgba(space: .deviceCMYK, [cyan, magenta, yellow, black, alpha]), space: .deviceCMYK,
                  components: [cyan, magenta, yellow, black, alpha])
    }
    /// `components` holds the color space's components followed by alpha.
    public convenience init?(colorSpace space: CGColorSpace, components: UnsafePointer<CGFloat>) {
        let list = Array(UnsafeBufferPointer(start: components, count: space.numberOfComponents + 1))
        self.init(rgba: CGColor.rgba(space: space, list), space: space, components: list)
    }

    package static func rgba(space: CGColorSpace, _ c: [CGFloat]) -> (r: Double, g: Double, b: Double, a: Double) {
        func encode(_ v: Double) -> Double {
            guard space.isLinear else { return v }
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        switch space.model {
        case .monochrome:
            return (encode(Double(c[0])), encode(Double(c[0])), encode(Double(c[0])), Double(c[1]))
        case .cmyk:
            let k = 1 - Double(c[3])
            return ((1 - Double(c[0])) * k, (1 - Double(c[1])) * k, (1 - Double(c[2])) * k, Double(c[4]))
        default:
            return (encode(Double(c[0])), encode(Double(c[1])), encode(Double(c[2])), Double(c[3]))
        }
    }

    public var alpha: CGFloat { CGFloat(rgba.a) }
    public var numberOfComponents: Int { components?.count ?? 0 }

    public func copy() -> CGColor? { self }
    public func copy(alpha: CGFloat) -> CGColor? {
        var list = components ?? []
        if !list.isEmpty { list[list.count - 1] = alpha }
        return CGColor(rgba: (rgba.r, rgba.g, rgba.b, Double(alpha)), space: colorSpace ?? .srgb, components: list)
    }
    public func converted(to space: CGColorSpace, intent: CGColorRenderingIntent, options: CFDictionary?) -> CGColor? {
        func decode(_ v: Double) -> CGFloat {
            guard space.isLinear else { return CGFloat(v) }
            return CGFloat(v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
        }
        switch space.model {
        case .monochrome:
            return CGColor(rgba: rgba, space: space, components: [decode(0.2126 * rgba.r + 0.7152 * rgba.g + 0.0722 * rgba.b), CGFloat(rgba.a)])
        case .rgb:
            return CGColor(rgba: rgba, space: space, components: [decode(rgba.r), decode(rgba.g), decode(rgba.b), CGFloat(rgba.a)])
        case .cmyk:
            let k = 1 - max(rgba.r, rgba.g, rgba.b)
            let d = max(1 - k, 0.000001)
            return CGColor(rgba: rgba, space: space, components: [CGFloat((1 - rgba.r - k) / d), CGFloat((1 - rgba.g - k) / d),
                                                                  CGFloat((1 - rgba.b - k) / d), CGFloat(k), CGFloat(rgba.a)])
        default:
            return nil
        }
    }

    public static func == (a: CGColor, b: CGColor) -> Bool { a.rgba == b.rgba && a.colorSpace == b.colorSpace }
    public func hash(into hasher: inout Hasher) { hasher.combine(rgba.r); hasher.combine(rgba.g); hasher.combine(rgba.b); hasher.combine(rgba.a) }

    public static let black = CGColor(gray: 0, alpha: 1)
    public static let white = CGColor(gray: 1, alpha: 1)
    public static let clear = CGColor(gray: 0, alpha: 0)
}

