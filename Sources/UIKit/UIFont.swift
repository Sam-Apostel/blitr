// UIFont, UIFontDescriptor and UIFontMetrics. A UIFont is a description (family, size, weight,
// traits) that converts to a SwiftUI `Font`; its metrics come from the font file that would draw it.

import Foundation
import SwiftUI

open class UIFont: NSObject, @unchecked Sendable {
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
        init(value: CGFloat) {
            let table: [(CGFloat, Weight)] = [(100, .ultraLight), (200, .thin), (300, .light), (400, .regular), (500, .medium),
                                              (600, .semibold), (700, .bold), (800, .heavy), (900, .black)]
            self = table.min { abs($0.0 - value) < abs($1.0 - value) }!.1
        }
    }

    public struct Width: RawRepresentable, Hashable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let compressed = Width(rawValue: -0.8)
        public static let condensed = Width(rawValue: -0.2)
        public static let standard = Width(rawValue: 0)
        public static let expanded = Width(rawValue: 0.2)
    }

    public struct TextStyle: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let extraLargeTitle = TextStyle(rawValue: "UICTFontTextStyleExtraLargeTitle")
        public static let extraLargeTitle2 = TextStyle(rawValue: "UICTFontTextStyleExtraLargeTitle2")
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
            case .extraLargeTitle: return .extraLargeTitle
            case .extraLargeTitle2: return .extraLargeTitle2
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

    /// What the font is: everything `Font` and the metrics are derived from.
    struct Spec: Hashable {
        /// A registered or installed font's name; nil for the system font.
        var name: String?
        var design = Font.Design.default
        var size: CGFloat
        /// On the 100...900 scale.
        var weight: CGFloat = 400
        var italic = false
        var width: CGFloat = 0
        var monospacedDigits = false
    }
    let spec: Spec

    init(spec: Spec) {
        self.spec = spec
        super.init()
    }

    var font: Font {
        var result: Font
        if let name = spec.name {
            result = .custom(name, fixedSize: spec.size)
            if spec.weight >= 600 { result = result.bold() }
        } else {
            result = .system(size: spec.size, weight: Weight(value: spec.weight).swiftUI, design: spec.design)
        }
        if spec.italic { result = result.italic() }
        if spec.monospacedDigits { result = result.monospacedDigit() }
        if spec.width != 0 {
            result = result.width(spec.width <= -0.5 ? .compressed : spec.width < 0 ? .condensed : .expanded)
        }
        return result
    }

    /// (ascent, descent, capHeight, xHeight) as fractions of the point size.
    private var metrics: (ascent: CGFloat, descent: CGFloat, cap: CGFloat, x: CGFloat) {
        guard Thread.isMainThread else { return (0.952, 0.241, 0.705, 0.526) }
        let spec = spec
        let m = MainActor.assumeIsolated {
            _fontMetrics(name: spec.name, design: spec.design, size: spec.size, weight: spec.weight, italic: spec.italic, width: spec.width)
        }
        return (m.ascent, m.descent, m.capHeight, m.xHeight)
    }

    public var pointSize: CGFloat { spec.size }
    public var fontName: String {
        if let name = spec.name { return name }
        let face = spec.weight >= 600 ? "Bold" : spec.weight >= 500 ? "Medium" : "Regular"
        return spec.design == .monospaced ? ".SFNSMono-\(face)" : spec.design == .rounded ? ".SFUIRounded-\(face)"
            : spec.design == .serif ? ".NewYork-\(face)" : ".SFUI-\(face)"
    }
    public var familyName: String {
        if let name = spec.name { return name.split(separator: "-").first.map(String.init) ?? name }
        return spec.design == .monospaced ? ".AppleSystemUIFontMonospaced" : spec.design == .rounded ? ".AppleSystemUIFontRounded"
            : spec.design == .serif ? ".AppleSystemUIFontSerif" : ".AppleSystemUIFont"
    }
    public var ascender: CGFloat { metrics.ascent * spec.size }
    /// Negative, as in UIKit.
    public var descender: CGFloat { -metrics.descent * spec.size }
    public var capHeight: CGFloat { metrics.cap * spec.size }
    public var xHeight: CGFloat { metrics.x * spec.size }
    public var lineHeight: CGFloat { (metrics.ascent + metrics.descent) * spec.size }
    public var leading: CGFloat { 0 }
    public var fontDescriptor: UIFontDescriptor { UIFontDescriptor(spec: spec) }

    // MARK: Creation

    public static func systemFont(ofSize size: CGFloat) -> UIFont { UIFont(spec: Spec(size: size)) }
    public static func systemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(spec: Spec(size: size, weight: weight.swiftUI.value))
    }
    public static func systemFont(ofSize size: CGFloat, weight: Weight, width: Width) -> UIFont {
        UIFont(spec: Spec(size: size, weight: weight.swiftUI.value, width: width.rawValue))
    }
    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont { UIFont(spec: Spec(size: size, weight: 700)) }
    public static func italicSystemFont(ofSize size: CGFloat) -> UIFont { UIFont(spec: Spec(size: size, italic: true)) }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(spec: Spec(design: .monospaced, size: size, weight: weight.swiftUI.value))
    }
    public static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(spec: Spec(size: size, weight: weight.swiftUI.value, monospacedDigits: true))
    }
    /// The text style at the Dynamic Type size being rendered.
    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont {
        let s = style.swiftUI
        let env = EnvironmentValues()
        let m = s.metrics(for: env.renderPlatform)
        return UIFont(spec: Spec(size: (m.size * env.dynamicTypeSize.scale(for: s)).rounded(), weight: m.weight.value))
    }
    public static func preferredFont(forTextStyle style: TextStyle, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        preferredFont(forTextStyle: style)
    }

    /// Nil when no font of that name is registered or installed, as in UIKit.
    public convenience init?(name: String, size: CGFloat) {
        if Thread.isMainThread, !MainActor.assumeIsolated({ _hasCustomFont(named: name) }) { return nil }
        self.init(spec: Spec(name: name, size: size))
    }
    /// A `size` of 0 keeps the descriptor's size.
    public convenience init(descriptor: UIFontDescriptor, size: CGFloat) {
        var spec = descriptor.spec
        if size != 0 { spec.size = size }
        self.init(spec: spec)
    }

    public func withSize(_ size: CGFloat) -> UIFont {
        var copy = spec
        copy.size = size
        return UIFont(spec: copy)
    }

    public class var labelFontSize: CGFloat { 17 }
    public class var buttonFontSize: CGFloat { 18 }
    public class var smallSystemFontSize: CGFloat { 12 }
    public class var systemFontSize: CGFloat { 14 }
    public class var familyNames: [String] { [] }
    public class func fontNames(forFamilyName familyName: String) -> [String] { [] }

    open override func isEqual(_ object: Any?) -> Bool { (object as? UIFont)?.spec == spec }
    open override var hash: Int { spec.hashValue }
}

extension Font {
    public init(_ font: UIFont) { self = font.font }
}

open class UIFontDescriptor: NSObject, @unchecked Sendable {
    public struct SymbolicTraits: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let traitItalic = SymbolicTraits(rawValue: 1 << 0)
        public static let traitBold = SymbolicTraits(rawValue: 1 << 1)
        public static let traitExpanded = SymbolicTraits(rawValue: 1 << 5)
        public static let traitCondensed = SymbolicTraits(rawValue: 1 << 6)
        public static let traitMonoSpace = SymbolicTraits(rawValue: 1 << 10)
        public static let traitVertical = SymbolicTraits(rawValue: 1 << 11)
        public static let traitUIOptimized = SymbolicTraits(rawValue: 1 << 12)
        public static let traitTightLeading = SymbolicTraits(rawValue: 1 << 15)
        public static let traitLooseLeading = SymbolicTraits(rawValue: 1 << 16)
        public static let classMask = SymbolicTraits(rawValue: 0xF000_0000)
    }
    public struct SystemDesign: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = SystemDesign(rawValue: "NSCTFontUIFontDesignDefault")
        public static let rounded = SystemDesign(rawValue: "NSCTFontUIFontDesignRounded")
        public static let serif = SystemDesign(rawValue: "NSCTFontUIFontDesignSerif")
        public static let monospaced = SystemDesign(rawValue: "NSCTFontUIFontDesignMonospaced")
    }
    public struct AttributeName: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let family = AttributeName(rawValue: "NSFontFamilyAttribute")
        public static let name = AttributeName(rawValue: "NSFontNameAttribute")
        public static let face = AttributeName(rawValue: "NSFontFaceAttribute")
        public static let size = AttributeName(rawValue: "NSFontSizeAttribute")
        public static let traits = AttributeName(rawValue: "NSCTFontTraitsAttribute")
        public static let featureSettings = AttributeName(rawValue: "NSCTFontFeatureSettingsAttribute")
        public static let textStyle = AttributeName(rawValue: "NSCTFontUIUsageAttribute")
    }
    public struct TraitKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let symbolic = TraitKey(rawValue: "NSCTFontSymbolicTrait")
        public static let weight = TraitKey(rawValue: "NSCTFontWeightTrait")
        public static let width = TraitKey(rawValue: "NSCTFontProportionTrait")
        public static let slant = TraitKey(rawValue: "NSCTFontSlantTrait")
    }

    let spec: UIFont.Spec
    init(spec: UIFont.Spec) { self.spec = spec; super.init() }

    public convenience init(name: String, size: CGFloat) { self.init(spec: UIFont.Spec(name: name, size: size)) }
    public convenience init(fontAttributes attributes: [AttributeName: Any] = [:]) {
        var spec = UIFont.Spec(size: 0)
        spec.name = (attributes[.name] as? String) ?? (attributes[.family] as? String)
        if let size = _cfNumber(attributes[.size]) { spec.size = CGFloat(size) }
        self.init(spec: spec)
    }
    public class func preferredFontDescriptor(withTextStyle style: UIFont.TextStyle) -> UIFontDescriptor {
        UIFont.preferredFont(forTextStyle: style).fontDescriptor
    }
    public class func preferredFontDescriptor(withTextStyle style: UIFont.TextStyle, compatibleWith traitCollection: UITraitCollection?) -> UIFontDescriptor {
        preferredFontDescriptor(withTextStyle: style)
    }

    public var pointSize: CGFloat { spec.size }
    public var postscriptName: String { UIFont(spec: spec).fontName }
    public var symbolicTraits: SymbolicTraits {
        var traits: SymbolicTraits = []
        if spec.italic { traits.insert(.traitItalic) }
        if spec.weight >= 600 { traits.insert(.traitBold) }
        if spec.design == .monospaced { traits.insert(.traitMonoSpace) }
        if spec.width > 0 { traits.insert(.traitExpanded) }
        if spec.width < 0 { traits.insert(.traitCondensed) }
        return traits
    }
    public var fontAttributes: [AttributeName: Any] {
        var attributes: [AttributeName: Any] = [.size: NSNumber(value: Double(spec.size))]
        if let name = spec.name { attributes[.name] = name }
        return attributes
    }
    public func object(forKey key: AttributeName) -> Any? { fontAttributes[key] }

    private func with(_ change: (inout UIFont.Spec) -> Void) -> UIFontDescriptor {
        var copy = spec
        change(&copy)
        return UIFontDescriptor(spec: copy)
    }
    /// Sets exactly these traits (bold, italic, monospace, width).
    public func withSymbolicTraits(_ traits: SymbolicTraits) -> UIFontDescriptor? {
        with { s in
            s.italic = traits.contains(.traitItalic)
            if traits.contains(.traitBold) { s.weight = max(s.weight, 700) } else if s.weight >= 600 { s.weight = 400 }
            if traits.contains(.traitMonoSpace) { s.design = .monospaced; s.name = nil } else if s.design == .monospaced { s.design = .default }
            s.width = traits.contains(.traitExpanded) ? 0.2 : traits.contains(.traitCondensed) ? -0.2 : 0
        }
    }
    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
        with { s in
            s.name = nil
            s.design = design == .rounded ? .rounded : design == .serif ? .serif : design == .monospaced ? .monospaced : .default
        }
    }
    public func withSize(_ size: CGFloat) -> UIFontDescriptor { with { $0.size = size } }
    public func withFamily(_ family: String) -> UIFontDescriptor { with { $0.name = family } }
    public func withFace(_ face: String) -> UIFontDescriptor {
        with { s in
            let lower = face.lowercased()
            s.italic = lower.contains("italic") || lower.contains("oblique")
            if lower.contains("bold") { s.weight = 700 }
        }
    }
    public func addingAttributes(_ attributes: [AttributeName: Any] = [:]) -> UIFontDescriptor {
        with { s in
            if let name = (attributes[.name] as? String) ?? (attributes[.family] as? String) { s.name = name }
            if let size = _cfNumber(attributes[.size]) { s.size = CGFloat(size) }
            if let traits = attributes[.traits] as? [TraitKey: Any], let weight = traits[.weight] {
                let raw = (weight as? UIFont.Weight)?.rawValue ?? _cfNumber(weight).map { CGFloat($0) }
                if let raw { s.weight = UIFont.Weight(raw).swiftUI.value }
            }
        }
    }
    public func matchingFontDescriptors(withMandatoryKeys keys: Set<AttributeName>?) -> [UIFontDescriptor] { [self] }

    open override func isEqual(_ object: Any?) -> Bool { (object as? UIFontDescriptor)?.spec == spec }
    open override var hash: Int { spec.hashValue }
}

/// Scales fonts and values with the Dynamic Type size being rendered (`--dynamic-type`).
public final class UIFontMetrics: NSObject, @unchecked Sendable {
    let style: UIFont.TextStyle
    public init(forTextStyle textStyle: UIFont.TextStyle) { style = textStyle; super.init() }
    public static let `default` = UIFontMetrics(forTextStyle: .body)

    private var factor: CGFloat { EnvironmentValues().dynamicTypeSize.scale(for: style.swiftUI) }

    public func scaledValue(for value: CGFloat) -> CGFloat { (value * factor * 3).rounded() / 3 }
    public func scaledValue(for value: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> CGFloat { scaledValue(for: value) }
    public func scaledFont(for font: UIFont) -> UIFont { font.withSize((font.pointSize * factor).rounded()) }
    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat) -> UIFont {
        font.withSize(min((font.pointSize * factor).rounded(), maximumPointSize))
    }
    public func scaledFont(for font: UIFont, compatibleWith traitCollection: UITraitCollection?) -> UIFont { scaledFont(for: font) }
    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        scaledFont(for: font, maximumPointSize: maximumPointSize)
    }
}
