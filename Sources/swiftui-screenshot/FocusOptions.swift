import Foundation

// The focus flags of `render`: `--focus-map <file.json>`, `--focus-overlay <file.png>`,
// `--press <list>` and `--focus <selector>`. The runner does the work (see Sources/SwiftUI/Focus and
// docs/FOCUS.md); this file parses the flags and derives one file name per image like the PNG names.

struct FocusCLIOptions {
    var mapPath: String?
    var overlayPath: String?
    var presses: [String] = []
    var selector: String?

    var isActive: Bool { mapPath != nil || overlayPath != nil || !presses.isEmpty || selector != nil }

    mutating func record(_ flag: String, value: String) {
        switch flag {
        case "--focus-map": mapPath = value
        case "--focus-overlay": overlayPath = value
        case "--press": presses.append(value)
        default: selector = value
        }
    }

    /// `base` with the image's name suffix inserted before the extension (see AccessibilityCLIOptions).
    private func derive(_ base: String, png: String, stem: String, multiple: Bool, outDir: String?) -> String {
        guard multiple else { return base }
        let pngStem = ((png as NSString).lastPathComponent as NSString).deletingPathExtension
        let suffix = pngStem.hasPrefix(stem) ? String(pngStem.dropFirst(stem.count)) : "-" + pngStem
        let ns = base as NSString
        let name = (ns.lastPathComponent as NSString).deletingPathExtension + suffix + (ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension)
        let dir = ns.deletingLastPathComponent
        return (dir.isEmpty ? (outDir ?? ".") : dir) + "/" + name
    }

    func arguments(png: String, stem: String, multiple: Bool, outDir: String?) -> [String] {
        var args: [String] = []
        if let mapPath { args += ["--focus-map", derive(mapPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let overlayPath { args += ["--focus-overlay", derive(overlayPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let selector { args += ["--focus", selector] }
        if !presses.isEmpty { args += ["--press", presses.joined(separator: ",")] }
        return args
    }

    /// Text-mode report after one image: the files written (the summary itself comes on stderr).
    func report(_ runnerLine: String, json: Bool) {
        guard isActive, !json, let data = runnerLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let path = object["focusMap"] as? String { print("  focus map: \(path)") }
        if let path = object["focusOverlay"] as? String { print("  focus overlay: \(path)") }
    }
}
