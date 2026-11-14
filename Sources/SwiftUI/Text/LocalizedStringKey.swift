// String literals passed to Text: interpolation plus inline Markdown.

public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation, Sendable {
    enum Segment: @unchecked Sendable {
        case literal(String)
        case string(String)
        case text(Text)
    }
    var segments: [Segment]
    /// Format specifiers Xcode puts in the key for interpolations that are not `%@`, by segment index.
    var specifiers: [Int: String] = [:]

    public init(_ value: String) { segments = [.literal(value)] }
    public init(stringLiteral value: String) { segments = [.literal(value)] }
    public init(stringInterpolation: StringInterpolation) { segments = stringInterpolation.segments; specifiers = stringInterpolation.specifiers }

    public static func == (l: LocalizedStringKey, r: LocalizedStringKey) -> Bool { l.plainString == r.plainString }

    public struct StringInterpolation: StringInterpolationProtocol {
        var segments: [Segment] = []
        var specifiers: [Int: String] = [:]
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { segments.append(.literal(literal)) }
        public mutating func appendInterpolation(_ string: String) { segments.append(.string(string)) }
        public mutating func appendInterpolation(_ text: Text) { segments.append(.text(text)) }
        public mutating func appendInterpolation(_ image: Image) { segments.append(.text(Text(image))) }
        public mutating func appendInterpolation(_ attributed: AttributedString) { segments.append(.string(String(attributed.characters))) }
        public mutating func appendInterpolation<T>(_ value: T) {
            let specifier = ScreenshotStrings.specifier(for: value)
            if specifier != "%@" { specifiers[segments.count] = specifier }
            segments.append(.string("\(value)"))
        }
        public mutating func appendInterpolation<T: CVarArg>(_ value: T, specifier: String) {
            specifiers[segments.count] = specifier
            segments.append(.string(String(format: specifier, value)))
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
            segments.append(.string(format.format(input)))
        }
        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
            segments.append(.string(Text.format(date, style)))
        }
    }

    var plainString: String {
        runsSource().reduce("") { $0 + $1.text }
    }

    /// Interpolated values are swapped for private-use placeholders so Markdown spans can
    /// cross them, then restored after parsing.
    private func runsSource() -> [InlineMarkdown.Span] {
        var source = ""
        var inserts: [Segment] = []
        var key = ""
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .literal(let s):
                source += s
                key += s.replacingOccurrences(of: "%", with: "%%")
            default:
                source.unicodeScalars.append(Unicode.Scalar(UInt32(0xE000 + inserts.count))!)
                inserts.append(segment)
                key += specifiers[index] ?? "%@"
            }
        }
        // A translation from the project's string table replaces the literal text; its placeholders
        // ("%@", "%lld", "%2$@") take the interpolated values.
        if !ScreenshotStrings.table.isEmpty, let template = ScreenshotStrings.template(key, arguments: inserts.map { insert in
            if case .string(let s) = insert { return s }
            return ""
        }) {
            let chars = Array(template)
            source = ""
            var i = 0
            for placeholder in ScreenshotStrings.placeholders(template) {
                source += String(chars[i..<placeholder.range.lowerBound]).replacingOccurrences(of: "%%", with: "%")
                if placeholder.argument < inserts.count { source.unicodeScalars.append(Unicode.Scalar(UInt32(0xE000 + placeholder.argument))!) }
                i = placeholder.range.upperBound
            }
            source += String(chars[i...]).replacingOccurrences(of: "%%", with: "%")
        }
        var spans: [InlineMarkdown.Span] = []
        for span in InlineMarkdown.parse(source) {
            var buffer = ""
            for scalar in span.text.unicodeScalars {
                let index = Int(scalar.value) - 0xE000
                if index >= 0, index < inserts.count {
                    if !buffer.isEmpty { spans.append(span.with(buffer)); buffer = "" }
                    switch inserts[index] {
                    case .string(let s): spans.append(span.with(s))
                    case .text(let t): var s = span.with(""); s.embedded = t; spans.append(s)
                    case .literal: break
                    }
                } else {
                    buffer.unicodeScalars.append(scalar)
                }
            }
            if !buffer.isEmpty { spans.append(span.with(buffer)) }
        }
        return spans
    }

    @MainActor
    func runs(in env: EnvironmentValues, attrs: TextAttributes) -> [TextRun] {
        var result: [TextRun] = []
        for span in runsSource() {
            var a = attrs
            if span.bold { a.bold = true }
            if span.italic { a.italic = true }
            if span.strikethrough { a.strikethrough = (true, nil) }
            if span.code { a.isCode = true }
            if span.link { a.isLink = true }
            if let text = span.embedded {
                result += text.runs(in: env, inherited: a)
            } else {
                result.append(Text.makeRun(span.text, a, env))
            }
        }
        return result.isEmpty ? [Text.makeRun("", attrs, env)] : result
    }
}

/// The inline subset of Markdown that SwiftUI's Text renders.
enum InlineMarkdown {
    struct Span {
        var text: String
        var bold = false, italic = false, strikethrough = false, code = false, link = false
        var embedded: Text? = nil
        func with(_ text: String) -> Span {
            var copy = self
            copy.text = text
            copy.embedded = nil
            return copy
        }
    }

    static func parse(_ source: String) -> [Span] {
        guard source.contains(where: { "*_~`[\\".contains($0) }) else { return [Span(text: source)] }
        var spans: [Span] = []
        parse(Array(source), style: Span(text: ""), into: &spans)
        return spans
    }

    private static func parse(_ chars: [Character], style: Span, into spans: inout [Span]) {
        var buffer = ""
        var i = 0
        func flush() {
            if !buffer.isEmpty { spans.append(style.with(buffer)); buffer = "" }
        }
        func find(_ delimiter: [Character], from start: Int) -> Int? {
            guard start < chars.count else { return nil }
            var j = start
            while j + delimiter.count <= chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if Array(chars[j..<(j + delimiter.count)]) == delimiter, j > start { return j }
                j += 1
            }
            return nil
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count { buffer.append(chars[i + 1]); i += 2; continue }
            if c == "`", let end = find(["`"], from: i + 1) {
                flush()
                var s = style.with(String(chars[(i + 1)..<end]))
                s.code = true
                spans.append(s)
                i = end + 1
                continue
            }
            if c == "[", let close = find(["]"], from: i + 1), close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find([")"], from: close + 2) ?? (close + 2 < chars.count && chars[close + 2] == ")" ? close + 2 : nil) {
                flush()
                var s = style
                s.link = true
                parse(Array(chars[(i + 1)..<close]), style: s, into: &spans)
                i = paren + 1
                continue
            }
            var matched = false
            for (delimiter, apply) in delimiters {
                let d = Array(delimiter)
                guard i + d.count <= chars.count, Array(chars[i..<(i + d.count)]) == d else { continue }
                // Opening delimiters must be followed by text; `_` only opens at a word boundary.
                guard i + d.count < chars.count, !chars[i + d.count].isWhitespace else { continue }
                if d[0] == "_", i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber { continue }
                guard let end = find(d, from: i + d.count), !chars[end - 1].isWhitespace else { continue }
                flush()
                var s = style
                apply(&s)
                parse(Array(chars[(i + d.count)..<end]), style: s, into: &spans)
                i = end + d.count
                matched = true
                break
            }
            if matched { continue }
            buffer.append(c)
            i += 1
        }
        flush()
    }

    private static let delimiters: [(String, (inout Span) -> Void)] = [
        ("***", { $0.bold = true; $0.italic = true }),
        ("**", { $0.bold = true }),
        ("__", { $0.bold = true }),
        ("~~", { $0.strikethrough = true }),
        ("*", { $0.italic = true }),
        ("_", { $0.italic = true }),
    ]
}
