// The public Font type and its resolution to a concrete face + size.

public struct Font: Hashable, Sendable {
    public struct Weight: Hashable, Sendable {
        package let value: CGFloat
        public static let ultraLight = Weight(value: 100)
        public static let thin = Weight(value: 200)
        public static let light = Weight(value: 300)
        public static let regular = Weight(value: 400)
        public static let medium = Weight(value: 500)
        public static let semibold = Weight(value: 600)
        public static let bold = Weight(value: 700)
        public static let heavy = Weight(value: 800)
        public static let black = Weight(value: 900)
    }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum TextStyle: Hashable, CaseIterable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
        case extraLargeTitle, extraLargeTitle2
        /// tvOS text styles are sized for viewing from across a room (values from the tvOS
        /// typography table in Apple's Human Interface Guidelines; largeTitle is an estimate).
        var tvMetrics: (size: CGFloat, weight: Weight) {
            switch self {
            case .extraLargeTitle: return (96, .bold)
            case .extraLargeTitle2: return (86, .bold)
            case .largeTitle: return (76, .medium)
            case .title: return (76, .medium)
            case .title2: return (57, .medium)
            case .title3: return (48, .medium)
            case .headline: return (38, .medium)
            case .subheadline: return (38, .regular)
            case .callout: return (31, .medium)
            case .body: return (29, .medium)
            case .footnote: return (23, .medium)
            case .caption: return (25, .medium)
            case .caption2: return (23, .medium)
            }
        }
        /// watchOS text styles at the watch's default text size: Large on the 42mm screen, Extra Large
        /// on the 46mm and 49mm ones (Apple's watchOS typography table; callout and subheadline, which
        /// the table leaves out, are estimates).
        func watchMetrics(extraLarge: Bool) -> (size: CGFloat, weight: Weight) {
            let d: CGFloat = extraLarge ? 1 : 0
            if RenderedPlatform.current >= 26 {
                // measured: watchOS 26.5 simulator (Examples/Watch.swift "Text styles", SF Compact): title is 34pt
                // on the 42mm screen and 38pt on the 46mm and 49mm ones, caption 2 is 14pt and 15pt.
                switch self {
                case .title: return (34 + d * 4, .regular)
                case .caption2: return (14 + d, .regular)
                default: break
                }
            }
            switch self {
            case .extraLargeTitle: return (36 + d * 2, .bold)
            case .extraLargeTitle2: return (32 + d * 2, .bold)
            case .largeTitle: return (32 + d * 2, .regular)
            case .title: return (30 + d * 2, .regular)
            case .title2: return (24 + d * 2, .regular)
            case .title3: return (19 + d, .regular)
            case .headline: return (16 + d, .semibold)
            case .body: return (16 + d, .regular)
            case .callout: return (15 + d, .regular)
            case .subheadline: return (15 + d, .regular)
            case .footnote: return (13 + d, .regular)
            case .caption: return (13 + d, .regular)
            case .caption2: return (12 + d, .regular)
            }
        }
        package func metrics(for platform: RenderPlatform) -> (size: CGFloat, weight: Weight) {
            switch platform {
            case .tvOS: return tvMetrics
            case .watchOS: return watchMetrics(extraLarge: RenderedPlatform.watchTextIsExtraLarge)
            default: return metrics
            }
        }
        /// Point size and default weight at the standard Dynamic Type size (Large).
        package var metrics: (size: CGFloat, weight: Weight) {
            switch self {
            case .extraLargeTitle: return (36, .bold)
            case .extraLargeTitle2: return (28, .bold)
            case .largeTitle: return (34, .regular)
            case .title: return (28, .regular)
            case .title2: return (22, .regular)
            case .title3: return (20, .regular)
            case .headline: return (17, .semibold)
            case .body: return (17, .regular)
            case .callout: return (16, .regular)
            case .subheadline: return (15, .regular)
            case .footnote: return (13, .regular)
            case .caption: return (12, .regular)
            case .caption2: return (11, .regular)
            }
        }
        /// Baseline-to-baseline distance of wrapped lines at the standard Dynamic Type size (Large),
        /// on iOS. A single line is still as tall as the font (ascent + descent); the extra goes
        /// between lines. measured: iOS 27.0 simulator (body 3 lines 64.33pt = 20.33 + 2 x 22,
        /// subheadline 2 lines 38pt = 18 + 20, footnote 2 lines 33.67pt = 15.67 + 18); the other
        /// styles follow Apple's typography table, which these agree with.
        var lineAdvance: CGFloat? {
            switch self {
            case .extraLargeTitle, .extraLargeTitle2: return nil
            case .largeTitle: return 41
            case .title: return 34
            case .title2: return 28
            case .title3: return 25
            case .headline, .body: return 22
            case .callout: return 21
            case .subheadline: return 20
            case .footnote: return 18
            case .caption: return 16
            case .caption2: return 13
            }
        }
    }
    public enum Leading: Hashable, Sendable { case standard, tight, loose }
    public struct Width: Hashable, Sendable {
        public var value: CGFloat
        public init(_ value: CGFloat) { self.value = value }
        public static let compressed = Width(-0.8)
        public static let condensed = Width(-0.2)
        public static let standard = Width(0)
        public static let expanded = Width(0.2)
    }

    enum Provider: Hashable, Sendable {
        case style(TextStyle, design: Design?, weight: Weight?)
        case system(size: CGFloat, weight: Weight?, design: Design?)
        case custom(name: String, size: CGFloat, relativeTo: TextStyle?, fixed: Bool)
    }
    enum Modifier: Hashable, Sendable {
        case weight(Weight), bold, italic, monospacedDigit, monospaced, smallCaps, leading(Leading), width(Width)
    }
    var provider: Provider
    var modifiers: [Modifier] = []

    public static let largeTitle = Font(provider: .style(.largeTitle, design: nil, weight: nil))
    public static let title = Font(provider: .style(.title, design: nil, weight: nil))
    public static let title2 = Font(provider: .style(.title2, design: nil, weight: nil))
    public static let title3 = Font(provider: .style(.title3, design: nil, weight: nil))
    public static let headline = Font(provider: .style(.headline, design: nil, weight: nil))
    public static let subheadline = Font(provider: .style(.subheadline, design: nil, weight: nil))
    public static let body = Font(provider: .style(.body, design: nil, weight: nil))
    public static let callout = Font(provider: .style(.callout, design: nil, weight: nil))
    public static let footnote = Font(provider: .style(.footnote, design: nil, weight: nil))
    public static let caption = Font(provider: .style(.caption, design: nil, weight: nil))
    public static let caption2 = Font(provider: .style(.caption2, design: nil, weight: nil))
    public static let extraLargeTitle = Font(provider: .style(.extraLargeTitle, design: nil, weight: nil))
    public static let extraLargeTitle2 = Font(provider: .style(.extraLargeTitle2, design: nil, weight: nil))

    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
        Font(provider: .style(style, design: design, weight: weight))
    }
    public static func system(size: CGFloat, weight: Weight? = nil, design: Design? = nil) -> Font {
        Font(provider: .system(size: size, weight: weight, design: design))
    }
    @_disfavoredOverload
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        Font(provider: .system(size: size, weight: weight, design: design))
    }
    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(provider: .custom(name: name, size: size, relativeTo: .body, fixed: false))
    }
    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: TextStyle) -> Font {
        Font(provider: .custom(name: name, size: size, relativeTo: textStyle, fixed: false))
    }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        Font(provider: .custom(name: name, size: fixedSize, relativeTo: nil, fixed: true))
    }

    func adding(_ m: Modifier) -> Font {
        var copy = self
        copy.modifiers.append(m)
        return copy
    }
    public func weight(_ weight: Weight) -> Font { adding(.weight(weight)) }
    public func bold() -> Font { adding(.bold) }
    public func italic() -> Font { adding(.italic) }
    public func monospacedDigit() -> Font { adding(.monospacedDigit) }
    public func monospaced() -> Font { adding(.monospaced) }
    public func smallCaps() -> Font { adding(.smallCaps) }
    public func lowercaseSmallCaps() -> Font { adding(.smallCaps) }
    public func uppercaseSmallCaps() -> Font { adding(.smallCaps) }
    public func leading(_ leading: Leading) -> Font { adding(.leading(leading)) }
    public func width(_ width: Width) -> Font { adding(.width(width)) }
}

/// A font with every choice made: what the text engine consumes.
struct ResolvedFont: Hashable {
    enum Family: Hashable { case system(Font.Design), custom(String) }
    var family: Family = .system(.default)
    var size: CGFloat = 17
    var weight: CGFloat = 400
    var italic = false
    var width: CGFloat = 0
    var monospacedDigit = false
    var smallCaps = false
    var lineHeightMultiple: CGFloat = 1
    /// Baseline-to-baseline distance of wrapped lines when it exceeds the font's height
    /// (text styles on iOS); nil stacks lines at the font's ascent + descent.
    var lineAdvance: CGFloat? = nil
}

extension Font {
    func resolve(in env: EnvironmentValues) -> ResolvedFont {
        var r = ResolvedFont()
        let scale = env.dynamicTypeSize.scale
        switch provider {
        case .style(let style, let design, let weight):
            let m = style.metrics(for: env.renderPlatform)
            r.size = (m.size * env.dynamicTypeSize.scale(for: style)).rounded()
            r.weight = (weight ?? m.weight).value
            r.family = .system(design ?? env.fontDesign ?? .default)
            if env.renderPlatform != .tvOS, env.renderPlatform != .watchOS, let advance = style.lineAdvance {
                r.lineAdvance = (advance * r.size / m.size).rounded()
            }
        case .system(let size, let weight, let design):
            r.size = size
            r.weight = (weight ?? .regular).value
            r.family = .system(design ?? env.fontDesign ?? .default)
        case .custom(let name, let size, _, let fixed):
            r.size = fixed ? size : (size * scale).rounded()
            r.family = .custom(name)
        }
        for m in modifiers {
            switch m {
            case .weight(let w): r.weight = w.value
            case .bold: r.weight = max(r.weight, Font.Weight.bold.value)
            case .italic: r.italic = true
            case .monospacedDigit: r.monospacedDigit = true
            case .monospaced: r.family = .system(.monospaced)
            case .smallCaps: r.smallCaps = true
            case .leading(let l): r.lineHeightMultiple = l == .tight ? 0.92 : l == .loose ? 1.1 : 1
            case .width(let w): r.width = w.value
            }
        }
        if let w = env.fontWeight { r.weight = w.value }
        if let w = env.fontWidth { r.width = w.value }
        if env.legibilityWeight == .bold { r.weight = min(900, r.weight + 200) }
        return r
    }
}

// MARK: - Dynamic Type

public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5
    public var isAccessibilitySize: Bool { self >= .accessibility1 }
    /// Body point size at each setting (the reference for scaling other styles).
    var bodySize: CGFloat {
        switch self {
        case .xSmall: return 14
        case .small: return 15
        case .medium: return 16
        case .large: return 17
        case .xLarge: return 19
        case .xxLarge: return 21
        case .xxxLarge: return 23
        case .accessibility1: return 28
        case .accessibility2: return 33
        case .accessibility3: return 40
        case .accessibility4: return 47
        case .accessibility5: return 53
        }
    }
    var scale: CGFloat { bodySize / 17 }
    /// Smaller styles step in whole points with the body size; large titles scale less.
    package func scale(for style: Font.TextStyle) -> CGFloat {
        if self == .large { return 1 }
        let base = style.metrics.size
        let delta = bodySize - 17
        let damped = base >= 28 ? delta * 0.9 : delta
        return max(0.5, (base + damped) / base)
    }
}

public enum LegibilityWeight: Hashable, Sendable { case regular, bold }

enum FontKey: EnvironmentKey { static let defaultValue: Font? = nil }
enum FontWeightKey: EnvironmentKey { static let defaultValue: Font.Weight? = nil }
enum FontDesignKey: EnvironmentKey { static let defaultValue: Font.Design? = nil }
enum FontWidthKey: EnvironmentKey { static let defaultValue: Font.Width? = nil }
enum DynamicTypeSizeKey: EnvironmentKey { static let defaultValue = DynamicTypeSize.large }
enum LegibilityWeightKey: EnvironmentKey { static let defaultValue: LegibilityWeight? = nil }

extension EnvironmentValues {
    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }
    var fontWeight: Font.Weight? {
        get { self[FontWeightKey.self] }
        set { self[FontWeightKey.self] = newValue }
    }
    var fontDesign: Font.Design? {
        get { self[FontDesignKey.self] }
        set { self[FontDesignKey.self] = newValue }
    }
    var fontWidth: Font.Width? {
        get { self[FontWidthKey.self] }
        set { self[FontWidthKey.self] = newValue }
    }
    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }
    public var legibilityWeight: LegibilityWeight? {
        get { self[LegibilityWeightKey.self] }
        set { self[LegibilityWeightKey.self] = newValue }
    }
}

extension View {
    public func font(_ font: Font?) -> some View { env { $0.font = font } }
    public func fontWeight(_ weight: Font.Weight?) -> some View { env { $0.fontWeight = weight } }
    public func fontDesign(_ design: Font.Design?) -> some View { env { $0.fontDesign = design } }
    public func fontWidth(_ width: Font.Width?) -> some View { env { $0.fontWidth = width } }
    public func bold(_ isActive: Bool = true) -> some View { env { if isActive { $0.fontWeight = .bold } } }
    public func italic(_ isActive: Bool = true) -> some View { env { if isActive { $0.textItalic = true } } }
    public func monospaced(_ isActive: Bool = true) -> some View { env { if isActive { $0.fontDesign = .monospaced } } }
    public func monospacedDigit() -> some View { env { $0.textMonospacedDigit = true } }
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View { env { $0.dynamicTypeSize = size } }
    public func dynamicTypeSize<T: RangeExpression>(_ range: T) -> some View where T.Bound == DynamicTypeSize {
        env { if !range.contains($0.dynamicTypeSize) { $0.dynamicTypeSize = .large } }
    }
}
