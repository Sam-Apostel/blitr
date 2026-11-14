import Foundation

/// Rewrites SwiftUI sources so they can be compiled into a headless runner:
///
///     #Preview("Name", ...) { body }  ->  @MainActor let __preview_N = SwiftUI._PreviewEntry("Name") { body }
///     #Preview(as: .systemSmall) { W() } timeline: { ... }  ->  ... = WidgetKit._WidgetPreview(as: .systemSmall) { W() } timeline: { ... }
///                                     (widget and Live Activity previews keep their arguments; see docs/WIDGETS.md)
///     @Previewable                     ->  (removed)
///     @main                            ->  (removed; the generated main.swift is the entry point)
///     #if os(iOS)                      ->  #if os(Linux)   (for the platform being rendered: its branches are kept;
///                                                           os(macOS) when the tool runs on a Mac, see hostOS)
///     #if os(Linux)                    ->  #if false       (the code is rendered as an Apple platform)
///     #if canImport(UIKit)             ->  #if false       (on platforms without the framework; see frameworkPlatforms)
///     import SwiftUI                   ->  import SwiftUI; import UIKit   (iOS, tvOS, visionOS: SwiftUI re-exports UIKit there)
///     @objc, @IBAction, @IBOutlet      ->  (removed: there is no Objective-C runtime on Linux)
///     .accessoryCorner                 ->  ._accessoryCorner   (WidgetKit's watchOS family; see WidgetFamily)
///     #Rule(Self.$x) { ... }           ->  TipKit.Tips.Rule(Self.$x) { ... }   (TipKit's macro)
///     #selector(tap(_:))               ->  Selector("tap(_:)")   (ObjectiveC's Selector, which UIKit re-exports)
///     import CoreImage.CIFilterBuiltins ->  import CoreImage   (the shims are Swift modules, without submodules)
///     @Entry var x: T = v              ->  an explicit EnvironmentKey + computed property
///     #available(iOS 26, *)            ->  SwiftUI.RenderedPlatform.isAtLeast(iOS: 26)
///     #unavailable(iOS 26)             ->  !SwiftUI.RenderedPlatform.isAtLeast(iOS: 26)
///     formatter.monthSymbols?[i]       ->  formatter.monthSymbols[i]   (implicitly unwrapped on Apple; see implicitlyUnwrappedSymbols)
///     extension UIWindow { override func motionEnded(...) { ... } }  ->  the override is blanked out, with a warning
///                                     (see dropExtensionOverrides)
///
/// Rewrites stay on the same line, so compiler diagnostics still point at the right line.
struct Preprocessor {
    struct Output {
        var files: [(name: String, contents: String)]
        /// Expressions producing `_PreviewEntry` values, in source order.
        var entries: [String]
        /// One line per member left out (`file:line: ...`), for the tool to print as warnings.
        var warnings: [String] = []
    }

    private var counter = 0
    /// Set when a widget preview was rewritten: main.swift then expands preview groups.
    private var hasWidgetPreviews = false
    /// The Apple platform being rendered, as Swift spells it in `os(...)` and `#available(...)`:
    /// iOS, tvOS, watchOS, macOS or visionOS. Its branches are the ones kept.
    var platform = "iOS"
    /// The operating system the code is compiled on, as `os(...)` spells it (HostPlatform.osName in the tool).
    /// The rendered platform's `os(...)` checks become checks for it, and its own become false. Stays "Linux"
    /// in the reference-capture driver (scripts/mac/host), which turns `os(Linux)` back into the platform.
    var hostOS = "Linux"

    mutating func process(_ sources: [(path: String, contents: String)], viewExpression: String?) -> Output {
        var files: [(String, String)] = []
        var entries: [String] = []
        var appTypes: [String] = []
        var widgetTypes: [String] = [], bundleTypes: [String] = []
        var usedNames: Set<String> = ["main.swift"]
        var warnings: [String] = []

        for (index, source) in sources.enumerated() {
            let (kept, dropped) = Self.dropExtensionOverrides(source.contents, path: source.path)
            warnings += dropped
            var (rewritten, names) = rewrite(kept)
            rewritten = Self.rewriteEntries(rewritten)
            entries += names
            for type in Self.matches(of: #"struct\s+(\w+)\s*:\s*[^{]*\bPreviewProvider\b"#, in: rewritten) {
                entries.append("SwiftUI._PreviewEntry(\"\(type)\") { \(type).previews }")
            }
            appTypes += Self.matches(of: #"struct\s+(\w+)\s*:\s*(?:[^{\n]*,\s*)?(?:SwiftUI\.)?App\b"#, in: rewritten)
            widgetTypes += Self.matches(of: #"struct\s+(\w+)\s*:\s*(?:[^{\n]*,\s*)?(?:WidgetKit\.)?Widget\b"#, in: rewritten)
            bundleTypes += Self.matches(of: #"struct\s+(\w+)\s*:\s*(?:[^{\n]*,\s*)?(?:WidgetKit\.)?WidgetBundle\b"#, in: rewritten)
            var name = (source.path as NSString).lastPathComponent
            if usedNames.contains(name) { name = "\(index)_\(name)" }
            usedNames.insert(name)
            files.append((name, rewritten))
        }

        if let viewExpression {
            entries = ["SwiftUI._PreviewEntry(\"view\") { \(viewExpression) }"]
        } else if entries.isEmpty, let app = appTypes.first {
            // No previews: launch the app instead (its first WindowGroup is rendered).
            entries = ["SwiftUI._PreviewEntry(app: \(app)())"]
        } else if entries.isEmpty, !bundleTypes.isEmpty || !widgetTypes.isEmpty {
            // A widget extension without previews: render its widgets from their providers.
            entries = bundleTypes.first.map { ["WidgetKit._WidgetPreview(bundle: \($0)())"] }
                ?? widgetTypes.map { "WidgetKit._WidgetPreview(widget: \($0)())" }
            hasWidgetPreviews = true
        }

        var main = "import SwiftUI\n\nMainActor.assumeIsolated {\n    SwiftUI._ScreenshotRunner.run([\n"
        if hasWidgetPreviews {
            // Widget previews expand to one image per family, timeline entry or content state.
            // `_WidgetPreview` is WidgetKit's, which declares the widget API.
            main = "import SwiftUI\nimport WidgetKit\n\nMainActor.assumeIsolated {\n    SwiftUI._ScreenshotRunner.run(([\n"
        }
        for entry in entries { main += "        \(entry),\n" }
        main += hasWidgetPreviews ? "    ] as [any SwiftUI._PreviewEntryGroup]).flatMap { $0._previewEntries })\n}\n" : "    ])\n}\n"
        files.append(("main.swift", main))
        return Output(files: files, entries: entries, warnings: warnings)
    }

    /// Overrides declared in an extension (`extension UIWindow { override func motionEnded(...) }`) compile on Apple
    /// platforms only because the overridden member is `@objc dynamic`: Swift accepts an override in an extension
    /// for Objective-C members alone, which here are UIKit's and AppKit's. Linux has no Objective-C runtime, so such
    /// an override cannot compile; it is a behaviour hook (view lifecycle, shake, key commands) that never shows in a
    /// still frame, so it is removed, brace-matched, keeping its newlines so later lines keep their numbers. Overrides
    /// in class bodies are untouched.
    static func dropExtensionOverrides(_ source: String, path: String) -> (String, [String]) {
        guard source.contains("override") else { return (source, []) }
        var bytes = Array(source.utf8)
        let mask = codeMask(bytes)
        let n = bytes.count
        func isSpace(_ b: UInt8) -> Bool { b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") }
        func word(at k: Int) -> String {
            var e = k
            while e < n, isIdentifierByte(bytes[e]) || bytes[e] == UInt8(ascii: ".") { e += 1 }
            return String(decoding: bytes[k..<e], as: UTF8.self)
        }
        func isKeyword(_ keyword: String, at k: Int) -> Bool {
            let t = Array(keyword.utf8)
            guard mask[k], k + t.count <= n, Array(bytes[k..<(k + t.count)]) == t else { return false }
            if k > 0, isIdentifierByte(bytes[k - 1]) || bytes[k - 1] == UInt8(ascii: ".") { return false }
            return k + t.count == n || !isIdentifierByte(bytes[k + t.count])
        }
        enum Frame { case extensionBody(String), other }
        var frames: [Frame] = []
        var pendingExtension: String?
        var removals: [(start: Int, end: Int, line: Int, type: String, signature: String)] = []
        var i = 0
        while i < n {
            guard mask[i] else { i += 1; continue }
            let b = bytes[i]
            if b == UInt8(ascii: "{") {
                frames.append(pendingExtension.map { .extensionBody($0) } ?? .other)
                pendingExtension = nil
            } else if b == UInt8(ascii: "}") {
                _ = frames.popLast()
            } else if isKeyword("extension", at: i) {
                var k = i + "extension".utf8.count
                while k < n, isSpace(bytes[k]) { k += 1 }
                pendingExtension = word(at: k)
            } else if isKeyword("override", at: i), case .extensionBody(let type)? = frames.last {
                // The declaration starts at its first modifier or attribute on this line, and takes attribute-only lines above it.
                var start = i
                while start > 0, mask[start - 1], bytes[start - 1] != UInt8(ascii: "\n"), bytes[start - 1] != UInt8(ascii: "{"),
                      bytes[start - 1] != UInt8(ascii: "}"), bytes[start - 1] != UInt8(ascii: ";") { start -= 1 }
                while start < i, isSpace(bytes[start]) { start += 1 }
                var head = start
                while head > 0, isSpace(bytes[head - 1]) { head -= 1 }
                while head > 0, bytes[head - 1] == UInt8(ascii: "\n") {
                    var lineStart = head - 1
                    while lineStart > 0, bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
                    var first = lineStart
                    while first < head - 1, isSpace(bytes[first]) { first += 1 }
                    guard first < head - 1, bytes[first] == UInt8(ascii: "@"), mask[first] else { break }
                    start = first
                    head = lineStart
                }
                // The body: the first `{` outside parentheses (default arguments may hold closures), brace-matched.
                var k = i, parens = 0
                while k < n, !(mask[k] && parens == 0 && bytes[k] == UInt8(ascii: "{")) {
                    if mask[k], bytes[k] == UInt8(ascii: "(") { parens += 1 }
                    if mask[k], bytes[k] == UInt8(ascii: ")") { parens -= 1 }
                    k += 1
                }
                guard k < n else { break }
                let signature = String(decoding: bytes[i..<k], as: UTF8.self)
                    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                var depth = 0, end = k
                while end < n {
                    if mask[end], bytes[end] == UInt8(ascii: "{") { depth += 1 }
                    if mask[end], bytes[end] == UInt8(ascii: "}") { depth -= 1; if depth == 0 { end += 1; break } }
                    end += 1
                }
                removals.append((start, end, bytes[..<i].filter { $0 == UInt8(ascii: "\n") }.count + 1, type, signature))
                i = end
                continue
            }
            i += 1
        }
        guard !removals.isEmpty else { return (source, []) }
        let file = (path as NSString).lastPathComponent
        var warnings: [String] = []
        for removal in removals.reversed() {
            warnings.insert("\(file):\(removal.line): left out `\(removal.signature)` in `extension \(removal.type)`: overriding from an extension needs the Objective-C runtime (a behaviour hook, not drawn in a still frame)", at: 0)
            let newlines = bytes[removal.start..<removal.end].filter { $0 == UInt8(ascii: "\n") }
            bytes.replaceSubrange(removal.start..<removal.end, with: newlines)
        }
        return (String(decoding: bytes, as: UTF8.self), warnings)
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

    /// `@Entry var foo: T = v` inside `extension EnvironmentValues` (or `FocusedValues`) becomes an
    /// explicit key type plus a computed property, since macros are not available here.
    static func rewriteEntries(_ source: String) -> String {
        guard source.contains("@Entry") else { return source }
        let bytes = Array(source.utf8)
        let mask = codeMask(bytes)
        let token = Array("@Entry".utf8)
        var out: [UInt8] = []
        var i = 0

        func isIdentifier(_ b: UInt8) -> Bool {
            b == UInt8(ascii: "_") || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
        }
        func skipSpaces(_ k: Int) -> Int {
            var k = k
            while k < bytes.count, bytes[k] == UInt8(ascii: " ") || bytes[k] == UInt8(ascii: "\t") { k += 1 }
            return k
        }
        func word(at k: Int) -> (String, Int) {
            var e = k
            while e < bytes.count, isIdentifier(bytes[e]) { e += 1 }
            return (String(decoding: bytes[k..<e], as: UTF8.self), e)
        }
        /// End of a type annotation or initializer expression: end of line at bracket depth zero.
        func declarationEnd(from start: Int, isType: Bool) -> Int {
            var depth = 0, k = start
            while k < bytes.count {
                let c = bytes[k]
                if mask[k] {
                    if c == UInt8(ascii: "(") || c == UInt8(ascii: "[") || c == UInt8(ascii: "{") { depth += 1 }
                    else if c == UInt8(ascii: ")") || c == UInt8(ascii: "]") || c == UInt8(ascii: "}") {
                        if depth == 0 { return k }
                        depth -= 1
                    } else if isType, c == UInt8(ascii: "<") { depth += 1 }
                    else if isType, c == UInt8(ascii: ">"), bytes[k - 1] != UInt8(ascii: "-") { depth -= 1 }
                    else if depth == 0 {
                        if c == UInt8(ascii: "\n") { return k }
                        if isType, c == UInt8(ascii: "="), k + 1 < bytes.count, bytes[k + 1] != UInt8(ascii: "=") { return k }
                    }
                }
                k += 1
            }
            return bytes.count
        }
        func text(_ range: Range<Int>) -> String {
            String(decoding: bytes[range], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }

        var owner: String?
        var scan = 0
        while scan < bytes.count {
            // Track the most recent `extension Name` so we know which key protocol applies.
            if mask[scan], bytes[scan] == UInt8(ascii: "e"), scan + 10 < bytes.count,
               String(decoding: bytes[scan..<(scan + 10)], as: UTF8.self) == "extension ",
               scan == 0 || !isIdentifier(bytes[scan - 1]) {
                owner = word(at: skipSpaces(scan + 10)).0
            }
            guard mask[scan], scan + token.count <= bytes.count, Array(bytes[scan..<(scan + token.count)]) == token,
                  scan + token.count < bytes.count, !isIdentifier(bytes[scan + token.count]),
                  owner == "EnvironmentValues" || owner == "FocusedValues" else { scan += 1; continue }

            var k = skipSpaces(scan + token.count)
            let modifiersStart = k
            var modifiersEnd = k
            let modifiers: Set<String> = ["public", "internal", "private", "fileprivate", "package", "open", "nonisolated", "static", "final"]
            while true {
                let (w, e) = word(at: k)
                guard modifiers.contains(w) else { break }
                var next = e
                if next < bytes.count, bytes[next] == UInt8(ascii: "(") { while next < bytes.count, bytes[next] != UInt8(ascii: ")") { next += 1 }; next += 1 }
                k = skipSpaces(next)
                modifiersEnd = k
            }
            let (keyword, afterKeyword) = word(at: k)
            guard keyword == "var" else { scan += 1; continue }
            let (name, afterName) = word(at: skipSpaces(afterKeyword))
            k = skipSpaces(afterName)
            var type: String?, defaultValue: String?
            if k < bytes.count, bytes[k] == UInt8(ascii: ":") {
                let end = declarationEnd(from: k + 1, isType: true)
                type = text((k + 1)..<end)
                k = skipSpaces(end)
            }
            if k < bytes.count, bytes[k] == UInt8(ascii: "=") {
                let end = declarationEnd(from: k + 1, isType: false)
                defaultValue = text((k + 1)..<end)
                k = end
            }
            let key = "__Entry_" + name
            let mods = String(decoding: bytes[modifiersStart..<modifiersEnd], as: UTF8.self)
            let accessor = "{ get { self[\(key).self] } set { self[\(key).self] = newValue } }"
            var replacement: String?
            if owner == "FocusedValues" {
                if let type {
                    let value = type.hasSuffix("?") ? String(type.dropLast()) : type
                    replacement = "struct \(key): FocusedValueKey { typealias Value = \(value) }; \(mods)var \(name): \(type) \(accessor)"
                }
            } else {
                if defaultValue == nil, let type, type.hasSuffix("?") { defaultValue = "nil" }
                if let defaultValue {
                    let annotation = type.map { ": " + $0 } ?? ""
                    replacement = "struct \(key): EnvironmentKey { static let defaultValue\(annotation) = \(defaultValue) }; \(mods)var \(name): \(type ?? key + ".Value") \(accessor)"
                }
            }
            guard let replacement else { scan += 1; continue }
            out += bytes[i..<scan]
            out += Array(replacement.utf8)
            i = k
            scan = k
        }
        out += bytes[i...]
        return String(decoding: out, as: UTF8.self)
    }

    /// Turns `.landscapeLeft, .fixedLayout(width: 300, height: 200)` into `, orientation: "landscapeLeft", layout: "fixed", width: 300, height: 200`.
    static func traitArguments(_ text: String) -> String {
        var result = ""
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\.landscapeLeft\b"#) { result += ", orientation: \"landscapeLeft\"" }
        else if has(#"\.landscapeRight\b"#) { result += ", orientation: \"landscapeRight\"" }
        else if has(#"\.portrait(UpsideDown)?\b"#) { result += ", orientation: \"portrait\"" }
        if has(#"\.sizeThatFitsLayout\b"#) {
            result += ", layout: \"fit\""
        } else if let regex = try? NSRegularExpression(pattern: #"\.fixedLayout\s*\(\s*width:\s*([0-9.]+)\s*,\s*height:\s*([0-9.]+)\s*\)"#),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let ns = text as NSString
            result += ", layout: \"fixed\", width: \(ns.substring(with: match.range(at: 1))), height: \(ns.substring(with: match.range(at: 2)))"
        }
        return result
    }

    /// Platforms whose SwiftUI makes UIKit visible to a file that imports only SwiftUI. On watchOS that is
    /// the small UIKit Apple ships there (UIImage, UIColor, UIFont, ...): watch apps use `UIImage` with only
    /// `import SwiftUI`.
    static let uiKitPlatforms: Set<String> = ["iOS", "tvOS", "visionOS", "watchOS"]

    /// Frameworks the SDK has a module for that Apple does not ship on every platform: `canImport` of one is
    /// false when another platform is rendered.
    static let frameworkPlatforms: [String: Set<String>] = [
        "UIKit": uiKitPlatforms,
        "ActivityKit": ["iOS"],
        "WidgetKit": ["iOS", "macOS", "watchOS", "visionOS"],
        "AppKit": ["macOS"],
        "PhotosUI": ["iOS", "macOS", "tvOS", "visionOS"],
        "WatchConnectivity": ["iOS", "watchOS"],
        "WatchKit": ["watchOS"],
        "EventKitUI": ["iOS", "visionOS"],
        "ContactsUI": ["iOS", "macOS", "visionOS"],
        "PassKit": ["iOS", "macOS", "watchOS", "visionOS"],
        "VisionKit": ["iOS", "macOS", "visionOS"],
        "PDFKit": ["iOS", "macOS", "visionOS"],
        "QuickLook": ["iOS", "macOS", "visionOS"],
        "MessageUI": ["iOS", "visionOS"],
        "SafariServices": ["iOS", "macOS", "visionOS"],
        "CoreMotion": ["iOS", "watchOS", "visionOS"],
        "Translation": ["iOS", "macOS", "visionOS"],
        "CoreSpotlight": ["iOS", "macOS", "visionOS"],
    ]

    /// Modules of the SDK whose Apple counterparts have submodules (`import CoreImage.CIFilterBuiltins`).
    static let submoduleParents: Set<String> = ["os", "CoreImage", "UIKit", "AppKit", "CoreGraphics", "QuartzCore", "ImageIO", "CoreText"]
    /// Attributes that need the Objective-C runtime, which Swift on Linux does not have; they are dropped.
    /// DateFormatter properties declared `[String]!` / `String!` by Apple's Foundation and non-optional by Linux
    /// Foundation. (Its other implicitly unwrapped properties, and NumberFormatter's, are optional on Linux too;
    /// Calendar's and Locale's symbols are non-optional on both.)
    static let implicitlyUnwrappedSymbols = [
        "monthSymbols", "shortMonthSymbols", "veryShortMonthSymbols",
        "standaloneMonthSymbols", "shortStandaloneMonthSymbols", "veryShortStandaloneMonthSymbols",
        "weekdaySymbols", "shortWeekdaySymbols", "veryShortWeekdaySymbols",
        "standaloneWeekdaySymbols", "shortStandaloneWeekdaySymbols", "veryShortStandaloneWeekdaySymbols",
        "quarterSymbols", "shortQuarterSymbols", "standaloneQuarterSymbols", "shortStandaloneQuarterSymbols",
        "eraSymbols", "longEraSymbols", "amSymbol", "pmSymbol",
    ]
    static let objCAttributes = ["@objcMembers", "@objc", "@nonobjc", "@IBAction", "@IBOutlet", "@IBInspectable", "@IBDesignable", "@IBSegueAction"]

    private static func isIdentifierByte(_ b: UInt8) -> Bool {
        b == UInt8(ascii: "_") || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
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
        func hasPrefix(_ token: String, at index: Int) -> Bool {
            let t = Array(token.utf8)
            guard index + t.count <= bytes.count, mask[index] else { return false }
            for (k, b) in t.enumerated() where bytes[index + k] != b { return false }
            return true
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
            // Availability checks are always true to the Linux compiler; make them follow --ios instead.
            var availability: (negated: Bool, length: Int)?
            if hasPrefix("#available", at: i) { availability = (false, "#available".utf8.count) }
            if hasPrefix("#unavailable", at: i) { availability = (true, "#unavailable".utf8.count) }
            if let availability {
                var k = i + availability.length
                while k < bytes.count, bytes[k] == UInt8(ascii: " ") { k += 1 }
                if k < bytes.count, bytes[k] == UInt8(ascii: "("), let close = bytes[k...].firstIndex(of: UInt8(ascii: ")")) {
                    let arguments = String(decoding: bytes[(k + 1)..<close], as: UTF8.self)
                    // Use the iOS entry; a check that does not mention iOS is left for the compiler.
                    let iosEntry = arguments.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .first { $0.hasPrefix(platform + " ") || $0.hasPrefix(platform + "\t") }
                    if let iosEntry {
                        let version = iosEntry.dropFirst(platform.count).trimmingCharacters(in: .whitespaces).split(separator: ".")
                        if let major = version.first.flatMap({ Int($0) }) {
                            let minor = version.count > 1 ? Int(version[1]) ?? 0 : 0
                            let call = "\(availability.negated ? "!" : "")SwiftUI.RenderedPlatform.isAtLeast(iOS: \(major), \(minor))"
                            out += Array(call.utf8)
                            i = close + 1
                            continue
                        }
                    }
                }
            }
            // Apple's SwiftUI re-exports UIKit on iOS, tvOS, visionOS and watchOS. Here UIKit is a module of its
            // own (so macOS code does not see it), and a file importing SwiftUI imports it as well.
            if Self.uiKitPlatforms.contains(platform), hasToken("import SwiftUI", at: i),
               i == 0 || !Self.isIdentifierByte(bytes[i - 1]), !(i + 14 < bytes.count && bytes[i + 14] == UInt8(ascii: ".")) {
                let lineStart = out.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0
                let lead = String(decoding: out[lineStart...], as: UTF8.self).split(separator: " ")
                let accessLevels: Set<Substring> = ["public", "package", "internal", "fileprivate", "private"]
                let modifier = lead.contains("@_exported") ? "@_exported " : lead.first(where: accessLevels.contains).map { "\($0) " } ?? ""
                out += Array("import SwiftUI; \(modifier)import UIKit".utf8)
                i += "import SwiftUI".utf8.count
                continue
            }
            // No Objective-C runtime: drop its attributes (with an `@objc(name)` argument), and make selectors plain values.
            if bytes[i] == UInt8(ascii: "@"), i == 0 || !Self.isIdentifierByte(bytes[i - 1]),
               let attribute = Self.objCAttributes.first(where: { hasToken($0, at: i) }) {
                var j = i + attribute.utf8.count
                if j < bytes.count, bytes[j] == UInt8(ascii: "("), let close = bytes[j...].firstIndex(of: UInt8(ascii: ")")) { j = close + 1 }
                i = j
                continue
            }
            // DateFormatter's symbol properties are implicitly unwrapped (`[String]!`, `String!`) on Apple platforms
            // and plain on Linux, so `f.monthSymbols?[i]` and `f.amSymbol!` lose their `?` / `!` here.
            if bytes[i] == UInt8(ascii: "."), mask[i], let name = Self.implicitlyUnwrappedSymbols.first(where: { hasToken("." + $0, at: i) }) {
                let after = i + 1 + name.utf8.count
                let next = after + 1 < bytes.count ? bytes[after + 1] : 0
                if after < bytes.count, (bytes[after] == UInt8(ascii: "?") && (next == UInt8(ascii: ".") || next == UInt8(ascii: "[")))
                    || (bytes[after] == UInt8(ascii: "!") && next != UInt8(ascii: "=")) {
                    out += bytes[i..<after]
                    i = after + 1
                    continue
                }
            }
            // WidgetKit's watchOS-only family (see WidgetFamily.accessoryCorner).
            if hasPrefix(".accessoryCorner", at: i), i + 16 >= bytes.count || !Self.isIdentifierByte(bytes[i + 16]) {
                out += Array("._accessoryCorner".utf8)
                i += 16
                continue
            }
            // TipKit's `#Rule(...)` macro: the same arguments make a `Tips.Rule` here.
            if hasPrefix("#Rule(", at: i) {
                out += Array("TipKit.Tips.Rule(".utf8)
                i += "#Rule(".utf8.count
                continue
            }
            if hasPrefix("#selector(", at: i) {
                var depth = 0, close = i + "#selector".utf8.count
                while close < bytes.count {
                    if bytes[close] == UInt8(ascii: "(") { depth += 1 }
                    if bytes[close] == UInt8(ascii: ")") { depth -= 1; if depth == 0 { break } }
                    if bytes[close] == UInt8(ascii: "\n") { break }
                    close += 1
                }
                if close < bytes.count, bytes[close] == UInt8(ascii: ")") {
                    let inner = String(decoding: bytes[(i + "#selector(".utf8.count)..<close], as: UTF8.self)
                    out += Array("Selector(\"\(inner.replacingOccurrences(of: "\"", with: ""))\")".utf8)
                    i = close + 1
                    continue
                }
            }
            if hasPrefix("import ", at: i), i == 0 || !Self.isIdentifierByte(bytes[i - 1]) {
                var j = i + "import ".utf8.count
                while j < bytes.count, bytes[j] == UInt8(ascii: " ") { j += 1 }
                var k = j
                while k < bytes.count, Self.isIdentifierByte(bytes[k]) { k += 1 }
                let module = String(decoding: bytes[j..<k], as: UTF8.self)
                if k < bytes.count, bytes[k] == UInt8(ascii: "."), Self.submoduleParents.contains(module) {
                    var end = k + 1
                    while end < bytes.count, Self.isIdentifierByte(bytes[end]) || bytes[end] == UInt8(ascii: ".") { end += 1 }
                    out += Array("import \(module)".utf8)
                    i = end
                    continue
                }
            }
            // `#if os(<the rendered platform>)` must be the true branch; other Apple platforms stay false.
            if hasToken("os(\(platform))", at: i) {
                out += Array("os(\(hostOS))".utf8)
                i += "os(\(platform))".utf8.count
                continue
            }
            // The code is rendered as the Apple platform, so the host's own branches (Linux; macOS on a Mac
            // rendering another platform) are not taken.
            if hasToken("os(\(hostOS))", at: i), i == 0 || !Self.isIdentifierByte(bytes[i - 1]) {
                out += Array("false".utf8)
                i += "os(\(hostOS))".utf8.count
                continue
            }
            // `canImport` follows the rendered platform too: UIKit only where Apple ships it, and so on
            // (Self.frameworkPlatforms). Other modules are left to the compiler, which finds the ones the
            // SDK provides and no others.
            if hasPrefix("canImport(", at: i), i == 0 || !Self.isIdentifierByte(bytes[i - 1]),
               let close = bytes[i...].firstIndex(of: UInt8(ascii: ")")) {
                let argument = String(decoding: bytes[(i + "canImport(".utf8.count)..<close], as: UTF8.self)
                let module = argument.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                if let platforms = Self.frameworkPlatforms[module], !platforms.contains(platform) {
                    out += Array("false".utf8)
                    i = close + 1
                    continue
                }
            }
            if hasToken("#Preview", at: i) {
                var j = i + "#Preview".utf8.count
                var name = "nil"
                var traits = ""
                // Newlines in a multi-line argument list are kept, so later lines keep their numbers.
                var lineBreaks = ""
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
                    // `traits:` become per-preview defaults on the entry.
                    if close > k {
                        let arguments = String(decoding: bytes[(k + 1)..<close], as: UTF8.self)
                        if let range = arguments.range(of: "traits:") { traits = Self.traitArguments(String(arguments[range.upperBound...])) }
                        // Widget and Live Activity previews (`as: <family or kind>`) keep their arguments.
                        let code = String(decoding: bytes[(k + 1)..<close].enumerated().map { mask[k + 1 + $0.offset] ? $0.element : UInt8(ascii: " ") }, as: UTF8.self)
                        if code.range(of: #"(^|,)\s*as\s*:"#, options: .regularExpression) != nil {
                            let identifier = "__preview_\(counter)"
                            counter += 1
                            names.append(identifier)
                            hasWidgetPreviews = true
                            out += Array("@MainActor let \(identifier) = WidgetKit._WidgetPreview(\(arguments))".utf8)
                            i = close + 1
                            continue
                        }
                    }
                    j = close + 1
                    lineBreaks = String(repeating: "\n", count: bytes[k..<min(close, bytes.count)].filter { $0 == UInt8(ascii: "\n") }.count)
                }
                let identifier = "__preview_\(counter)"
                counter += 1
                names.append(identifier)
                out += Array("@MainActor let \(identifier) = SwiftUI._PreviewEntry(\(name)\(traits)\(lineBreaks))".utf8)
                i = j
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        return (String(decoding: out, as: UTF8.self), names)
    }
}
