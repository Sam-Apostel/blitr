// UIColor / UIImage / UIFont: the value types app code passes into SwiftUI.
// They live in the SwiftUI module so `Color(.systemBackground)` works with only `import SwiftUI`.

public enum UIUserInterfaceStyle: Int, Hashable, Sendable { case unspecified, light, dark }
public enum UIUserInterfaceSizeClass: Int, Hashable, Sendable { case unspecified, compact, regular }
public enum UIUserInterfaceIdiom: Int, Hashable, Sendable { case unspecified = -1, phone, pad, tv, carPlay, mac, vision }

public class UITraitCollection {
    public var userInterfaceStyle: UIUserInterfaceStyle
    public var horizontalSizeClass: UIUserInterfaceSizeClass
    public var verticalSizeClass: UIUserInterfaceSizeClass
    public var displayScale: CGFloat
    public var userInterfaceIdiom: UIUserInterfaceIdiom

    public init(userInterfaceStyle: UIUserInterfaceStyle) {
        let config = _currentConfiguration()
        self.userInterfaceStyle = userInterfaceStyle
        horizontalSizeClass = _currentSizeClass(horizontal: true) == .regular ? .regular : .compact
        verticalSizeClass = _currentSizeClass(horizontal: false) == .regular ? .regular : .compact
        displayScale = config.scale ?? config.device.scale
        userInterfaceIdiom = config.device.idiom == .pad ? .pad : .phone
    }
    public convenience init() { self.init(userInterfaceStyle: .unspecified) }

    public static var current: UITraitCollection {
        UITraitCollection(userInterfaceStyle: _currentConfiguration().colorScheme == .dark ? .dark : .light)
    }
}

public final class UIColor: Hashable {
    let dynamic: DynamicColor

    init(_ dynamic: DynamicColor) { self.dynamic = dynamic }
    convenience init(_ rgba: RGBA) { self.init(DynamicColor(light: rgba, dark: rgba)) }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(RGBA(Double(red), Double(green), Double(blue), Double(alpha)))
    }
    public convenience init(white: CGFloat, alpha: CGFloat) { self.init(red: white, green: white, blue: white, alpha: alpha) }
    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let c = Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
        self.init(c.rgba(in: EnvironmentValues()))
    }
    public convenience init(_ color: Color) {
        var light = EnvironmentValues(), dark = EnvironmentValues()
        light.colorScheme = .light
        dark.colorScheme = .dark
        self.init(DynamicColor(light: color.rgba(in: light), dark: color.rgba(in: dark)))
    }
    public convenience init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) {
        let light = dynamicProvider(UITraitCollection(userInterfaceStyle: .light)).dynamic.light
        let dark = dynamicProvider(UITraitCollection(userInterfaceStyle: .dark)).dynamic.dark
        self.init(DynamicColor(light: light, dark: dark))
    }
    /// Colors from an asset catalog (pass `--assets`); a missing color renders magenta.
    public convenience init?(named name: String) {
        let found = MainActor.assumeIsolated { () -> DynamicColor? in
            guard let light = AssetCatalog.shared.color(named: name, scheme: .light) else { return nil }
            return DynamicColor(light: light, dark: AssetCatalog.shared.color(named: name, scheme: .dark) ?? light)
        }
        self.init(found ?? DynamicColor(light: RGBA(1, 0, 1, 1), dark: RGBA(1, 0, 1, 1)))
    }

    public func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        UIColor(DynamicColor(light: dynamic.light.withAlpha(Double(alpha)), dark: dynamic.dark.withAlpha(Double(alpha))))
    }
    public func resolvedColor(with traitCollection: UITraitCollection) -> UIColor {
        UIColor(traitCollection.userInterfaceStyle == .dark ? dynamic.dark : dynamic.light)
    }
    @discardableResult
    public func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?,
                       blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        let c = dynamic.light
        red?.pointee = CGFloat(c.r); green?.pointee = CGFloat(c.g); blue?.pointee = CGFloat(c.b); alpha?.pointee = CGFloat(c.a)
        return true
    }
    @discardableResult
    public func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        white?.pointee = CGFloat(dynamic.light.luminance); alpha?.pointee = CGFloat(dynamic.light.a)
        return true
    }

    public static func == (a: UIColor, b: UIColor) -> Bool { a.dynamic == b.dynamic }
    public func hash(into hasher: inout Hasher) { hasher.combine(dynamic) }

    // Fixed colors
    public static var black: UIColor { UIColor(RGBA.black) }
    public static var white: UIColor { UIColor(RGBA.white) }
    public static var clear: UIColor { UIColor(RGBA.clear) }
    public static var red: UIColor { UIColor(RGBA(1, 0, 0)) }
    public static var green: UIColor { UIColor(RGBA(0, 1, 0)) }
    public static var blue: UIColor { UIColor(RGBA(0, 0, 1)) }
    public static var cyan: UIColor { UIColor(RGBA(0, 1, 1)) }
    public static var yellow: UIColor { UIColor(RGBA(1, 1, 0)) }
    public static var magenta: UIColor { UIColor(RGBA(1, 0, 1)) }
    public static var orange: UIColor { UIColor(RGBA(1, 0.5, 0)) }
    public static var purple: UIColor { UIColor(RGBA(0.5, 0, 0.5)) }
    public static var brown: UIColor { UIColor(RGBA(0.6, 0.4, 0.2)) }
    public static var gray: UIColor { UIColor(RGBA(0.5, 0.5, 0.5)) }
    public static var darkGray: UIColor { UIColor(RGBA(1.0 / 3, 1.0 / 3, 1.0 / 3)) }
    public static var lightGray: UIColor { UIColor(RGBA(2.0 / 3, 2.0 / 3, 2.0 / 3)) }

    // Adaptive system colors
    public static var systemRed: UIColor { UIColor(SystemColor.red) }
    public static var systemOrange: UIColor { UIColor(SystemColor.orange) }
    public static var systemYellow: UIColor { UIColor(SystemColor.yellow) }
    public static var systemGreen: UIColor { UIColor(SystemColor.green) }
    public static var systemMint: UIColor { UIColor(SystemColor.mint) }
    public static var systemTeal: UIColor { UIColor(SystemColor.teal) }
    public static var systemCyan: UIColor { UIColor(SystemColor.cyan) }
    public static var systemBlue: UIColor { UIColor(SystemColor.blue) }
    public static var systemIndigo: UIColor { UIColor(SystemColor.indigo) }
    public static var systemPurple: UIColor { UIColor(SystemColor.purple) }
    public static var systemPink: UIColor { UIColor(SystemColor.pink) }
    public static var systemBrown: UIColor { UIColor(SystemColor.brown) }
    public static var systemGray: UIColor { UIColor(SystemColor.gray) }
    public static var systemGray2: UIColor { UIColor(SystemColor.gray2) }
    public static var systemGray3: UIColor { UIColor(SystemColor.gray3) }
    public static var systemGray4: UIColor { UIColor(SystemColor.gray4) }
    public static var systemGray5: UIColor { UIColor(SystemColor.gray5) }
    public static var systemGray6: UIColor { UIColor(SystemColor.gray6) }
    public static var tintColor: UIColor { UIColor(SystemColor.blue) }

    public static var label: UIColor { UIColor(SystemColor.label) }
    public static var secondaryLabel: UIColor { UIColor(SystemColor.secondaryLabel) }
    public static var tertiaryLabel: UIColor { UIColor(SystemColor.tertiaryLabel) }
    public static var quaternaryLabel: UIColor { UIColor(SystemColor.quaternaryLabel) }
    public static var placeholderText: UIColor { UIColor(SystemColor.placeholderText) }
    public static var separator: UIColor { UIColor(SystemColor.separator) }
    public static var opaqueSeparator: UIColor { UIColor(SystemColor.opaqueSeparator) }
    public static var link: UIColor { UIColor(SystemColor.link) }
    public static var systemBackground: UIColor { UIColor(SystemColor.background) }
    public static var secondarySystemBackground: UIColor { UIColor(SystemColor.secondaryBackground) }
    public static var tertiarySystemBackground: UIColor { UIColor(SystemColor.tertiaryBackground) }
    public static var systemGroupedBackground: UIColor { UIColor(SystemColor.groupedBackground) }
    public static var secondarySystemGroupedBackground: UIColor { UIColor(SystemColor.secondaryGroupedBackground) }
    public static var tertiarySystemGroupedBackground: UIColor { UIColor(SystemColor.tertiaryGroupedBackground) }
    public static var systemFill: UIColor { UIColor(SystemColor.fill) }
    public static var secondarySystemFill: UIColor { UIColor(SystemColor.secondaryFill) }
    public static var tertiarySystemFill: UIColor { UIColor(SystemColor.tertiaryFill) }
    public static var quaternarySystemFill: UIColor { UIColor(SystemColor.quaternaryFill) }
}

extension DynamicColor {
    init(light: RGBA, dark: RGBA) {
        self.init(0, 0)
        self.light = light
        self.dark = dark
    }
}
extension RGBA {
    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
}

extension Color {
    public init(_ color: UIColor) { self.init(color.dynamic) }
    public init(uiColor: UIColor) { self.init(uiColor.dynamic) }
}

// MARK: - UIImage

public class UIImage {
    public enum RenderingMode: Int, Sendable { case automatic, alwaysOriginal, alwaysTemplate }
    public class Configuration { public init() {} }
    public class SymbolConfiguration: Configuration {
        public enum Scale: Int, Sendable { case unspecified = -1, `default` = 0, small = 1, medium = 2, large = 3 }
        public init(pointSize: CGFloat, weight: UIFont.Weight = .regular, scale: Scale = .default) { super.init() }
        public init(weight: UIFont.Weight) { super.init() }
        public init(scale: Scale) { super.init() }
        public init(font: UIFont) { super.init() }
        public init(textStyle: UIFont.TextStyle) { super.init() }
    }

    let source: Image.Source
    var template = false
    public var renderingMode: RenderingMode { template ? .alwaysTemplate : .automatic }
    public var scale: CGFloat {
        if case .rendered(let rendered) = source { return rendered.scale }
        return _currentConfiguration().scale ?? _currentConfiguration().device.scale
    }
    public var size: CGSize {
        if case .rendered(let rendered) = source { return rendered.bitmap.pointSize }
        guard case .named(let name) = source else { return .zero }
        return MainActor.assumeIsolated { AssetCatalog.shared.bitmap(named: name, scheme: .light)?.pointSize ?? .zero }
    }

    init(source: Image.Source) { self.source = source }
    public convenience init() { self.init(source: .named("")) }
    /// Always succeeds: a missing asset renders as a visible placeholder (with a warning) instead of nothing.
    public convenience init?(named name: String) { self.init(source: .named(name)) }
    public convenience init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) { self.init(source: .named(name)) }
    public convenience init?(systemName name: String) { self.init(source: .system(name)) }
    public convenience init?(systemName name: String, withConfiguration configuration: Configuration?) { self.init(source: .system(name)) }
    public convenience init?(data: Data) { return nil }
    public convenience init?(contentsOfFile path: String) { return nil }

    public func withRenderingMode(_ mode: RenderingMode) -> UIImage {
        let copy = UIImage(source: source)
        copy.template = mode == .alwaysTemplate
        return copy
    }
    public func withTintColor(_ color: UIColor) -> UIImage { withRenderingMode(.alwaysTemplate) }
    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode) -> UIImage { withRenderingMode(renderingMode) }
    public func withConfiguration(_ configuration: Configuration) -> UIImage { self }
    public func applyingSymbolConfiguration(_ configuration: Configuration) -> UIImage? { self }
}

extension Image {
    public init(uiImage: UIImage) {
        self.init("")
        source = uiImage.source
        if uiImage.template { renderingMode = .template }
    }
}

// MARK: - UIFont

public class UIFont {
    public struct Weight: RawRepresentable, Hashable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(-0.8)
        public static let thin = Weight(-0.6)
        public static let light = Weight(-0.4)
        public static let regular = Weight(0)
        public static let medium = Weight(0.23)
        public static let semibold = Weight(0.3)
        public static let bold = Weight(0.4)
        public static let heavy = Weight(0.56)
        public static let black = Weight(0.62)
        var swiftUI: Font.Weight {
            switch rawValue {
            case ..<(-0.7): return .ultraLight
            case ..<(-0.5): return .thin
            case ..<(-0.2): return .light
            case ..<0.115: return .regular
            case ..<0.265: return .medium
            case ..<0.35: return .semibold
            case ..<0.48: return .bold
            case ..<0.59: return .heavy
            default: return .black
            }
        }
    }

    public struct TextStyle: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let largeTitle = TextStyle(rawValue: "UICTFontTextStyleTitle0")
        public static let title1 = TextStyle(rawValue: "UICTFontTextStyleTitle1")
        public static let title2 = TextStyle(rawValue: "UICTFontTextStyleTitle2")
        public static let title3 = TextStyle(rawValue: "UICTFontTextStyleTitle3")
        public static let headline = TextStyle(rawValue: "UICTFontTextStyleHeadline")
        public static let subheadline = TextStyle(rawValue: "UICTFontTextStyleSubhead")
        public static let body = TextStyle(rawValue: "UICTFontTextStyleBody")
        public static let callout = TextStyle(rawValue: "UICTFontTextStyleCallout")
        public static let footnote = TextStyle(rawValue: "UICTFontTextStyleFootnote")
        public static let caption1 = TextStyle(rawValue: "UICTFontTextStyleCaption1")
        public static let caption2 = TextStyle(rawValue: "UICTFontTextStyleCaption2")
        var swiftUI: Font.TextStyle {
            switch self {
            case .largeTitle: return .largeTitle
            case .title1: return .title
            case .title2: return .title2
            case .title3: return .title3
            case .headline: return .headline
            case .subheadline: return .subheadline
            case .callout: return .callout
            case .footnote: return .footnote
            case .caption1: return .caption
            case .caption2: return .caption2
            default: return .body
            }
        }
    }

    let font: Font
    public let pointSize: CGFloat
    public let fontName: String
    public var familyName: String { fontName }
    public var lineHeight: CGFloat { (pointSize * 1.2).rounded(.up) }

    init(font: Font, pointSize: CGFloat, name: String) {
        self.font = font
        self.pointSize = pointSize
        fontName = name
    }

    public static func systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(font: .system(size: size), pointSize: size, name: ".SFUI-Regular")
    }
    public static func systemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(font: .system(size: size, weight: weight.swiftUI), pointSize: size, name: ".SFUI-Regular")
    }
    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(font: .system(size: size, weight: .bold), pointSize: size, name: ".SFUI-Bold")
    }
    public static func italicSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(font: Font.system(size: size).italic(), pointSize: size, name: ".SFUI-Italic")
    }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(font: .system(size: size, weight: weight.swiftUI, design: .monospaced), pointSize: size, name: ".SFNSMono-Regular")
    }
    public static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(font: Font.system(size: size, weight: weight.swiftUI).monospacedDigit(), pointSize: size, name: ".SFUI-Regular")
    }
    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont {
        let s = style.swiftUI
        return UIFont(font: .system(s), pointSize: s.metrics.size, name: ".SFUI-Regular")
    }
    public convenience init?(name: String, size: CGFloat) {
        self.init(font: .custom(name, size: size), pointSize: size, name: name)
    }
    public func withSize(_ size: CGFloat) -> UIFont { UIFont(font: font, pointSize: size, name: fontName) }
}

extension Font {
    public init(_ font: UIFont) { self = font.font }
}
