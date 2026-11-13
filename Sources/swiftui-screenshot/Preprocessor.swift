import Foundation

/// Rewrites SwiftUI sources so they can be compiled into a headless runner:
///
///     #Preview("Name", ...) { body }  ->  @MainActor let __preview_N = SwiftUI._PreviewEntry("Name") { body }
///     @Previewable                     ->  (removed)
///     @main                            ->  (removed; the generated main.swift is the entry point)
///     #if os(iOS)                      ->  #if os(Linux)   (so iOS-only branches are the ones rendered)
///
/// Rewrites stay on the same line, so compiler diagnostics still point at the right line.
struct Preprocessor {
    struct Output {
        var files: [(name: String, contents: String)]
        /// Expressions producing `_PreviewEntry` values, in source order.
        var entries: [String]
    }

    private var counter = 0

    mutating func process(_ sources: [(path: String, contents: String)], viewExpression: String?) -> Output {
        var files: [(String, String)] = []
        var entries: [String] = []
        var appTypes: [String] = []
        var usedNames: Set<String> = ["main.swift"]

        for (index, source) in sources.enumerated() {
            let (rewritten, names) = rewrite(source.contents)
            entries += names
            for type in Self.matches(of: #"struct\s+(\w+)\s*:\s*[^{]*\bPreviewProvider\b"#, in: rewritten) {
                entries.append("SwiftUI._PreviewEntry(\"\(type)\") { \(type).previews }")
            }
            appTypes += Self.matches(of: #"struct\s+(\w+)\s*:\s*[^{]*\bApp\b"#, in: rewritten)
            var name = (source.path as NSString).lastPathComponent
            if usedNames.contains(name) { name = "\(index)_\(name)" }
            usedNames.insert(name)
            files.append((name, rewritten))
        }

        if let viewExpression {
            entries = ["SwiftUI._PreviewEntry(\"view\") { \(viewExpression) }"]
        } else if entries.isEmpty, let app = appTypes.first {
            entries = ["SwiftUI._PreviewEntry(app: \(app).self)"]
        }

        var main = "import SwiftUI\n\nMainActor.assumeIsolated {\n    SwiftUI._ScreenshotRunner.run([\n"
        for entry in entries { main += "        \(entry),\n" }
        main += "    ])\n}\n"
        files.append(("main.swift", main))
        return Output(files: files, entries: entries)
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Marks which UTF-8 bytes are code (as opposed to comments and string literals).
    private static func codeMask(_ bytes: [UInt8]) -> [Bool] {
        var mask = [Bool](repeating: true, count: bytes.count)
        let n = bytes.count
        var i = 0
        func at(_ k: Int) -> UInt8 { k < n ? bytes[k] : 0 }
        while i < n {
            let start = i
            if at(i) == UInt8(ascii: "/"), at(i + 1) == UInt8(ascii: "/") {
                while i < n, bytes[i] != UInt8(ascii: "\n") { i += 1 }
            } else if at(i) == UInt8(ascii: "/"), at(i + 1) == UInt8(ascii: "*") {
                var depth = 1
                i += 2
                while i < n, depth > 0 {
                    if at(i) == UInt8(ascii: "/"), at(i + 1) == UInt8(ascii: "*") { depth += 1; i += 2 }
                    else if at(i) == UInt8(ascii: "*"), at(i + 1) == UInt8(ascii: "/") { depth -= 1; i += 2 }
                    else { i += 1 }
                }
            } else if at(i) == UInt8(ascii: "\"") || (at(i) == UInt8(ascii: "#") && isRawStringStart(bytes, i)) {
                var hashes = 0
                while at(i) == UInt8(ascii: "#") { hashes += 1; i += 1 }
                let triple = at(i + 1) == UInt8(ascii: "\"") && at(i + 2) == UInt8(ascii: "\"")
                i += triple ? 3 : 1
                while i < n {
                    if bytes[i] == UInt8(ascii: "\\"), hashes == 0 { i += 2; continue }
                    if bytes[i] == UInt8(ascii: "\"") {
                        let quotes = triple ? 3 : 1
                        if !triple || (at(i + 1) == UInt8(ascii: "\"") && at(i + 2) == UInt8(ascii: "\"")) {
                            var k = i + quotes, seen = 0
                            while seen < hashes, at(k) == UInt8(ascii: "#") { seen += 1; k += 1 }
                            if seen == hashes { i = k; break }
                        }
                    }
                    if !triple, bytes[i] == UInt8(ascii: "\n") { break }
                    i += 1
                }
            } else {
                i += 1
                continue
            }
            for k in start..<min(i, n) { mask[k] = false }
        }
        return mask
    }

    private static func isRawStringStart(_ bytes: [UInt8], _ index: Int) -> Bool {
        var k = index
        while k < bytes.count, bytes[k] == UInt8(ascii: "#") { k += 1 }
        return k < bytes.count && bytes[k] == UInt8(ascii: "\"")
    }

    private mutating func rewrite(_ source: String) -> (String, [String]) {
        let bytes = Array(source.utf8)
        let mask = Self.codeMask(bytes)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 256)
        var names: [String] = []
        var i = 0
        func hasToken(_ token: String, at index: Int) -> Bool {
            let t = Array(token.utf8)
            guard index + t.count <= bytes.count, mask[index] else { return false }
            for (k, b) in t.enumerated() where bytes[index + k] != b { return false }
            // Must end at an identifier boundary.
            let next = index + t.count < bytes.count ? bytes[index + t.count] : 0
            return !(next == UInt8(ascii: "_") || (next >= 48 && next <= 57) || (next >= 65 && next <= 90) || (next >= 97 && next <= 122))
        }
        while i < bytes.count {
            if hasToken("@Previewable", at: i) {
                i += "@Previewable".utf8.count
                while i < bytes.count, bytes[i] == UInt8(ascii: " ") { i += 1 }
                continue
            }
            if hasToken("@main", at: i) {
                i += "@main".utf8.count
                continue
            }
            if hasToken("os(iOS)", at: i) {
                out += Array("os(Linux)".utf8)
                i += "os(iOS)".utf8.count
                continue
            }
            if hasToken("#Preview", at: i) {
                var j = i + "#Preview".utf8.count
                var name = "nil"
                var k = j
                while k < bytes.count, bytes[k] == UInt8(ascii: " ") || bytes[k] == UInt8(ascii: "\t") { k += 1 }
                if k < bytes.count, bytes[k] == UInt8(ascii: "(") {
                    // Skip the argument list; keep a leading string literal as the preview's name.
                    var depth = 0, close = k
                    while close < bytes.count {
                        if mask[close] {
                            if bytes[close] == UInt8(ascii: "(") { depth += 1 }
                            if bytes[close] == UInt8(ascii: ")") { depth -= 1; if depth == 0 { break } }
                        }
                        close += 1
                    }
                    var a = k + 1
                    while a < close, bytes[a] == UInt8(ascii: " ") || bytes[a] == UInt8(ascii: "\n") { a += 1 }
                    if a < close, bytes[a] == UInt8(ascii: "\"") {
                        var b = a + 1
                        while b < close, !(bytes[b] == UInt8(ascii: "\"") && bytes[b - 1] != UInt8(ascii: "\\")) { b += 1 }
                        name = String(decoding: bytes[a...b], as: UTF8.self)
                    }
                    j = close + 1
                }
                let identifier = "__preview_\(counter)"
                counter += 1
                names.append(identifier)
                out += Array("@MainActor let \(identifier) = SwiftUI._PreviewEntry(\(name))".utf8)
                i = j
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        return (String(decoding: out, as: UTF8.self), names)
    }
}
