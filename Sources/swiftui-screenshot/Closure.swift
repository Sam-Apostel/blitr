import Foundation

// Dependency-closure compile: an app target is all-or-nothing for the compiler, so one file using an
// unsupported framework would block every screen. Instead the entry file is compiled together with
// the files that declare what it (transitively) references.
//
// This is a token-level analysis, not a type checker, and it errs on the side of including files:
//   - a file is included when it declares a top-level name (type, function, variable, typealias,
//     protocol, operator, macro) that an included file mentions;
//   - nested declarations are reached through their top-level parent, so they do not pull files in;
//   - an extension of a type declared in an included file is included when it adds a conformance, when an
//     included file mentions one of its members, or when a member is named like a protocol requirement;
//   - an extension of any other type (View, Color, a package's type) is included when an included file
//     mentions one of its members, or when it adds a conformance to a type an included file mentions;
//   - identifiers are collected from code and from string interpolations, never from comments.
// Tokens inside inactive `#if` branches count too, which only ever adds files.

struct SwiftFileIndex {
    struct Extension {
        var type: String
        var members: Set<String>
        var hasConformance: Bool
    }
    /// Top-level declared names.
    var declarations: Set<String> = []
    /// Types declared anywhere in the file, nested ones included (they make the file part of the type's closure).
    var types: Set<String> = []
    var extensions: [Extension] = []
    /// Every identifier and operator mentioned in code.
    var references: Set<String> = []
    var importsModules: Set<String> = []
    var hasPreviews = false
    var hasMainApp = false
}

enum SwiftLexer {
    struct Token {
        enum Kind { case identifier, keyword, attribute, pound, op, punct, string, number }
        var kind: Kind
        var text: String
        var start: Int
        var end: Int
    }

    static let keywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open",
        "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var",
        "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
        "throw", "switch", "where", "while", "as", "Any", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try", "await",
        "actor", "macro", "package", "nonisolated", "async", "some", "any", "final", "override", "mutating", "lazy", "weak", "unowned",
        "convenience", "required", "dynamic", "indirect", "optional", "get", "set", "willSet", "didSet", "consuming", "borrowing", "each",
    ]

    static func isIdentifierStart(_ b: UInt8) -> Bool { b == 95 || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b >= 0x80 }
    static func isIdentifierBody(_ b: UInt8) -> Bool { isIdentifierStart(b) || (b >= 48 && b <= 57) }
    static let operatorChars: Set<UInt8> = Set("/=-+!*%<>&|^~?.".utf8)

    /// Tokens of `source`. String literal contents are skipped but their interpolations are lexed.
    static func tokens(_ bytes: [UInt8]) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        let n = bytes.count
        func at(_ k: Int) -> UInt8 { k < n ? bytes[k] : 0 }

        /// Lexes a string literal starting at `i` (after any `#`s), appending interpolation tokens.
        func string(hashes: Int) {
            let start = i - hashes
            let triple = at(i) == 34 && at(i + 1) == 34 && at(i + 2) == 34
            i += triple ? 3 : 1
            while i < n {
                let c = bytes[i]
                if c == 92 {  // backslash
                    var k = i + 1
                    var seen = 0
                    while seen < hashes, at(k) == 35 { seen += 1; k += 1 }
                    if seen == hashes, at(k) == 40 {  // \( interpolation )
                        i = k + 1
                        var depth = 1
                        while i < n, depth > 0 {
                            let before = tokens.count
                            lexOne()
                            if tokens.count > before {
                                let t = tokens[tokens.count - 1]
                                if t.kind == .punct && t.text == "(" { depth += 1 }
                                if t.kind == .punct && t.text == ")" { depth -= 1; if depth == 0 { tokens.removeLast() } }
                            }
                        }
                        continue
                    }
                    i += hashes == 0 ? 2 : 1
                    continue
                }
                if c == 34 {
                    if !triple || (at(i + 1) == 34 && at(i + 2) == 34) {
                        var k = i + (triple ? 3 : 1)
                        var seen = 0
                        while seen < hashes, at(k) == 35 { seen += 1; k += 1 }
                        if seen == hashes { i = k; break }
                    }
                }
                if !triple, c == 10 { break }
                i += 1
            }
            tokens.append(Token(kind: .string, text: "", start: start, end: i))
        }

        func lexOne() {
            let c = bytes[i]
            if c == 32 || c == 9 || c == 10 || c == 13 { i += 1; return }
            if c == 47, at(i + 1) == 47 { while i < n, bytes[i] != 10 { i += 1 }; return }
            if c == 47, at(i + 1) == 42 {
                var depth = 1
                i += 2
                while i < n, depth > 0 {
                    if at(i) == 47, at(i + 1) == 42 { depth += 1; i += 2 }
                    else if at(i) == 42, at(i + 1) == 47 { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                return
            }
            if c == 34 { string(hashes: 0); return }
            if c == 35 {  // #
                var k = i
                while at(k) == 35 { k += 1 }
                if at(k) == 34 { let hashes = k - i; i = k; string(hashes: hashes); return }
                let start = i
                i += 1
                while i < n, isIdentifierBody(bytes[i]) { i += 1 }
                tokens.append(Token(kind: .pound, text: String(decoding: bytes[(start + 1)..<i], as: UTF8.self), start: start, end: i))
                return
            }
            if c == 64 {  // @
                let start = i
                i += 1
                while i < n, isIdentifierBody(bytes[i]) { i += 1 }
                tokens.append(Token(kind: .attribute, text: String(decoding: bytes[(start + 1)..<i], as: UTF8.self), start: start, end: i))
                return
            }
            if c == 96 {  // `escaped`
                let start = i
                i += 1
                while i < n, bytes[i] != 96, bytes[i] != 10 { i += 1 }
                let text = String(decoding: bytes[(start + 1)..<min(i, n)], as: UTF8.self)
                i += 1
                tokens.append(Token(kind: .identifier, text: text, start: start, end: i))
                return
            }
            if c == 36 || isIdentifierStart(c) {  // $0, identifiers
                let start = i
                i += 1
                while i < n, isIdentifierBody(bytes[i]) { i += 1 }
                let text = String(decoding: bytes[start..<i], as: UTF8.self)
                tokens.append(Token(kind: keywords.contains(text) ? .keyword : .identifier, text: text, start: start, end: i))
                return
            }
            if c >= 48 && c <= 57 {
                let start = i
                while i < n, isIdentifierBody(bytes[i]) || bytes[i] == 46 && at(i + 1) >= 48 && at(i + 1) <= 57 { i += 1 }
                tokens.append(Token(kind: .number, text: "", start: start, end: i))
                return
            }
            if operatorChars.contains(c) {
                let start = i
                // `.` alone is member access; a run like `..<` or `...` is an operator.
                if c == 46, !(at(i + 1) == 46) { i += 1; tokens.append(Token(kind: .punct, text: ".", start: start, end: i)); return }
                while i < n, operatorChars.contains(bytes[i]) {
                    if bytes[i] == 47, at(i + 1) == 47 || at(i + 1) == 42 { break }
                    i += 1
                }
                tokens.append(Token(kind: .op, text: String(decoding: bytes[start..<i], as: UTF8.self), start: start, end: i))
                return
            }
            i += 1
            tokens.append(Token(kind: .punct, text: String(UnicodeScalar(c)), start: i - 1, end: i))
        }

        while i < n { lexOne() }
        return tokens
    }
}

enum SwiftIndexer {
    static let declarationKeywords: Set<String> = ["struct", "class", "enum", "actor", "protocol", "typealias", "func", "var", "let", "macro",
                                                   "associatedtype", "case", "subscript", "init"]
    static let typeKeywords: Set<String> = ["struct", "class", "enum", "actor", "protocol"]

    static func index(_ bytes: [UInt8]) -> SwiftFileIndex {
        let tokens = SwiftLexer.tokens(bytes)
        var index = SwiftFileIndex()
        // Scope stack: what each open `{` belongs to.
        enum Scope { case type(String), extensionOf(Int), body }
        var stack: [Scope] = []
        var pendingScope: Scope?
        var parenDepth = 0

        func directScope() -> Scope? { stack.last }
        var k = 0
        while k < tokens.count {
            let t = tokens[k]
            switch t.kind {
            case .identifier:
                index.references.insert(t.text)
            case .attribute:
                index.references.insert(t.text)
                if t.text == "main" { index.hasMainApp = true }
            case .pound:
                index.references.insert(t.text)
                if t.text == "Preview" { index.hasPreviews = true }
            case .op:
                index.references.insert(t.text)
            case .keyword:
                let next = k + 1 < tokens.count ? tokens[k + 1] : nil
                if t.text == "import", let next, next.kind == .identifier || next.kind == .keyword {
                    // `import struct Foo.Bar`, `@testable import Foo`
                    var m = k + 1
                    if ["struct", "class", "enum", "protocol", "typealias", "func", "var", "let"].contains(tokens[m].text), m + 1 < tokens.count { m += 1 }
                    index.importsModules.insert(tokens[m].text)
                }
                let atTopLevel = stack.isEmpty
                let inTypeScope: Bool = { if case .type = directScope() { return true }; if case .extensionOf = directScope() { return true }; return false }()
                if t.text == "extension", let next {
                    // `extension A.B<T>: P where ...`
                    var m = k + 1
                    var name = next.text
                    while m + 2 < tokens.count, tokens[m + 1].text == ".", tokens[m + 2].kind == .identifier { name = tokens[m + 2].text; m += 2 }
                    if atTopLevel {
                        index.references.insert(next.text)
                        index.extensions.append(.init(type: next.text, members: [], hasConformance: false))
                        // Find the scope's `{`; a `:` before it means a conformance.
                        var q = m + 1
                        var conformance = false
                        while q < tokens.count, tokens[q].text != "{" { if tokens[q].text == ":" { conformance = true }; q += 1 }
                        index.extensions[index.extensions.count - 1].hasConformance = conformance
                        pendingScope = .extensionOf(index.extensions.count - 1)
                    } else {
                        pendingScope = .body
                    }
                    _ = name
                } else if declarationKeywords.contains(t.text) || t.text == "operator" {
                    var names: [String] = []
                    if t.text == "operator", k > 0 {
                        // `infix operator <>`: the operator token is next
                        if let next, next.kind == .op { names.append(next.text) }
                    } else if t.text == "case" && inTypeScope {
                        // enum cases: `case a, b(Int), c = 1`
                        var m = k + 1
                        var depth = 0
                        var expectName = true
                        while m < tokens.count {
                            let u = tokens[m]
                            let newLine = bytes[tokens[m - 1].end..<u.start].contains(10)
                            if depth == 0, newLine, tokens[m - 1].text != "," { break }
                            if depth == 0, u.kind == .keyword || u.kind == .attribute || u.kind == .pound || u.text == "{" || u.text == "}" { break }
                            if u.text == "(" || u.text == "[" { depth += 1 }
                            else if u.text == ")" || u.text == "]" { depth -= 1 }
                            else if depth == 0, u.text == "," { expectName = true }
                            else if depth == 0, expectName, u.kind == .identifier { names.append(u.text); expectName = false }
                            m += 1
                        }
                    } else if t.text == "case" || t.text == "init" || t.text == "subscript" {
                        // pattern `case` in a switch, or initializers: no name
                    } else if let next {
                        if next.kind == .identifier { names.append(next.text) }
                        else if next.kind == .op { names.append(next.text) }
                        else if next.text == "(" && (t.text == "var" || t.text == "let") {
                            // `let (a, b) = ...`
                            var m = k + 2
                            while m < tokens.count, tokens[m].text != ")" { if tokens[m].kind == .identifier { names.append(tokens[m].text) }; m += 1 }
                        }
                        // `var a = 1, b = 2` at top level is rare; the first name is enough to be conservative only if the rest is referenced
                    }
                    if typeKeywords.contains(t.text), let name = names.first {
                        index.types.insert(name)
                        pendingScope = .type(name)
                    } else if t.text == "func" || t.text == "init" || t.text == "subscript" || t.text == "var" || t.text == "let" {
                        pendingScope = .body
                    }
                    for name in names {
                        if atTopLevel { index.declarations.insert(name) }
                        else if case .extensionOf(let e) = directScope() { index.extensions[e].members.insert(name) }
                    }
                }
            case .punct:
                switch t.text {
                case "{":
                    stack.append(pendingScope ?? .body)
                    pendingScope = nil
                case "}":
                    if !stack.isEmpty { stack.removeLast() }
                case "(": parenDepth += 1
                case ")": parenDepth -= 1
                default: break
                }
            case .string, .number:
                break
            }
            k += 1
        }
        return index
    }
}

enum PreviewStripper {
    /// Blanks `#Preview { ... }` blocks and `PreviewProvider` types (with the attributes and modifiers
    /// before them), keeping every newline so line numbers do not move. Used for every file except the
    /// entry file: their previews would otherwise be registered and pull in more of the target.
    static func strip(_ source: String) -> String {
        guard source.contains("#Preview") || source.contains("PreviewProvider") else { return source }
        var bytes = Array(source.utf8)
        let tokens = SwiftLexer.tokens(bytes)
        var ranges: [Range<Int>] = []

        func matchingClose(from open: Int, _ openText: String, _ closeText: String) -> Int? {
            var depth = 0
            var m = open
            while m < tokens.count {
                if tokens[m].kind == .punct {
                    if tokens[m].text == openText { depth += 1 }
                    if tokens[m].text == closeText { depth -= 1; if depth == 0 { return m } }
                }
                m += 1
            }
            return nil
        }
        /// Index of the first token of the attributes/modifiers directly before token `k`.
        func leadingStart(_ k: Int) -> Int {
            var s = k
            let modifiers: Set<String> = ["private", "fileprivate", "internal", "public", "final", "nonisolated"]
            while s > 0 {
                let p = tokens[s - 1]
                if p.kind == .keyword, modifiers.contains(p.text) { s -= 1; continue }
                if p.kind == .attribute { s -= 1; continue }
                if p.text == ")" , let open = (0..<(s - 1)).reversed().first(where: { tokens[$0].text == "(" && matchingClose(from: $0, "(", ")") == s - 1 }),
                   open > 0, tokens[open - 1].kind == .attribute {
                    s = open - 1; continue
                }
                break
            }
            return s
        }

        var k = 0
        while k < tokens.count {
            let t = tokens[k]
            if t.kind == .pound, t.text == "Preview" {
                var m = k + 1
                if m < tokens.count, tokens[m].text == "(", let close = matchingClose(from: m, "(", ")") { m = close + 1 }
                if m < tokens.count, tokens[m].text == "{", var close = matchingClose(from: m, "{", "}") {
                    // Widget previews continue with labeled closures: `} timeline: { ... }`, `} contentStates: { ... }`.
                    while close + 3 < tokens.count, tokens[close + 1].kind == .identifier, tokens[close + 2].text == ":", tokens[close + 3].text == "{",
                          let next = matchingClose(from: close + 3, "{", "}") {
                        close = next
                    }
                    ranges.append(tokens[leadingStart(k)].start..<tokens[close].end)
                    k = close + 1
                    continue
                }
            }
            if t.kind == .keyword, t.text == "struct" || t.text == "enum", k + 1 < tokens.count {
                // struct Name: ..., PreviewProvider ... {
                var m = k + 2
                var isPreviewProvider = false
                while m < tokens.count, tokens[m].text != "{" {
                    if tokens[m].text == "PreviewProvider" { isPreviewProvider = true }
                    m += 1
                }
                if isPreviewProvider, m < tokens.count, let close = matchingClose(from: m, "{", "}") {
                    ranges.append(tokens[leadingStart(k)].start..<tokens[close].end)
                    k = close + 1
                    continue
                }
            }
            k += 1
        }
        for range in ranges {
            for b in range where bytes[b] != 10 { bytes[b] = 32 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension PreviewStripper {
    /// Blanks the `@main struct X: App { ... }` of a file (keeping newlines), for builds that render a
    /// preview or `--view`: the App's body names the whole app, and nothing else needs the App type.
    static func stripMainApp(_ source: String) -> String {
        guard source.contains("@main") else { return source }
        var bytes = Array(source.utf8)
        let tokens = SwiftLexer.tokens(bytes)
        var k = 0
        while k < tokens.count {
            defer { k += 1 }
            guard tokens[k].kind == .attribute, tokens[k].text == "main" else { continue }
            var m = k + 1
            while m < tokens.count, tokens[m].kind == .keyword, tokens[m].text != "struct" { m += 1 }
            guard m < tokens.count, tokens[m].text == "struct" else { continue }
            var open = m
            var isApp = false
            while open < tokens.count, tokens[open].text != "{" {
                if tokens[open].text == "App" { isApp = true }
                open += 1
            }
            guard isApp, open < tokens.count else { continue }
            var depth = 0
            var close = open
            while close < tokens.count {
                if tokens[close].kind == .punct, tokens[close].text == "{" { depth += 1 }
                if tokens[close].kind == .punct, tokens[close].text == "}" { depth -= 1; if depth == 0 { break } }
                close += 1
            }
            guard close < tokens.count else { continue }
            for b in tokens[k].start..<tokens[close].end where bytes[b] != 10 { bytes[b] = 32 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return source
    }
}

enum DependencyClosure {
    /// Members that commonly satisfy a protocol requirement without being mentioned by name.
    static let requirementNames: Set<String> = ["body", "id", "hash", "encode", "description", "debugDescription", "makeBody",
                                                "makeUIView", "updateUIView", "makeUIViewController", "updateUIViewController",
                                                "makeCoordinator", "sizeThatFits", "placeSubviews", "path", "reduce", "defaultValue",
                                                "allCases", "rawValue", "makeIterator", "next", "startIndex", "endIndex", "index"]

    struct Result {
        var files: [String]
        /// file -> why it was included (the name that pulled it in), for `-v`.
        var reasons: [String: String]
    }

    /// The files of `indexes` needed by the roots, in the order of `indexes`.
    static func compute(roots: [String], extraReferences: Set<String>, indexes: [(path: String, index: SwiftFileIndex)]) -> Result {
        var included = Set(roots)
        var reasons: [String: String] = [:]
        for root in roots { reasons[root] = "entry" }
        let targetTypes = Set(indexes.flatMap { $0.index.types })

        var references = extraReferences
        var closureTypes: Set<String> = []
        var frontier = indexes.filter { included.contains($0.path) }.map(\.index)
        var changed = true
        while changed {
            changed = false
            for index in frontier {
                references.formUnion(index.references)
                closureTypes.formUnion(index.types)
            }
            frontier = []
            for entry in indexes where !included.contains(entry.path) {
                var reason: String?
                if let name = entry.index.declarations.first(where: { references.contains($0) }) {
                    reason = "declares \(name)"
                } else {
                    for ext in entry.index.extensions {
                        if closureTypes.contains(ext.type) {
                            // An extension of a type in the closure: needed when it adds a conformance, when one of its
                            // members is mentioned, or when it may implement a protocol requirement of the type
                            // (members named like common requirements). Others only add unused API.
                            if ext.hasConformance { reason = "adds a conformance to \(ext.type)"; break }
                            if let member = ext.members.first(where: { references.contains($0) || DependencyClosure.requirementNames.contains($0) }) {
                                reason = "extends \(ext.type) with \(member)"; break
                            }
                            if ext.members.isEmpty { reason = "extends \(ext.type)"; break }
                            continue
                        }
                        if targetTypes.contains(ext.type) { continue }   // waits until that type is in the closure
                        if let member = ext.members.first(where: { references.contains($0) }) { reason = "extends \(ext.type) with \(member)"; break }
                        if ext.hasConformance, references.contains(ext.type) { reason = "adds a conformance to \(ext.type)"; break }
                    }
                }
                if let reason {
                    included.insert(entry.path)
                    reasons[entry.path] = reason
                    frontier.append(entry.index)
                    changed = true
                }
            }
        }
        return Result(files: indexes.map(\.path).filter { included.contains($0) }, reasons: reasons)
    }
}
