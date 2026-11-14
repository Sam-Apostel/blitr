import Foundation

// Geometry comparison for `swiftui-screenshot compare`: pure JSON in, JSON out. Accepts this tool's
// `--accessibility-tree` output or a simulator dump (see README, "Comparing against references").

struct GeoElement {
    var role: String          // normalised
    var rawRole: String
    var label: String
    var value: String
    var identifier: String
    var x: Double, y: Double, width: Double, height: Double
    var order: Int
}

enum GeometryError: Error, CustomStringConvertible {
    case unreadable(String)
    var description: String { if case .unreadable(let m) = self { return m }; return "" }
}

enum Geometry {
    /// "XCUIElementTypeStaticText", "StaticText", "staticText", "text" all become "statictext".
    static func normalizeRole(_ raw: String) -> String {
        var r = raw.lowercased().replacingOccurrences(of: "xcuielementtype", with: "")
        r = r.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        if r.hasPrefix("ax") { r.removeFirst(2) }
        switch r {
        case "text", "label": return "statictext"
        case "heading": return "header"
        case "toggle", "uiswitch": return "switch"
        case "progressindicator", "progressview", "activityindicator": return "progress"
        case "pickerwheel": return "picker"
        case "": return "other"
        default: return r
        }
    }

    static func string(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// {x,y,width,height}, {origin:{},size:{}}, [x,y,w,h] or "{{x, y}, {w, h}}".
    static func frame(_ v: Any?) -> (Double, Double, Double, Double)? {
        if let d = v as? [String: Any] {
            if let o = d["origin"] as? [String: Any], let s = d["size"] as? [String: Any],
               let x = number(o["x"]), let y = number(o["y"]), let w = number(s["width"]), let h = number(s["height"]) { return (x, y, w, h) }
            if let x = number(d["x"]), let y = number(d["y"]), let w = number(d["width"] ?? d["w"]), let h = number(d["height"] ?? d["h"]) { return (x, y, w, h) }
            return nil
        }
        if let a = v as? [Any], a.count == 4, let x = number(a[0]), let y = number(a[1]), let w = number(a[2]), let h = number(a[3]) { return (x, y, w, h) }
        if let s = v as? String {
            let nums = s.split(whereSeparator: { !"0123456789.-+e".contains($0) }).compactMap { Double($0) }
            if nums.count == 4 { return (nums[0], nums[1], nums[2], nums[3]) }
        }
        return nil
    }

    static func load(_ path: String) throws -> [GeoElement] {
        guard let data = FileManager.default.contents(atPath: path) else { throw GeometryError.unreadable("cannot read \(path)") }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw GeometryError.unreadable("\(path) is not valid JSON") }
        var out: [GeoElement] = []
        func walk(_ node: Any) {
            if let list = node as? [Any] { list.forEach(walk); return }
            guard let d = node as? [String: Any] else { return }
            let f = frame(d["frame"] ?? d["rect"] ?? d["bounds"])
            if let f {
                let raw = string(d["role"] ?? d["type"] ?? d["elementType"] ?? d["class"])
                let role = normalizeRole(raw)
                if role != "application" && role != "window" {
                    out.append(GeoElement(role: role, rawRole: raw,
                                          label: string(d["label"] ?? d["title"] ?? d["name"] ?? d["accessibilityLabel"]),
                                          value: string(d["value"]),
                                          identifier: string(d["identifier"] ?? d["id"] ?? d["accessibilityIdentifier"]),
                                          x: f.0, y: f.1, width: f.2, height: f.3, order: out.count))
                }
            }
            for key in ["children", "elements", "root", "tree", "nodes"] { if let c = d[key] { walk(c) } }
        }
        walk(root)
        return out
    }

    static func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.1f", v)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }
    static func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + fmt(v) }

    static func describe(_ e: GeoElement) -> String { e.label.isEmpty ? e.role : "\(e.role) \"\(e.label)\"" }

    /// Compare two element lists. Deltas are candidate minus reference, in points.
    static func compare(reference: [GeoElement], candidate: [GeoElement], tolerance: Double = 0.5) -> [String: Any] {
        func sortKey(_ a: GeoElement, _ b: GeoElement) -> Bool { a.y != b.y ? a.y < b.y : (a.x != b.x ? a.x < b.x : a.order < b.order) }
        let refs = reference.sorted(by: sortKey), cands = candidate.sorted(by: sortKey)
        var refMatch = [Int?](repeating: nil, count: refs.count), candTaken = [Bool](repeating: false, count: cands.count)

        func pass(_ key: (GeoElement) -> String?, requireEqualCounts: Bool = false) {
            var rg: [String: [Int]] = [:], cg: [String: [Int]] = [:]
            for (i, e) in refs.enumerated() where refMatch[i] == nil { if let k = key(e) { rg[k, default: []].append(i) } }
            for (i, e) in cands.enumerated() where !candTaken[i] { if let k = key(e) { cg[k, default: []].append(i) } }
            for (k, ri) in rg {
                guard let ci = cg[k] else { continue }
                if requireEqualCounts && ri.count != ci.count { continue }
                for n in 0..<min(ri.count, ci.count) { refMatch[ri[n]] = ci[n]; candTaken[ci[n]] = true }
            }
        }
        pass { $0.identifier.isEmpty ? nil : "id|" + $0.identifier }
        pass { $0.label.isEmpty ? nil : "rl|" + $0.role + "|" + $0.label.lowercased() }
        pass { $0.label.isEmpty ? nil : "l|" + $0.label.lowercased() }
        pass({ $0.label.isEmpty ? "r|" + $0.role : nil }, requireEqualCounts: true)

        struct Delta { var ref: GeoElement; var cand: GeoElement; var dx, dy, dw, dh: Double
            var maxAbs: Double { max(abs(dx), abs(dy), abs(dw), abs(dh)) } }
        var deltas: [Delta] = []
        for (i, m) in refMatch.enumerated() {
            guard let m else { continue }
            let a = refs[i], b = cands[m]
            deltas.append(Delta(ref: a, cand: b, dx: r2(b.x - a.x), dy: r2(b.y - a.y), dw: r2(b.width - a.width), dh: r2(b.height - a.height)))
        }
        let moved = deltas.filter { $0.maxAbs >= tolerance }.sorted { $0.maxAbs > $1.maxAbs }

        // Systematic offsets.
        var summary: [String] = []
        func bucket(_ v: Double) -> Double { (v * 2).rounded() / 2 }
        func direction(_ axis: String, _ v: Double) -> String {
            switch axis {
            case "dy": return v > 0 ? "lower" : "higher"
            case "dx": return v > 0 ? "further right" : "further left"
            case "dh": return v > 0 ? "taller" : "shorter"
            default: return v > 0 ? "wider" : "narrower"
            }
        }
        let byPosition = deltas.sorted { $0.ref.y != $1.ref.y ? $0.ref.y < $1.ref.y : $0.ref.x < $1.ref.x }
        for axis in ["dy", "dx"] {
            func value(_ d: Delta) -> Double { axis == "dy" ? d.dy : d.dx }
            var groups: [Double: [Delta]] = [:]
            for d in byPosition where abs(value(d)) >= tolerance { groups[bucket(value(d)), default: []].append(d) }
            for (v, g) in groups.sorted(by: { $0.value.count > $1.value.count }) where g.count >= 3 {
                let start = g.map { $0.ref.y }.min()!, end = g.map { $0.ref.y + $0.ref.height }.max()!
                let below = byPosition.filter { $0.ref.y >= start }
                let allBelow = below.allSatisfy { bucket(value($0)) == v }
                if allBelow && axis == "dy" {
                    summary.append("everything from y=\(fmt(start))pt down (\(below.count) elements) is \(fmt(abs(v)))pt \(direction(axis, v))")
                } else {
                    summary.append("\(g.count) elements between y=\(fmt(start)) and \(fmt(end))pt are \(fmt(abs(v)))pt \(direction(axis, v))")
                }
            }
        }
        for axis in ["dh", "dw"] {
            var groups: [String: [Delta]] = [:]
            for d in deltas {
                let v = axis == "dh" ? d.dh : d.dw
                if abs(v) >= tolerance { groups["\(d.ref.role)|\(bucket(v))", default: []].append(d) }
            }
            for (_, g) in groups.sorted(by: { $0.value.count > $1.value.count }) where g.count >= 2 {
                let v = bucket(axis == "dh" ? g[0].dh : g[0].dw)
                summary.append("\(g.count) \(g[0].ref.role) elements are \(fmt(abs(v)))pt \(direction(axis, v))")
            }
        }
        if let first = byPosition.first(where: { abs($0.dy) >= tolerance }) {
            summary.append("first element to move vertically: \(describe(first.ref)) at y=\(fmt(first.ref.y))pt (\(signed(first.dy))pt)")
        }

        func frameJSON(_ e: GeoElement) -> [String: Any] { ["x": r2(e.x), "y": r2(e.y), "width": r2(e.width), "height": r2(e.height)] }
        func unmatched(_ e: GeoElement) -> [String: Any] {
            var j: [String: Any] = ["role": e.role, "label": e.label, "frame": frameJSON(e)]
            if !e.identifier.isEmpty { j["identifier"] = e.identifier }
            return j
        }
        let unmatchedRef = refs.enumerated().filter { refMatch[$0.offset] == nil }.map { unmatched($0.element) }
        let unmatchedCand = cands.enumerated().filter { !candTaken[$0.offset] }.map { unmatched($0.element) }
        return [
            "matched": deltas.count, "moved": moved.count, "tolerancePt": tolerance,
            "referenceElements": refs.count, "candidateElements": cands.count,
            "unmatchedReference": unmatchedRef, "unmatchedCandidate": unmatchedCand,
            "systematic": summary,
            "deltas": moved.map { d -> [String: Any] in
                var j: [String: Any] = ["role": d.ref.role, "label": d.ref.label, "dx": d.dx, "dy": d.dy, "dw": d.dw, "dh": d.dh,
                                        "reference": frameJSON(d.ref), "candidate": frameJSON(d.cand)]
                if !d.ref.identifier.isEmpty { j["identifier"] = d.ref.identifier }
                if d.ref.role != d.cand.role { j["candidateRole"] = d.cand.role }
                return j
            },
        ]
    }
}
