import Foundation

// Rewrites SwiftUI sources for the reference-capture host app (see capture-references.sh).
//
//   prepare-host <repo-root> <out-dir> <file.swift>...
//
// Each source file becomes its own module (corpus files reuse type names, so they cannot share one),
// rewritten by the same Preprocessor the Linux tool uses, with its Linux-only rewrites undone
// (see `forRealSwiftUI`). Writes:
//   <out-dir>/modules/<Module>.swift  one rewritten file per module, ending in a public entry list
//   <out-dir>/Registry.swift          imports every module and maps screen keys to their entries
//   <out-dir>/screens.json            [{ key, source, module, previews: [{ index, name, layout }] }]

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: prepare-host <repo-root> <out-dir> <file.swift>...\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: args[1]).standardizedFileURL.path
let out = args[2]
let fm = FileManager.default
try? fm.removeItem(atPath: out + "/modules")
try fm.createDirectory(atPath: out + "/modules", withIntermediateDirectories: true)

/// `Tests/Corpus/01_Settings.swift` -> `01_Settings`; `Examples/NavigationTabs/Tabs.swift` -> `NavigationTabs-Tabs`.
func screenKey(_ relative: String) -> String {
    var parts = relative.split(separator: "/").map(String.init)
    let stem = (parts.removeLast() as NSString).deletingPathExtension
    let dirs = parts.filter { !["Tests", "Corpus", "Examples"].contains($0) }
    return (dirs + [stem]).joined(separator: "-")
}

var preprocessor = Preprocessor()
// Overrides in extensions compile on iOS as they are.
preprocessor.rewritesExtensionOverrides = false

/// The Preprocessor targets the Linux module: entries are `SwiftUI._PreviewEntry`, availability checks call
/// `SwiftUI.RenderedPlatform`, and `os(iOS)` becomes `os(Linux)`. Undo those for real SwiftUI. Its other
/// rewrites (`#Preview`, `@Previewable`, `@main`, `@Entry` as an explicit key) compile on iOS as they are.
func forRealSwiftUI(_ source: String) -> String {
    var s = source.replacingOccurrences(of: "SwiftUI._PreviewEntry(", with: "_PreviewEntry(")
    s = s.replacingOccurrences(of: "os(Linux)", with: "os(iOS)")
    s = s.replacingOccurrences(of: #"!SwiftUI\.RenderedPlatform\.isAtLeast\(iOS: (\d+), (\d+)\)"#,
                               with: "#unavailable(iOS $1.$2)", options: .regularExpression)
    s = s.replacingOccurrences(of: #"SwiftUI\.RenderedPlatform\.isAtLeast\(iOS: (\d+), (\d+)\)"#,
                               with: "#available(iOS $1.$2, *)", options: .regularExpression)
    return s
}
var registry = "import SwiftUI\nimport PreviewSupport\n"
var table = "\n@MainActor let previewRegistry: [String: [_PreviewEntry]] = [\n"
var screens: [[String: Any]] = []

for path in args[3...] {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    let relative = absolute.hasPrefix(root + "/") ? String(absolute.dropFirst(root.count + 1)) : (absolute as NSString).lastPathComponent
    let key = screenKey(relative)
    let module = "Screen_" + key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    let source = try String(contentsOfFile: absolute, encoding: .utf8)
    let output = preprocessor.process([(path: absolute, contents: source)], viewExpression: nil)
    guard let file = output.files.first(where: { $0.name != "main.swift" }) else { continue }

    // An app with no previews cannot be shown here: real SwiftUI gives no way to pull a WindowGroup's
    // content out of an App value. Such files are listed with no previews.
    let entries = output.entries.filter { !$0.contains("(app:") }.map(forRealSwiftUI)
    var contents = forRealSwiftUI(file.contents)
    contents += "\n\nimport PreviewSupport\nimport Combine\n\n@MainActor public let __previewEntries: [_PreviewEntry] = [\(entries.joined(separator: ", "))]\n"
    try contents.write(toFile: "\(out)/modules/\(module).swift", atomically: true, encoding: .utf8)

    registry += "import \(module)\n"
    table += "    \"\(key)\": \(module).__previewEntries,\n"

    // Preview names and layouts, for the capture script (it skips non-device layouts).
    var previews: [[String: Any]] = []
    for (index, entry) in entries.enumerated() {
        var item: [String: Any] = ["index": index]
        if let m = entry.range(of: #"_PreviewEntry\("((?:[^"\\]|\\.)*)""#, options: .regularExpression) {
            let literal = entry[m].dropFirst("_PreviewEntry(\"".count).dropLast()
            item["name"] = String(literal)
        }
        if entry.contains("layout: \"fit\"") { item["layout"] = "fit" }
        else if entry.contains("layout: \"fixed\"") { item["layout"] = "fixed" }
        if entry.contains("orientation: \"landscape") { item["orientation"] = "landscape" }
        previews.append(item)
    }
    // Inline `#Preview` entries are identifiers; read their names from the rewritten source.
    for (index, entry) in entries.enumerated() where entry.hasPrefix("__preview_") {
        let pattern = "let \(entry) = _PreviewEntry\\(([^\\n]*)"
        if let m = contents.range(of: pattern, options: .regularExpression) {
            let line = String(contents[m])
            if let open = line.range(of: "_PreviewEntry(\"") {
                let rest = line[open.upperBound...]
                if let close = rest.firstIndex(of: "\"") { previews[index]["name"] = String(rest[..<close]) }
            }
            if line.contains("layout: \"fit\"") { previews[index]["layout"] = "fit" }
            if line.contains("layout: \"fixed\"") { previews[index]["layout"] = "fixed" }
            if line.contains("orientation: \"landscape") { previews[index]["orientation"] = "landscape" }
        }
    }
    screens.append(["key": key, "source": relative, "module": module, "previews": previews])
}

table += "]\n"
try (registry + table).write(toFile: out + "/Registry.swift", atomically: true, encoding: .utf8)
let json = try JSONSerialization.data(withJSONObject: screens, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: out + "/screens.json"))
