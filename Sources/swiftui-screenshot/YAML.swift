import Foundation

/// The subset of YAML that XcodeGen specs use: block mappings and sequences, flow `[...]` and `{...}`
/// collections, plain and quoted scalars, block scalars (`|`, `>`) and comments. Anchors, aliases,
/// tags and multi-document streams are not supported; a spec that uses them is reported, not misread.
indirect enum YAML: Equatable {
    case scalar(String)
    case list([YAML])
    case map([(key: String, value: YAML)])
    case null

    static func == (a: YAML, b: YAML) -> Bool {
        switch (a, b) {
        case (.scalar(let x), .scalar(let y)): return x == y
        case (.list(let x), .list(let y)): return x == y
        case (.map(let x), .map(let y)): return x.map(\.key) == y.map(\.key) && x.map(\.value) == y.map(\.value)
        case (.null, .null): return true
        default: return false
        }
    }

    subscript(key: String) -> YAML? {
        if case .map(let entries) = self { return entries.last(where: { $0.key == key })?.value }
        return nil
    }
    var string: String? {
        switch self {
        case .scalar(let s): return s
        default: return nil
        }
    }
    var bool: Bool? {
        guard let s = string?.lowercased() else { return nil }
        if ["true", "yes", "on"].contains(s) { return true }
        if ["false", "no", "off"].contains(s) { return false }
        return nil
    }
    var list: [YAML] {
        switch self {
        case .list(let items): return items
        case .null: return []
        default: return [self]
        }
    }
    var entries: [(key: String, value: YAML)] {
        if case .map(let entries) = self { return entries }
        return []
    }
    /// A scalar or a list of scalars, as strings.
    var strings: [String] { list.compactMap(\.string) }

    /// Merges `other` into `self`: maps merge key by key (recursively), anything else is replaced.
    func merged(with other: YAML) -> YAML {
        guard case .map(var mine) = self, case .map(let theirs) = other else { return other }
        for (key, value) in theirs {
            if let index = mine.firstIndex(where: { $0.key == key }) { mine[index].value = mine[index].value.merged(with: value) }
            else { mine.append((key, value)) }
        }
        return .map(mine)
    }

    struct ParseError: Error, CustomStringConvertible {
        var line: Int
        var message: String
        var description: String { "line \(line): \(message)" }
    }

    static func parse(_ text: String) throws -> YAML {
        var parser = YAMLParser(text)
        return try parser.document()
    }
}

private struct YAMLParser {
    struct Line {
        var number: Int
        var indent: Int
        var text: String
    }
    var lines: [Line] = []
    var index = 0

    init(_ text: String) {
        var raw = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var number = 0
        var pending: Line?
        var depth = 0
        while !raw.isEmpty {
            let line = raw.removeFirst()
            number += 1
            if line.hasPrefix("---") || line.hasPrefix("...") { if pending == nil { continue } }
            let stripped = YAMLParser.stripComment(line)
            if var open = pending {
                // A flow collection spanning several lines: join until the brackets balance.
                open.text += " " + stripped.trimmingCharacters(in: .whitespaces)
                depth += YAMLParser.bracketBalance(stripped)
                if depth <= 0 { lines.append(open); pending = nil; depth = 0 } else { pending = open }
                continue
            }
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = stripped.prefix(while: { $0 == " " }).count
            let entry = Line(number: number, indent: indent, text: trimmed)
            let balance = YAMLParser.bracketBalance(trimmed)
            if balance > 0 { pending = entry; depth = balance } else { lines.append(entry) }
            // Block scalars keep their raw lines; they are consumed here so their content is not parsed as YAML.
            if trimmed.hasSuffix("|") || trimmed.hasSuffix(">") || trimmed.hasSuffix("|-") || trimmed.hasSuffix(">-")
                || trimmed.hasSuffix("|+") || trimmed.hasSuffix(">+") {
                var body: [String] = []
                while let next = raw.first {
                    let nextIndent = next.prefix(while: { $0 == " " }).count
                    if !next.trimmingCharacters(in: .whitespaces).isEmpty && nextIndent <= indent { break }
                    body.append(next.trimmingCharacters(in: .whitespaces))
                    raw.removeFirst()
                    number += 1
                }
                let folded = trimmed.contains(">")
                let value = body.joined(separator: folded ? " " : "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let quoted = "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
                var last = lines.removeLast()
                last.text = String(last.text.dropLast(last.text.hasSuffix("|") || last.text.hasSuffix(">") ? 1 : 2)).trimmingCharacters(in: .whitespaces) + " " + quoted
                lines.append(last)
            }
        }
        if let open = pending { lines.append(open) }
    }

    /// Removes a trailing `# comment` that is not inside quotes.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for (offset, c) in line.enumerated() {
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                if previous == " " || previous == ":" || previous == "[" || previous == "{" || previous == "," || previous == "-" { quote = c }
            } else if c == "#", previous == " " || offset == 0 || previous == "\t" {
                return String(line.prefix(offset))
            }
            previous = c
        }
        return line
    }

    static func bracketBalance(_ text: String) -> Int {
        var depth = 0
        var quote: Character?
        for c in text {
            if let q = quote { if c == q { quote = nil }; continue }
            switch c {
            case "\"", "'": quote = c
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        return depth
    }

    mutating func document() throws -> YAML {
        guard !lines.isEmpty else { return .null }
        for line in lines where line.text.hasPrefix("&") || line.text.hasPrefix("*") || line.text.contains(": &") || line.text.contains(": *") || line.text.hasPrefix("<<:") {
            throw YAML.ParseError(line: line.number, message: "YAML anchors, aliases and merge keys are not supported")
        }
        return try block(indent: lines[0].indent)
    }

    static func isSequenceItem(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }

    mutating func block(indent: Int) throws -> YAML {
        guard index < lines.count else { return .null }
        return YAMLParser.isSequenceItem(lines[index].text) ? try sequence(indent: indent) : try mapping(indent: indent)
    }

    mutating func sequence(indent: Int) throws -> YAML {
        var items: [YAML] = []
        while index < lines.count, lines[index].indent == indent, YAMLParser.isSequenceItem(lines[index].text) {
            let line = lines[index]
            let content = String(line.text.dropFirst(1))
            let spaces = content.prefix(while: { $0 == " " }).count
            let rest = content.trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                index += 1
                if index < lines.count, lines[index].indent > indent { items.append(try block(indent: lines[index].indent)) }
                else { items.append(.null) }
            } else if YAMLParser.isSequenceItem(rest) || YAMLParser.keySplit(rest) != nil {
                // `- key: value` (or a nested `- - x`) starts a collection whose first line is inline.
                let childIndent = indent + 1 + spaces
                lines[index] = Line(number: line.number, indent: childIndent, text: rest)
                items.append(try block(indent: childIndent))
            } else {
                items.append(try YAMLParser.flowValue(rest, line: line.number))
                index += 1
            }
        }
        return .list(items)
    }

    mutating func mapping(indent: Int) throws -> YAML {
        var entries: [(key: String, value: YAML)] = []
        while index < lines.count, lines[index].indent == indent, !YAMLParser.isSequenceItem(lines[index].text) {
            let line = lines[index]
            guard let (key, value) = YAMLParser.keySplit(line.text) else {
                throw YAML.ParseError(line: line.number, message: "expected `key: value`, found \"\(line.text)\"")
            }
            index += 1
            if value.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    entries.append((key, try block(indent: lines[index].indent)))
                } else if index < lines.count, lines[index].indent == indent, YAMLParser.isSequenceItem(lines[index].text) {
                    entries.append((key, try sequence(indent: indent)))
                } else {
                    entries.append((key, .null))
                }
            } else {
                entries.append((key, try YAMLParser.flowValue(value, line: line.number)))
            }
        }
        if index < lines.count, lines[index].indent > indent {
            throw YAML.ParseError(line: lines[index].number, message: "unexpected indentation")
        }
        return .map(entries)
    }

    /// Splits `key: value` at the first `:` followed by a space or the end, outside quotes and brackets.
    static func keySplit(_ text: String) -> (String, String)? {
        let chars = Array(text)
        var quote: Character?
        var depth = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if (c == "\"" || c == "'") && i == 0 {
                quote = c
            } else if c == "[" || c == "{" {
                if i == 0 { return nil }
                depth += 1
            } else if c == "]" || c == "}" {
                depth -= 1
            } else if c == ":", depth == 0, i + 1 == chars.count || chars[i + 1] == " " || chars[i + 1] == "\t" {
                let key = unquote(String(chars[0..<i]).trimmingCharacters(in: .whitespaces))
                let value = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
                return (key, value)
            }
            i += 1
        }
        return nil
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            var out = ""
            var escaped = false
            for c in s.dropFirst().dropLast() {
                if escaped {
                    switch c {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(c)
                    }
                    escaped = false
                } else if c == "\\" { escaped = true } else { out.append(c) }
            }
            return out
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    static func flowValue(_ text: String, line: Int) throws -> YAML {
        var flow = FlowParser(chars: Array(text), line: line)
        let value = try flow.value(terminators: [])
        flow.skipSpaces()
        if flow.i < flow.chars.count { throw YAML.ParseError(line: line, message: "unexpected text after value: \(text)") }
        return value
    }

    struct FlowParser {
        var chars: [Character]
        var i = 0
        var line: Int

        init(chars: [Character], line: Int) { self.chars = chars; self.line = line }

        mutating func skipSpaces() { while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 } }

        mutating func value(terminators: Set<Character>) throws -> YAML {
            skipSpaces()
            guard i < chars.count else { return .null }
            switch chars[i] {
            case "[":
                i += 1
                var items: [YAML] = []
                while true {
                    skipSpaces()
                    guard i < chars.count else { throw YAML.ParseError(line: line, message: "unterminated [") }
                    if chars[i] == "]" { i += 1; break }
                    items.append(try value(terminators: [",", "]"]))
                    skipSpaces()
                    if i < chars.count, chars[i] == "," { i += 1 }
                }
                return .list(items)
            case "{":
                i += 1
                var entries: [(key: String, value: YAML)] = []
                while true {
                    skipSpaces()
                    guard i < chars.count else { throw YAML.ParseError(line: line, message: "unterminated {") }
                    if chars[i] == "}" { i += 1; break }
                    let key = try scalar(terminators: [":", ",", "}"])
                    skipSpaces()
                    var v = YAML.null
                    if i < chars.count, chars[i] == ":" {
                        i += 1
                        v = try value(terminators: [",", "}"])
                    }
                    entries.append((key, v))
                    skipSpaces()
                    if i < chars.count, chars[i] == "," { i += 1 }
                }
                return .map(entries)
            default:
                let s = try scalar(terminators: terminators)
                if terminators.isEmpty, ["~", "null", "Null", "NULL"].contains(s) { return .null }
                return .scalar(s)
            }
        }

        mutating func scalar(terminators: Set<Character>) throws -> String {
            skipSpaces()
            guard i < chars.count else { return "" }
            if chars[i] == "\"" || chars[i] == "'" {
                let q = chars[i]
                let start = i
                i += 1
                while i < chars.count {
                    if q == "\"", chars[i] == "\\" { i += 2; continue }
                    if chars[i] == q {
                        if q == "'", i + 1 < chars.count, chars[i + 1] == "'" { i += 2; continue }
                        break
                    }
                    i += 1
                }
                guard i < chars.count else { throw YAML.ParseError(line: line, message: "unterminated string") }
                i += 1
                return unquote(String(chars[start..<i]))
            }
            let start = i
            while i < chars.count {
                let c = chars[i]
                if terminators.contains(c) {
                    // `:` only ends a key when followed by a space.
                    if c == ":" { if i + 1 == chars.count || chars[i + 1] == " " { break } } else { break }
                }
                i += 1
            }
            return String(chars[start..<i]).trimmingCharacters(in: .whitespaces)
        }
    }
}
