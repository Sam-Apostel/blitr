import Foundation

// `swiftui-screenshot compare <reference> <candidate>`: orchestration, geometry, baselines, report.
// The pixel work happens in a runner built against the SwiftUI module (Render/ImageComparison.swift).

let compareUsage = """
Usage: swiftui-screenshot compare <reference> <candidate> [options]

  <reference> and <candidate> are two PNG files, or two directories compared by relative file name.

  --out-dir <dir>          Write heatmaps, side-by-side composites and report.json here
  --scale <n>              Pixels per point of the images (default 3)
  --threshold <0..1>       Per-pixel perceptual tolerance (default 0.1, like pixelmatch)
  --mask x,y,w,h           Region in points excluded from the pixel comparison (repeatable)
  --mask-file <json>       Per-image masks: {"Settings.png": [[x,y,w,h], ...], "*": [...]}
  --reference-tree <json>  Reference element frames (a file, or a directory in directory mode)
  --tree <json>            Candidate accessibility tree (a file, or a directory)
                           Default: <name>.json next to each PNG
  --status-bar <pt>        Height of the status bar zone (default 54; 0 disables the zones)
  --home-indicator <pt>    Height of the home indicator zone (default 34)
  --max-shift <px>         Largest shift searched, in pixels (default 12)
  --baseline <scores.json> Compare scores with stored ones; with --update-baseline, store them
  --update-baseline        Write the current scores to the baseline file
  --fail-on-regression     Exit 1 if an image scores worse than its baseline
  --epsilon <n>            Score drop tolerated by --fail-on-regression (default 0.0005)
  --json                   Print the report as JSON on stdout
"""

struct CompareOptions {
    var reference = "", candidate = ""
    var outDir: String?
    var scale = 3.0
    var threshold = 0.1
    var masks: [[Double]] = []
    var maskFile: String?
    var referenceTree: String?
    var tree: String?
    var statusBar = 54.0
    var homeIndicator = 34.0
    var maxShift = 12
    var baseline: String?
    var updateBaseline = false
    var failOnRegression = false
    var epsilon = 0.0005
    var json = false
}

func parseCompare(_ arguments: [String]) -> CompareOptions {
    var o = CompareOptions()
    var args = arguments
    var positional: [String] = []
    func value(_ flag: String) -> String {
        guard !args.isEmpty else { fail("\(flag) needs a value") }
        return args.removeFirst()
    }
    func number(_ flag: String) -> Double {
        let v = value(flag)
        guard let d = Double(v) else { fail("\(flag) needs a number, got \"\(v)\"") }
        return d
    }
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--out-dir": o.outDir = value(arg)
        case "--scale": o.scale = number(arg); if o.scale <= 0 { fail("--scale must be positive") }
        case "--threshold": o.threshold = number(arg); if o.threshold < 0 || o.threshold > 1 { fail("--threshold must be between 0 and 1") }
        case "--mask":
            let v = value(arg)
            let parts = v.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else { fail("--mask takes x,y,w,h in points, got \"\(v)\"") }
            o.masks.append(parts)
        case "--mask-file": o.maskFile = value(arg)
        case "--reference-tree": o.referenceTree = value(arg)
        case "--tree": o.tree = value(arg)
        case "--status-bar": o.statusBar = number(arg)
        case "--home-indicator": o.homeIndicator = number(arg)
        case "--max-shift": o.maxShift = max(1, Int(number(arg)))
        case "--baseline": o.baseline = value(arg)
        case "--update-baseline": o.updateBaseline = true
        case "--fail-on-regression": o.failOnRegression = true
        case "--epsilon": o.epsilon = number(arg)
        case "--json": o.json = true
        case "-h", "--help":
            print(compareUsage)
            exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n\(compareUsage)", code: 2) }
            positional.append(arg)
        }
    }
    guard positional.count == 2 else { fail("compare needs <reference> and <candidate>\n\n\(compareUsage)", code: 2) }
    o.reference = positional[0]
    o.candidate = positional[1]
    return o
}

private func isDirectory(_ path: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
}

private func pngFiles(in dir: String) -> [String] {
    guard let walker = FileManager.default.enumerator(atPath: dir) else { return [] }
    var out: [String] = []
    for case let rel as String in walker where rel.lowercased().hasSuffix(".png") {
        // Our own outputs (heatmaps, composites) can live next to the images being compared.
        if rel.hasSuffix(".heatmap.png") || rel.hasSuffix(".compare.png") { continue }
        out.append(rel)
    }
    return out.sorted()
}

private func fmt(_ v: Double, _ digits: Int = 1) -> String {
    var s = String(format: "%.\(digits)f", v)
    if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
    return s
}

private func sizeText(_ v: Any?) -> String {
    guard let d = v as? [String: Any] else { return "?" }
    return "\(d["width"] ?? "?")x\(d["height"] ?? "?")"
}

private func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }

/// Masks from `--mask-file`: {"name.png": [[x,y,w,h] | {x,y,width,height}], "*": [...]}; keys match the
/// relative name, the file name or the name without extension.
private func masks(for name: String, file: [String: Any]?) -> [[Double]] {
    guard let file else { return [] }
    var out: [[Double]] = []
    for key in ["*", name, (name as NSString).lastPathComponent, stem(name), stem((name as NSString).lastPathComponent)] {
        guard let list = file[key] as? [Any] else { continue }
        for item in list {
            if let a = item as? [Double], a.count == 4 { out.append(a) }
            else if let a = item as? [NSNumber], a.count == 4 { out.append(a.map { $0.doubleValue }) }
            else if let d = item as? [String: Any], let f = Geometry.frame(d) { out.append([f.0, f.1, f.2, f.3]) }
        }
    }
    return out
}

func compareCommand(_ arguments: [String], _ installation: Installation) -> Never {
    let o = parseCompare(arguments)
    let fm = FileManager.default
    guard fm.fileExists(atPath: o.reference) else { fail("no such file or directory: \(o.reference)") }
    guard fm.fileExists(atPath: o.candidate) else { fail("no such file or directory: \(o.candidate)") }
    let directories = isDirectory(o.reference)
    guard directories == isDirectory(o.candidate) else { fail("reference and candidate must both be files or both be directories") }

    // Pairs by relative name.
    var pairs: [(name: String, reference: String, candidate: String)] = []
    var onlyReference: [String] = [], onlyCandidate: [String] = []
    if directories {
        let r = pngFiles(in: o.reference), c = pngFiles(in: o.candidate)
        let cs = Set(c), rs = Set(r)
        for name in r { if cs.contains(name) { pairs.append((name, o.reference + "/" + name, o.candidate + "/" + name)) } else { onlyReference.append(name) } }
        onlyCandidate = c.filter { !rs.contains($0) }
        if pairs.isEmpty && onlyReference.isEmpty && onlyCandidate.isEmpty { fail("no PNG files found in \(o.reference) or \(o.candidate)") }
    } else {
        pairs = [((o.candidate as NSString).lastPathComponent, o.reference, o.candidate)]
    }

    var maskFile: [String: Any]?
    if let path = o.maskFile {
        guard let data = fm.contents(atPath: path), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("cannot read mask file \(path)")
        }
        maskFile = json
    }
    if let dir = o.outDir { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }

    // Pixel comparison in the runner.
    var jobs: [[String: Any]] = []
    for pair in pairs {
        var job: [String: Any] = ["id": pair.name, "reference": pair.reference, "candidate": pair.candidate,
                                  "scale": o.scale, "threshold": o.threshold, "statusBar": o.statusBar,
                                  "homeIndicator": o.homeIndicator, "maxShift": o.maxShift,
                                  "masks": o.masks + masks(for: pair.name, file: maskFile)]
        if let dir = o.outDir {
            job["heatmap"] = dir + "/" + stem(pair.name) + ".heatmap.png"
            job["composite"] = dir + "/" + stem(pair.name) + ".compare.png"
        }
        jobs.append(job)
    }
    var results: [String: [String: Any]] = [:]
    if !jobs.isEmpty {
        let runner = utilityRunner(installation)
        let jobsPath = NSTemporaryDirectory() + "/swiftui-screenshot-compare-\(getpid()).json"
        guard let data = try? JSONSerialization.data(withJSONObject: ["jobs": jobs]), fm.createFile(atPath: jobsPath, contents: data) else {
            fail("cannot write the comparison job file")
        }
        defer { try? fm.removeItem(atPath: jobsPath) }
        let result = run(runner, ["--compare", jobsPath])
        guard result.status == 0, let out = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let list = out["results"] as? [[String: Any]] else {
            fail("the comparison runner failed (exit \(result.status)):\n\(result.stderr)")
        }
        for item in list { if let id = item["id"] as? String { results[id] = item } }
    }

    // Geometry.
    func treePath(_ explicit: String?, _ png: String, _ name: String) -> String? {
        if let explicit {
            if isDirectory(explicit) {
                let p = explicit + "/" + stem(name) + ".json"
                return fm.fileExists(atPath: p) ? p : nil
            }
            return explicit
        }
        let p = stem(png) + ".json"
        return fm.fileExists(atPath: p) ? p : nil
    }
    var warnings: [String] = []
    var images: [[String: Any]] = []
    for pair in pairs {
        var entry = results[pair.name] ?? ["id": pair.name, "error": "no result"]
        entry["name"] = pair.name
        entry["referenceFile"] = pair.reference
        entry["candidateFile"] = pair.candidate
        entry["id"] = nil
        if let rt = treePath(o.referenceTree, pair.reference, pair.name), let ct = treePath(o.tree, pair.candidate, pair.name) {
            do {
                let a = try Geometry.load(rt), b = try Geometry.load(ct)
                var g = Geometry.compare(reference: a, candidate: b)
                g["referenceTree"] = rt
                g["candidateTree"] = ct
                entry["geometry"] = g
            } catch { warnings.append("\(pair.name): geometry skipped: \(error)") }
        }
        images.append(entry)
    }
    func score(_ e: [String: Any]) -> Double { ((e["metrics"] as? [String: Any])?["score"] as? Double) ?? -1 }
    images.sort { score($0) != score($1) ? score($0) < score($1) : ($0["name"] as! String) < ($1["name"] as! String) }

    // Baseline.
    var regressions: [String] = []
    var baselineScores: [String: Double] = [:]
    if let path = o.baseline {
        if let data = fm.contents(atPath: path), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            baselineScores = (json["scores"] as? [String: Double]) ?? [:]
        } else if !o.updateBaseline {
            fail("cannot read baseline \(path) (use --update-baseline to create it)")
        }
        if !o.updateBaseline {
            for i in images.indices {
                let name = images[i]["name"] as! String
                guard let base = baselineScores[name] else { images[i]["baseline"] = ["status": "new"]; continue }
                let now = score(images[i])
                let regressed = now < base - o.epsilon
                images[i]["baseline"] = ["score": base, "delta": ((now - base) * 1_000_000).rounded() / 1_000_000,
                                         "status": regressed ? "regression" : (now > base + o.epsilon ? "improved" : "same")]
                if regressed { regressions.append(name) }
            }
        } else {
            for e in images where score(e) >= 0 { baselineScores[e["name"] as! String] = score(e) }
            let json: [String: Any] = ["version": 1, "scores": baselineScores]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                fm.createFile(atPath: path, contents: data)
                note("baseline updated: \(path) (\(baselineScores.count) images)")
            }
        }
    } else if o.updateBaseline || o.failOnRegression {
        fail("--update-baseline and --fail-on-regression need --baseline <scores.json>")
    }

    let identical = images.filter { score($0) == 1 }.count
    let summary: [String: Any] = ["images": images.count, "identical": identical, "differing": images.count - identical,
                                  "onlyInReference": onlyReference, "onlyInCandidate": onlyCandidate,
                                  "worstScore": images.first.map(score) ?? 1]
    var report: [String: Any] = ["version": 1, "reference": o.reference, "candidate": o.candidate, "scale": o.scale,
                                 "threshold": o.threshold, "summary": summary, "images": images, "regressions": regressions]
    if !warnings.isEmpty { report["warnings"] = warnings }
    let reportData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    if let dir = o.outDir, let reportData { fm.createFile(atPath: dir + "/report.json", contents: reportData) }

    if o.json {
        if let reportData { print(String(decoding: reportData, as: UTF8.self)) }
    } else {
        printCompareSummary(images, onlyReference, onlyCandidate, warnings, regressions, o)
    }
    exit(o.failOnRegression && !regressions.isEmpty ? 1 : 0)
}

// MARK: - Text summary

private func shiftHeadline(_ e: [String: Any]) -> String {
    guard let shift = e["shift"] as? [String: Any] else { return "" }
    var parts: [String] = []
    for run in (shift["runs"] as? [[String: Any]]) ?? [] {
        let dy = (run["dy"] as? Double) ?? 0, dx = (run["dx"] as? Double) ?? 0
        var s = ""
        if abs(dy) >= 0.005 { s += "y\(dy > 0 ? "+" : "")\(fmt(dy, 2))pt" }
        if abs(dx) >= 0.005 { s += (s.isEmpty ? "" : " ") + "x\(dx > 0 ? "+" : "")\(fmt(dx, 2))pt" }
        parts.append(s + "@" + fmt((run["y0"] as? Double) ?? 0, 0))
    }
    return parts.isEmpty ? "" : "shift " + parts.prefix(3).joined(separator: ", ") + (parts.count > 3 ? ", ..." : "")
}

private func printCompareSummary(_ images: [[String: Any]], _ onlyRef: [String], _ onlyCand: [String], _ warnings: [String],
                                 _ regressions: [String], _ o: CompareOptions) {
    var out: [String] = []
    let differing = images.filter { (($0["metrics"] as? [String: Any])?["score"] as? Double) != 1 }.count
    out.append("compared \(images.count) image\(images.count == 1 ? "" : "s"): \(images.count - differing) identical, \(differing) differ"
               + " (scale \(fmt(o.scale)), threshold \(fmt(o.threshold, 3)))")
    for e in images {
        let name = e["name"] as! String
        if let err = e["error"] as? String { out.append("  error    \(name): \(err)"); continue }
        let m = e["metrics"] as! [String: Any]
        let score = m["score"] as! Double
        var line = String(format: "  %.4f  %@", score, name)
        if score == 1 { line += "  identical" }
        else {
            line += "  \(fmt((m["diffShare"] as! Double) * 100, 2))% px differ"
            if e["sizeMismatch"] as? Bool == true { line += "  SIZE MISMATCH \(sizeText(e["reference"])) vs \(sizeText(e["candidate"]))" }
            let sh = shiftHeadline(e)
            if !sh.isEmpty { line += "  " + sh }
        }
        if let g = e["geometry"] as? [String: Any], let moved = g["moved"] as? Int, moved > 0 { line += "  geometry: \(moved) moved" }
        if let b = e["baseline"] as? [String: Any], let s = b["status"] as? String, s != "same" { line += "  [baseline: \(s)]" }
        out.append(line)
    }
    for n in onlyRef { out.append("  only in reference: \(n)") }
    for n in onlyCand { out.append("  only in candidate: \(n)") }
    for w in warnings { out.append("  warning: \(w)") }
    if !regressions.isEmpty { out.append("REGRESSIONS vs baseline: " + regressions.joined(separator: ", ")) }

    for e in images.prefix(3) where (((e["metrics"] as? [String: Any])?["score"] as? Double) ?? 1) != 1 {
        out.append("")
        out.append("== \(e["name"] as! String)")
        out.append(contentsOf: detail(e, o))
    }
    print(out.joined(separator: "\n"))
}

private func detail(_ e: [String: Any], _ o: CompareOptions) -> [String] {
    var out: [String] = []
    if e["sizeMismatch"] as? Bool == true {
        out.append("SIZE MISMATCH: reference \(sizeText(e["reference"])) px, candidate \(sizeText(e["candidate"])) px; \(e["note"] as? String ?? "")")
    }
    let m = e["metrics"] as! [String: Any]
    out.append("pixels: \(m["diffPixels"] ?? 0) differ (\(fmt((m["diffShare"] as! Double) * 100, 2))%), mean distance \(fmt((m["meanDistance"] as! Double), 4)), max \(fmt((m["maxDistance"] as! Double), 3)), \(m["antialiasedIgnored"] ?? 0) anti-aliased ignored, \(m["maskedPixels"] ?? 0) masked")
    if let shift = e["shift"] as? [String: Any] {
        let runs = (shift["runs"] as? [[String: Any]]) ?? []
        if runs.isEmpty { out.append("shift: none detected (differences are not explained by a vertical or horizontal offset)") }
        else {
            out.append("shift runs:")
            for r in runs { out.append("  \(r["description"] as? String ?? "") (explains \(fmt(((r["explained"] as? Double) ?? 0) * 100, 0))%)") }
        }
        for (key, title) in [("statusBar", "status bar"), ("homeIndicator", "home indicator")] {
            if let z = (shift["zones"] as? [String: Any])?[key] as? [String: Any], let st = z["status"] as? String, st != "match" {
                let extra = (z["description"] as? String).map { ": " + $0 } ?? ""
                out.append("\(title) zone (y \(fmt(z["y0"] as? Double ?? 0))-\(fmt(z["y1"] as? Double ?? 0))pt): \(st), \(fmt(((z["diffShare"] as? Double) ?? 0) * 100, 2))% differ\(extra)")
            }
        }
    }
    let clusters = (e["clusters"] as? [[String: Any]]) ?? []
    if !clusters.isEmpty {
        out.append("clusters (largest of \(clusters.count) shown, points):")
        for (i, c) in clusters.prefix(6).enumerated() {
            out.append("  #\(i + 1) x=\(fmt(c["x"] as! Double)) y=\(fmt(c["y"] as! Double)) \(fmt(c["width"] as! Double))x\(fmt(c["height"] as! Double))  \(c["pixels"] ?? 0) px  \(c["referenceColor"] ?? "") -> \(c["candidateColor"] ?? "")")
        }
    }
    if let g = e["geometry"] as? [String: Any] {
        let un = ((g["unmatchedReference"] as? [Any])?.count ?? 0, (g["unmatchedCandidate"] as? [Any])?.count ?? 0)
        out.append("geometry: \(g["matched"] ?? 0) matched, \(g["moved"] ?? 0) moved, unmatched \(un.0) reference / \(un.1) candidate")
        for s in (g["systematic"] as? [String]) ?? [] { out.append("  * " + s) }
        for d in ((g["deltas"] as? [[String: Any]]) ?? []).prefix(6) {
            var parts: [String] = []
            for (k, label) in [("dx", "x"), ("dy", "y"), ("dw", "w"), ("dh", "h")] {
                let v = (d[k] as? Double) ?? 0
                if abs(v) >= 0.5 { parts.append("\(label)\(v > 0 ? "+" : "")\(fmt(v))") }
            }
            let l = (d["label"] as? String) ?? ""
            out.append("  - \(d["role"] ?? "") \(l.isEmpty ? "" : "\"\(l)\" ")\(parts.joined(separator: " "))pt")
        }
        for (key, title) in [("unmatchedReference", "only in reference"), ("unmatchedCandidate", "only in candidate")] {
            let list = (g[key] as? [[String: Any]]) ?? []
            if !list.isEmpty { out.append("  \(title): " + list.prefix(5).map { "\($0["role"] ?? "") \"\($0["label"] ?? "")\"" }.joined(separator: ", ") + (list.count > 5 ? ", ..." : "")) }
        }
    }
    if let img = e["images"] as? [String: Any] {
        if let c = img["composite"] as? String { out.append("composite (reference | candidate | heatmap): \(c)") }
        if let h = img["heatmap"] as? String { out.append("heatmap: \(h)") }
    } else if o.outDir == nil { out.append("(pass --out-dir to write the heatmap and composite images)") }
    return out
}
