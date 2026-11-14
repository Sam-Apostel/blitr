import Foundation

// The accessibility flags of `render`: `--accessibility-tree <file.json>`, `--tap-targets <file.png>` and
// `--accessibility-outline`. The runner does the work (see Sources/SwiftUI/Accessibility); this file
// parses the flags and derives one file name per image the same way the PNG names are derived.

struct AccessibilityCLIOptions {
    var treePath: String?
    var tapTargetsPath: String?
    var outline = false

    var isActive: Bool { treePath != nil || tapTargetsPath != nil || outline }

    mutating func record(_ flag: String, value: String?) {
        switch flag {
        case "--accessibility-tree": treePath = value
        case "--tap-targets": tapTargetsPath = value
        default: outline = true
        }
    }

    /// `base` with the image's name suffix (the part of the PNG name after the source stem, e.g.
    /// `-Dark-dark`) inserted before the extension. A lone image uses `base` unchanged.
    private func derive(_ base: String, png: String, stem: String, multiple: Bool, outDir: String?) -> String {
        guard multiple else { return base }
        let pngName = (png as NSString).lastPathComponent
        let pngStem = (pngName as NSString).deletingPathExtension
        let suffix = pngStem.hasPrefix(stem) ? String(pngStem.dropFirst(stem.count)) : "-" + pngStem
        let ns = base as NSString
        let name = (ns.lastPathComponent as NSString).deletingPathExtension + suffix + (ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension)
        let dir = ns.deletingLastPathComponent
        return (dir.isEmpty ? (outDir ?? ".") : dir) + "/" + name
    }

    /// Runner arguments for one image (`png` is the path the screenshot is written to).
    func arguments(png: String, stem: String, multiple: Bool, outDir: String?) -> [String] {
        var args: [String] = []
        if let treePath { args += ["--accessibility-tree", derive(treePath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if let tapTargetsPath { args += ["--tap-targets", derive(tapTargetsPath, png: png, stem: stem, multiple: multiple, outDir: outDir)] }
        if outline { args.append("--accessibility-outline") }
        return args
    }

    /// Text-mode report after one image: the files written, then the outline on stdout.
    func report(_ runnerLine: String, json: Bool) {
        guard isActive, !json, let data = runnerLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let path = object["accessibilityTree"] as? String { print("  accessibility tree: \(path)") }
        if let path = object["tapTargets"] as? String { print("  tap targets: \(path)") }
        if let summary = object["accessibility"] as? [String: Any], let issues = summary["issues"] as? Int, issues > 0 {
            note("  \(issues) accessibility issue\(issues == 1 ? "" : "s") (see the issues array in the tree JSON)")
        }
        if let text = object["outline"] as? String { print(text) }
    }
}
