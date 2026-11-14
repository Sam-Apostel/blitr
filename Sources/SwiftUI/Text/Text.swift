// The Text view: storage, modifiers, and resolution into styled runs.

public struct Text: Equatable, Sendable {
    public enum TruncationMode: Hashable, Sendable { case head, tail, middle }
    public enum Case: Hashable, Sendable { case uppercase, lowercase }
    public struct LineStyle: Hashable, Sendable {
        public struct Pattern: Hashable, Sendable {
            public static let solid = Pattern(), dot = Pattern(), dash = Pattern(), dashDot = Pattern(), dashDotDot = Pattern()
        }
        var color: Color?
        public init(pattern: Pattern = .solid, color: Color? = nil) { self.color = color }
        public static let single = LineStyle()
    }
    public struct Scale: Hashable, Sendable {
        public static let `default` = Scale(factor: 1)
        public static let secondary = Scale(factor: 0.88)
        let factor: CGFloat
    }
    public struct DateStyle: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case time, date, relative, offset, timer }
        let kind: Kind
        public static let time = DateStyle(kind: .time)
        public static let date = DateStyle(kind: .date)
        public static let relative = DateStyle(kind: .relative)
        public static let offset = DateStyle(kind: .offset)
        public static let timer = DateStyle(kind: .timer)
    }

    indirect enum Storage: @unchecked Sendable {
        case verbatim(String)
        case localized(LocalizedStringKey)
        case concatenated(Text, Text)
        case image(Image)
        case attributed(AttributedString)
    }
    enum Modifier: @unchecked Sendable {
        case font(Font?), weight(Font.Weight?), bold(Bool), italic(Bool), style(AnyShapeStyle?)
        case underline(Bool, Color?), strikethrough(Bool, Color?), kerning(CGFloat), baselineOffset(CGFloat)
        case monospacedDigit, monospaced(Bool), design(Font.Design?), width(Font.Width?), scale(CGFloat)
    }
    var storage: Storage
    var modifiers: [Modifier] = []
    /// Set by `accessibilityLabel` / `accessibilityHeading` on a Text; copied to the node's accessibility info.
    var accessibilityLabelText: String?
    var isAccessibilityHeading = false

    /// String literals prefer the LocalizedStringKey initializer (Markdown, interpolation), as in SwiftUI.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) { storage = .verbatim(String(content)) }
    public init(verbatim content: String) { storage = .verbatim(content) }
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
        storage = .localized(key)
    }
    public init(_ image: Image) { storage = .image(image) }
    public init(_ date: Date, style: DateStyle) { storage = .verbatim(Text.format(date, style)) }
    public init(_ dates: ClosedRange<Date>) {
        storage = .verbatim(dates.lowerBound.formatted(date: .omitted, time: .shortened) + " – " + dates.upperBound.formatted(date: .omitted, time: .shortened))
    }
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatInput: Equatable, F.FormatOutput == String {
        storage = .verbatim(format.format(input))
    }
    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) { storage = .attributed(attributedContent) }
    init(storage: Storage) { self.storage = storage }

    static func format(_ date: Date, _ style: DateStyle) -> String {
        switch style.kind {
        case .time: return date.formatted(date: .omitted, time: .shortened)
        case .date: return date.formatted(date: .long, time: .omitted)
        case .relative, .offset:
            let seconds = Int(abs(date.timeIntervalSince(Runtime.now)))
            if seconds < 60 { return "\(seconds) sec" }
            if seconds < 3600 { return "\(seconds / 60) min" }
            if seconds < 86400 { return "\(seconds / 3600) hr" }
            return "\(seconds / 86400) days"
        case .timer:
            let seconds = Int(abs(date.timeIntervalSince(Runtime.now)))
            return seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    public static func == (l: Text, r: Text) -> Bool { l.plainString == r.plainString }

    public static func + (lhs: Text, rhs: Text) -> Text { Text(storage: .concatenated(lhs, rhs)) }

    /// The text without styling (used for accessibility labels, titles, measuring).
    package var plainString: String {
        switch storage {
        case .verbatim(let s): return s
        case .localized(let key): return key.plainString
        case .concatenated(let a, let b): return a.plainString + b.plainString
        case .image: return ""
        case .attributed(let a): return String(a.characters)
        }
    }

    func adding(_ m: Modifier) -> Text {
        var copy = self
        copy.modifiers.append(m)
        return copy
    }
    public func font(_ font: Font?) -> Text { adding(.font(font)) }
    public func fontWeight(_ weight: Font.Weight?) -> Text { adding(.weight(weight)) }
    public func fontDesign(_ design: Font.Design?) -> Text { adding(.design(design)) }
    public func fontWidth(_ width: Font.Width?) -> Text { adding(.width(width)) }
    public func bold() -> Text { adding(.bold(true)) }
    public func bold(_ isActive: Bool) -> Text { adding(.bold(isActive)) }
    public func italic() -> Text { adding(.italic(true)) }
    public func italic(_ isActive: Bool) -> Text { adding(.italic(isActive)) }
    public func foregroundColor(_ color: Color?) -> Text { adding(.style(color.map { AnyShapeStyle($0) })) }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text { adding(.style(AnyShapeStyle(style))) }
    public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text { adding(.underline(isActive, color)) }
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern, color: Color? = nil) -> Text { adding(.underline(isActive, color)) }
    public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text { adding(.strikethrough(isActive, color)) }
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern, color: Color? = nil) -> Text { adding(.strikethrough(isActive, color)) }
    public func kerning(_ kerning: CGFloat) -> Text { adding(.kerning(kerning)) }
    public func tracking(_ tracking: CGFloat) -> Text { adding(.kerning(tracking)) }
    public func baselineOffset(_ offset: CGFloat) -> Text { adding(.baselineOffset(offset)) }
    public func monospacedDigit() -> Text { adding(.monospacedDigit) }
    public func monospaced(_ isActive: Bool = true) -> Text { adding(.monospaced(isActive)) }
    public func textScale(_ scale: Scale, isEnabled: Bool = true) -> Text { isEnabled ? adding(.scale(scale.factor)) : self }
    public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> Text { self }
    public func accessibilityLabel(_ label: Text) -> Text { var copy = self; copy.accessibilityLabelText = label.plainString; return copy }
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> Text { var copy = self; copy.accessibilityLabelText = String(label); return copy }
    public func accessibilityTextContentType(_ value: AccessibilityTextContentType) -> Text { self }
    public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> Text {
        var copy = self
        copy.isAccessibilityHeading = level != .unspecified
        return copy
    }
}

public struct AccessibilityTextContentType: Sendable {
    public static let plain = Self(), console = Self(), fileSystem = Self(), messaging = Self(), narrative = Self(), sourceCode = Self(), spreadsheet = Self(), wordProcessing = Self()
}
public enum AccessibilityHeadingLevel: UInt, Sendable { case unspecified, h1, h2, h3, h4, h5, h6 }

extension Runtime {
    /// "Now" for relative dates, fixed per render so screenshots are reproducible.
    nonisolated(unsafe) static var referenceDate = Date()
}

// MARK: - Resolution to runs

/// The inherited text attributes while walking a Text's structure.
struct TextAttributes {
    var font: Font?
    var weight: Font.Weight?
    var bold = false
    var italic = false
    var paint: _Paint?
    var underline: (Bool, Color?)?
    var strikethrough: (Bool, Color?)?
    var kerning: CGFloat = 0
    var baselineOffset: CGFloat = 0
    var monospacedDigit = false
    var monospaced = false
    var design: Font.Design?
    var width: Font.Width?
    var scale: CGFloat = 1
    var isLink = false
    var isCode = false
    var background: Color?
}

extension Text {
    @MainActor
    func runs(in env: EnvironmentValues, inherited: TextAttributes = TextAttributes()) -> [TextRun] {
        var attrs = inherited
        for m in modifiers {
            switch m {
            case .font(let f): attrs.font = f ?? attrs.font
            case .weight(let w): attrs.weight = w
            case .bold(let b): attrs.bold = b
            case .italic(let i): attrs.italic = i
            case .style(let s): attrs.paint = s?._paint(in: env)
            case .underline(let on, let c): attrs.underline = (on, c)
            case .strikethrough(let on, let c): attrs.strikethrough = (on, c)
            case .kerning(let k): attrs.kerning = k
            case .baselineOffset(let o): attrs.baselineOffset = o
            case .monospacedDigit: attrs.monospacedDigit = true
            case .monospaced(let on): attrs.monospaced = on
            case .design(let d): attrs.design = d
            case .width(let w): attrs.width = w
            case .scale(let s): attrs.scale = s
            }
        }
        switch storage {
        case .verbatim(let string):
            return [Text.makeRun(string, attrs, env)]
        case .localized(let key):
            return key.runs(in: env, attrs: attrs)
        case .concatenated(let a, let b):
            return a.runs(in: env, inherited: attrs) + b.runs(in: env, inherited: attrs)
        case .image(let image):
            var run = Text.makeRun("\u{FFFC}", attrs, env)
            run.attachment = image.inlineAttachment(font: run.font, paint: run.paint, env: env)
            return [run]
        case .attributed(let string):
            return Text.attributedRuns(string, attrs, env)
        }
    }

    /// The inline presentation intent, read by name: libSwiftUIScreenshotEngine links its own copy of
    /// SwiftUIScreenshotFoundation, so a value app code stored (through the autolinked library) is another `InlinePresentationIntent` type
    /// than the one here, and a typed read would fail its cast.
    private enum InlineIntentKey: AttributedStringKey {
        typealias Value = AnyHashable
        static let name = AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.name
    }

    /// An AttributedString's runs: its SwiftUI attributes take precedence over the Text's modifiers, as on
    /// Apple platforms; Markdown's inline presentation intents and links are drawn as in a Markdown literal.
    @MainActor
    static func attributedRuns(_ string: AttributedString, _ inherited: TextAttributes, _ env: EnvironmentValues) -> [TextRun] {
        typealias S = AttributeScopes.SwiftUIAttributes
        var result: [TextRun] = []
        for run in string.runs {
            var a = inherited
            if let font = run[S.FontAttribute.self] { a.font = font }
            if let color = run[S.ForegroundColorAttribute.self] { a.paint = AnyShapeStyle(color)._paint(in: env) }
            if let color = run[S.BackgroundColorAttribute.self] { a.background = color }
            if let raw = (run[InlineIntentKey.self]?.base as? any RawRepresentable)?.rawValue as? UInt {
                let intent = InlinePresentationIntent(rawValue: raw)
                if intent.contains(.stronglyEmphasized) { a.bold = true }
                if intent.contains(.emphasized) { a.italic = true }
                if intent.contains(.code) { a.isCode = true }
                if intent.contains(.strikethrough) { a.strikethrough = (true, nil) }
            }
            if let style = run[S.StrikethroughStyleAttribute.self] { a.strikethrough = (true, style.color) }
            if let style = run[S.UnderlineStyleAttribute.self] { a.underline = (true, style.color) }
            if let kern = run[S.KerningAttribute.self] { a.kerning = kern }
            if let tracking = run[S.TrackingAttribute.self] { a.kerning = tracking }
            if let offset = run[S.BaselineOffsetAttribute.self] { a.baselineOffset = offset }
            if run.link != nil { a.isLink = true }
            result.append(Text.makeRun(String(string[run.range].characters), a, env))
        }
        return result.isEmpty ? [Text.makeRun("", inherited, env)] : result
    }

    @MainActor
    static func makeRun(_ string: String, _ attrs: TextAttributes, _ env: EnvironmentValues) -> TextRun {
        var font = (attrs.font ?? env.font ?? .body).resolve(in: env)
        if let w = attrs.weight { font.weight = w.value }
        if attrs.bold { font.weight = max(font.weight, 700) }
        if attrs.italic || env.textItalic { font.italic = true }
        if attrs.monospacedDigit || env.textMonospacedDigit { font.monospacedDigit = true }
        if attrs.monospaced || attrs.isCode { font.family = .system(.monospaced) }
        if let d = attrs.design { font.family = .system(d) }
        if let w = attrs.width { font.width = w.value }
        font.size *= attrs.scale
        var text = string
        switch env.textCase {
        case .uppercase: text = text.uppercased()
        case .lowercase: text = text.lowercased()
        case nil: break
        }
        var paint = attrs.paint ?? ForegroundStyle()._paint(in: env)
        if attrs.isLink { paint = .color(Color.accentColor.rgba(in: env)) }
        var run = TextRun(text: text, font: font, paint: paint)
        let base = paint.representativeColor
        if let (on, color) = attrs.underline ?? env.textUnderline, on { run.underline = color?.rgba(in: env) ?? base }
        if let (on, color) = attrs.strikethrough ?? env.textStrikethrough, on { run.strikethrough = color?.rgba(in: env) ?? base }
        run.kerning = attrs.kerning != 0 ? attrs.kerning : env.textKerning
        run.baselineOffset = attrs.baselineOffset
        run.background = attrs.background?.rgba(in: env)
        return run
    }
}

// MARK: - Node

final class TextNode: Node {
    let runs: [TextRun]
    let options: TextLayoutOptions
    let reservesSpace: Bool
    private var layouts: [LayoutKey: TextLayout] = [:]
    private struct LayoutKey: Hashable { var width: CGFloat?; var height: CGFloat? }

    init(runs: [TextRun], options: TextLayoutOptions, reservesSpace: Bool = false) {
        self.runs = runs
        self.options = options
        self.reservesSpace = reservesSpace
        super.init()
    }

    func textLayout(width: CGFloat?, height: CGFloat? = nil) -> TextLayout {
        let width = width.map { $0.isFinite ? $0 : nil } ?? nil
        // The height only matters to text that may shrink to fit it.
        let height = options.minimumScaleFactor < 1 ? (height.map { $0.isFinite ? $0 : nil } ?? nil) : nil
        let key = LayoutKey(width: width, height: height)
        if let cached = layouts[key] { return cached }
        let layout = TextLayout(runs: runs, width: width, height: height, options: options)
        layouts[key] = layout
        return layout
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        var size = textLayout(width: proposal.width, height: proposal.height).size
        if reservesSpace, let limit = options.lineLimit, let line = textLayout(width: nil).lines.first {
            let lineHeight = line.ascent + line.descent
            size.height = max(size.height, lineHeight * CGFloat(limit) + (options.lineSpacing + line.leading) * CGFloat(limit - 1))
        }
        return size
    }

    override func textLeading(_ edge: Edge) -> CGFloat? {
        guard edge == .top || edge == .bottom else { return nil }
        let lines = textLayout(width: nil).lines
        guard let line = edge == .top ? lines.first : lines.last else { return nil }
        let scale = max(options.scale, 1)
        return (line.leading * scale - 0.001).rounded(.up) / scale
    }

    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        let id = ObjectIdentifier(key.id)
        if id == ObjectIdentifier(VerticalAlignment.FirstTextBaseline.self) { return textLayout(width: size.width).firstBaseline }
        if id == ObjectIdentifier(VerticalAlignment.LastTextBaseline.self) { return textLayout(width: size.width).lastBaseline }
        return nil
    }

    override func drawContent(_ p: Painter) {
        textLayout(width: frame.width, height: frame.height).draw(p, in: CGRect(origin: .zero, size: frame.size))
    }
}

extension Text: View, PrimitiveView {
    public typealias Body = Never
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let node = makeNode(ctx.env)
        if accessibilityLabelText != nil || isAccessibilityHeading {
            node.ax = AXBox(AccessibilityInfo {
                $0.label = accessibilityLabelText
                if isAccessibilityHeading { $0.addTraits = [.header] }
            })
        }
        out.append(node)
    }
    @MainActor
    func makeNode(_ env: EnvironmentValues) -> TextNode {
        var options = TextLayoutOptions()
        options.lineLimit = env.lineLimit
        options.alignment = env.multilineTextAlignment
        options.truncation = env.truncationMode
        options.lineSpacing = env.lineSpacing
        options.minimumScaleFactor = env.minimumScaleFactor
        options.scale = env.displayScale
        options.avoidsOrphans = env.renderPlatform != .tvOS
        return TextNode(runs: runs(in: env), options: options, reservesSpace: env.lineLimitReservesSpace)
    }
}

// MARK: - Environment + view modifiers

enum LineLimitKey: EnvironmentKey { static let defaultValue: Int? = nil }
enum LineLimitReservesSpaceKey: EnvironmentKey { static let defaultValue = false }
enum MultilineTextAlignmentKey: EnvironmentKey { static let defaultValue = TextAlignment.leading }
enum TruncationModeKey: EnvironmentKey { static let defaultValue = Text.TruncationMode.tail }
enum LineSpacingKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
enum MinimumScaleFactorKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
enum TextCaseKey: EnvironmentKey { static let defaultValue: Text.Case? = nil }
enum TextItalicKey: EnvironmentKey { static let defaultValue = false }
enum TextMonospacedDigitKey: EnvironmentKey { static let defaultValue = false }
enum TextKerningKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
enum TextUnderlineKey: EnvironmentKey { static let defaultValue: (Bool, Color?)? = nil }
enum TextStrikethroughKey: EnvironmentKey { static let defaultValue: (Bool, Color?)? = nil }
enum AllowsTighteningKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }
    var lineLimitReservesSpace: Bool {
        get { self[LineLimitReservesSpaceKey.self] }
        set { self[LineLimitReservesSpaceKey.self] = newValue }
    }
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }
    public var lineSpacing: CGFloat {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }
    public var minimumScaleFactor: CGFloat {
        get { self[MinimumScaleFactorKey.self] }
        set { self[MinimumScaleFactorKey.self] = newValue }
    }
    public var textCase: Text.Case? {
        get { self[TextCaseKey.self] }
        set { self[TextCaseKey.self] = newValue }
    }
    public var allowsTightening: Bool {
        get { self[AllowsTighteningKey.self] }
        set { self[AllowsTighteningKey.self] = newValue }
    }
    var textItalic: Bool {
        get { self[TextItalicKey.self] }
        set { self[TextItalicKey.self] = newValue }
    }
    var textMonospacedDigit: Bool {
        get { self[TextMonospacedDigitKey.self] }
        set { self[TextMonospacedDigitKey.self] = newValue }
    }
    var textKerning: CGFloat {
        get { self[TextKerningKey.self] }
        set { self[TextKerningKey.self] = newValue }
    }
    var textUnderline: (Bool, Color?)? {
        get { self[TextUnderlineKey.self] }
        set { self[TextUnderlineKey.self] = newValue }
    }
    var textStrikethrough: (Bool, Color?)? {
        get { self[TextStrikethroughKey.self] }
        set { self[TextStrikethroughKey.self] = newValue }
    }
}

extension View {
    public func lineLimit(_ number: Int?) -> some View { env { $0.lineLimit = number; $0.lineLimitReservesSpace = false } }
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        env { $0.lineLimit = limit; $0.lineLimitReservesSpace = reservesSpace }
    }
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View { env { $0.lineLimit = limit.upperBound } }
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View { env { $0.lineLimit = nil } }
    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View { env { $0.lineLimit = limit.upperBound } }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { env { $0.multilineTextAlignment = alignment } }
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { env { $0.truncationMode = mode } }
    public func lineSpacing(_ lineSpacing: CGFloat) -> some View { env { $0.lineSpacing = lineSpacing } }
    public func minimumScaleFactor(_ factor: CGFloat) -> some View { env { $0.minimumScaleFactor = factor } }
    public func textCase(_ textCase: Text.Case?) -> some View { env { $0.textCase = textCase } }
    public func allowsTightening(_ flag: Bool) -> some View { env { $0.allowsTightening = flag } }
    public func kerning(_ kerning: CGFloat) -> some View { env { $0.textKerning = kerning } }
    public func tracking(_ tracking: CGFloat) -> some View { env { $0.textKerning = tracking } }
    public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        env { $0.textUnderline = (isActive, color) }
    }
    public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        env { $0.textStrikethrough = (isActive, color) }
    }
    public func baselineOffset(_ offset: CGFloat) -> some View { self }
    public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> some View { self }
}
