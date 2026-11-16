import Foundation

// Shift detection for `blitr compare`.
//
// Layout errors usually show up as "everything below here is N points lower". The detector works on
// luma images of the overlapping region:
//
//  1. For every pixel row y and every vertical offset s in -R...R it computes the sum of absolute luma
//     differences between reference row y and candidate row y+s (the "row cost table").
//  2. A Viterbi pass over the rows picks one offset per row, paying a penalty for every change of
//     offset. Runs of rows with the same offset are the vertical segments; ties between offsets (blank
//     rows) never create a change.
//  3. Segments whose non-zero offset does not remove at least half of the error are demoted to zero.
//  4. Segments are cut into bands (about 32pt) and each band searches its horizontal offset at its
//     vertical offset. Adjacent bands with the same offsets are merged into runs.
//  5. The status bar and home indicator zones are searched separately.
//
// Positive dy means the candidate content sits lower than the reference, positive dx further right.

struct ShiftResult {
    var json: [String: Any]
    /// Pixel row ranges and offsets of the reported runs, for drawing on the heatmap.
    var runs: [(y0: Int, y1: Int, dy: Double, dx: Double)]
}

enum ShiftDetector {
    struct Input {
        var lumaReference: [UInt8]
        var lumaCandidate: [UInt8]
        var width: Int
        var height: Int
        var scale: Double
        var statusBarPx: Int
        var homeIndicatorPx: Int
        var maxShift: Int
        /// (differing pixels, counted pixels) in rows a..<b of the overlap.
        var rowStats: (Int, Int) -> (Int, Int)
    }

    @_optimize(speed)
    static func rowCosts(_ r: UnsafePointer<UInt8>, _ c: UnsafePointer<UInt8>, width W: Int, height H: Int, R: Int,
                         into table: UnsafeMutablePointer<Int32>) {
        let S = 2 * R + 1
        for y in 0..<H {
            let rr = r + y * W
            for s in -R...R {
                let yc = y + s
                if yc < 0 || yc >= H { table[y * S + s + R] = -1; continue }
                let cc = c + yc * W
                var total = 0
                for x in 0..<W {
                    let d = Int(rr[x]) - Int(cc[x])
                    total += d < 0 ? -d : d
                }
                table[y * S + s + R] = Int32(truncatingIfNeeded: total)
            }
            let c0 = table[y * S + R]
            for s in 0..<S where table[y * S + s] < 0 { table[y * S + s] = c0 + Int32(W * 8) }
        }
    }

    /// Sum of absolute luma differences over rows y0..<y1 with the candidate shifted by (dy, dx),
    /// as (total, compared pixel count).
    @_optimize(speed)
    static func sad(_ r: UnsafePointer<UInt8>, _ c: UnsafePointer<UInt8>, width W: Int, height H: Int,
                    _ y0: Int, _ y1: Int, dy: Int, dx: Int) -> (Int, Int) {
        let x0 = max(0, -dx), x1 = min(W, W - dx)
        if x1 <= x0 { return (0, 0) }
        var total = 0, n = 0
        for y in y0..<y1 {
            let yc = y + dy
            if yc < 0 || yc >= H { continue }
            let rr = r + y * W, cc = c + yc * W + dx
            var t = 0
            for x in x0..<x1 {
                let d = Int(rr[x]) - Int(cc[x])
                t += d < 0 ? -d : d
            }
            total += t
            n += x1 - x0
        }
        return (total, n)
    }

    static func fmt(_ v: Double) -> String {
        let a = abs(v)
        var s = String(format: a < 1 ? "%.2f" : "%.1f", v)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }

    static func describe(dyPt: Double, dxPt: Double) -> String {
        var parts: [String] = []
        if abs(dyPt) >= 0.005 { parts.append("\(fmt(abs(dyPt)))pt \(dyPt > 0 ? "lower" : "higher")") }
        if abs(dxPt) >= 0.005 { parts.append("\(fmt(abs(dxPt)))pt to the \(dxPt > 0 ? "right" : "left")") }
        return "candidate is " + parts.joined(separator: " and ") + " than reference"
    }

    static func parabola(_ a: Double, _ b: Double, _ c: Double) -> Double {
        let denom = a - 2 * b + c
        if denom <= 0 { return 0 }
        return max(-0.5, min(0.5, 0.5 * (a - c) / denom))
    }

    static func detect(_ input: Input) -> ShiftResult {
        let W = input.width, H = input.height, R = input.maxShift, S = 2 * R + 1
        let scale = input.scale
        func pt(_ px: Int) -> Double { (Double(px) / scale * 100).rounded() / 100 }
        func ptd(_ px: Double) -> Double { (px / scale * 100).rounded() / 100 }
        var json: [String: Any] = ["maxShiftPx": R]
        guard W > 0, H > 0, R > 0 else { return ShiftResult(json: json, runs: []) }

        var table = [Int32](repeating: 0, count: H * S)
        input.lumaReference.withUnsafeBufferPointer { r in
            input.lumaCandidate.withUnsafeBufferPointer { c in
                table.withUnsafeMutableBufferPointer { t in
                    rowCosts(r.baseAddress!, c.baseAddress!, width: W, height: H, R: R, into: t.baseAddress!)
                }
            }
        }
        func sums(_ a: Int, _ b: Int) -> [Int64] {
            var out = [Int64](repeating: 0, count: S)
            for y in a..<b { for s in 0..<S { out[s] += Int64(table[y * S + s]) } }
            return out
        }
        func argmin(_ v: [Int64]) -> Int {
            var best = R
            for s in 0..<S where v[s] < v[best] { best = s }
            return best
        }
        let lambda = Int64(W * 8)

        let zoneTop = min(input.statusBarPx, H / 4), zoneBottom = H - min(input.homeIndicatorPx, H / 4)
        // The segmentation covers the whole image: content scrolls under the status bar and home indicator.
        let top = 0, bottom = H

        // MARK: vertical segmentation (Viterbi)
        struct Segment { var a: Int; var b: Int; var label: Int }
        var segments: [Segment] = []
        if bottom > top {
            let n = bottom - top
            var dp = [Int64](repeating: 0, count: S)
            var back = [UInt8](repeating: 0, count: n * S)
            for s in 0..<S { dp[s] = Int64(table[top * S + s]) + (s == R ? 0 : lambda) }
            for i in 1..<max(n, 1) {
                var bestIdx = R
                for s in 0..<S where dp[s] < dp[bestIdx] { bestIdx = s }
                let bestVal = dp[bestIdx]
                var next = dp
                for s in 0..<S {
                    let stay = dp[s], sw = bestVal + lambda
                    let c = Int64(table[(top + i) * S + s])
                    if stay <= sw { next[s] = stay + c; back[i * S + s] = UInt8(s) }
                    else { next[s] = sw + c; back[i * S + s] = UInt8(bestIdx) }
                }
                dp = next
            }
            var label = R
            for s in 0..<S where dp[s] < dp[label] { label = s }
            var labels = [Int](repeating: R, count: n)
            var i = n - 1
            while i >= 0 {
                labels[i] = label
                label = Int(back[i * S + label])
                i -= 1
            }
            var start = 0
            for i in 1...n where i == n || labels[i] != labels[start] {
                segments.append(Segment(a: top + start, b: top + i, label: labels[start]))
                start = i
            }
        }

        // Demote segments whose shift does not explain most of the error.
        func filtered(_ seg: Segment) -> Segment {
            var seg = seg
            if seg.label != R {
                let s = sums(seg.a, seg.b)
                let cost0 = s[R], cl = s[seg.label]
                if !(cost0 > 0 && Double(cl) <= 0.5 * Double(cost0) && cost0 - cl >= 2 * lambda) { seg.label = R }
            }
            return seg
        }
        segments = segments.map(filtered)
        func mergeSegments() {
            var merging = true
            while merging {
                merging = false
                var i = 0
                while i + 1 < segments.count {
                    let p = segments[i], q = segments[i + 1]
                    if p.label == q.label || (p.label != R && q.label != R && abs(p.label - q.label) <= 1) {
                        var m = Segment(a: p.a, b: q.b, label: p.label)
                        if p.label != q.label { m.label = argmin(sums(m.a, m.b)) }
                        segments.replaceSubrange(i...(i + 1), with: [filtered(m)])
                        merging = true
                    } else { i += 1 }
                }
            }
        }
        mergeSegments()
        // Slivers (a stray row of a divider or an indicator bar) are not layout shifts.
        let minRows = max(6, Int((2 * scale).rounded()))
        for i in segments.indices where segments[i].label != R && segments[i].b - segments[i].a < minRows { segments[i].label = R }
        mergeSegments()
        // A shift starts at the first row that actually moved, not at the start of the blank gap before it.
        for i in 1..<max(segments.count, 1) where segments.count > 1 && segments[i].label != R {
            var y = segments[i].a
            let li = segments[i].label, lp = segments[i - 1].label
            while y < segments[i].b - 1 && abs(Int(table[y * S + li]) - Int(table[y * S + lp])) < W { y += 1 }
            segments[i].a = y
            segments[i - 1].b = y
        }
        segments.removeAll { $0.b <= $0.a }

        // MARK: bands and horizontal offsets
        struct Band { var a: Int; var b: Int; var dy: Int; var dx: Int; var costs: [Double]; var gain: Double }
        let bandRows = max(16, Int((32 * scale).rounded()))
        var bands: [Band] = []
        input.lumaReference.withUnsafeBufferPointer { rp in
            input.lumaCandidate.withUnsafeBufferPointer { cp in
                let r = rp.baseAddress!, c = cp.baseAddress!
                func cost(_ a: Int, _ b: Int, _ dy: Int, _ dx: Int) -> Double {
                    let (t, n) = sad(r, c, width: W, height: H, a, b, dy: dy, dx: dx)
                    return n == 0 ? Double.greatestFiniteMagnitude / 4 : Double(t) * Double(W * (b - a)) / Double(n)
                }
                for seg in segments {
                    let len = seg.b - seg.a
                    let count = max(1, Int((Double(len) / Double(bandRows)).rounded()))
                    for k in 0..<count {
                        let a = seg.a + len * k / count, b = seg.a + len * (k + 1) / count
                        if b <= a { continue }
                        let dy = seg.label - R
                        var costs = [Double](repeating: 0, count: S)
                        let base = cost(a, b, dy, 0)
                        costs[R] = base
                        var dx = 0, gain = 0.0
                        if base > 0 {
                            for s in 0..<S where s != R { costs[s] = cost(a, b, dy, s - R) }
                            var best = R
                            for s in 0..<S where costs[s] < costs[best] { best = s }
                            if best != R, costs[best] <= 0.5 * base, base - costs[best] >= Double(2 * lambda) {
                                dx = best - R
                                gain = base - costs[best]
                            }
                        }
                        bands.append(Band(a: a, b: b, dy: dy, dx: dx, costs: costs, gain: gain))
                    }
                }
            }
        }

        // MARK: runs
        func argminD(_ v: [Double], _ R: Int) -> Int {
            var best = R
            for s in 0..<v.count where v[s] < v[best] { best = s }
            return best
        }
        struct Run { var a: Int; var b: Int; var dy: Int; var dx: Int; var costs: [Double] }
        var runs: [Run] = []
        for band in bands where band.dy != 0 || band.dx != 0 {
            if var last = runs.last, last.b == band.a, last.dy == band.dy,
               last.dx == band.dx || (last.dx != 0 && band.dx != 0 && abs(last.dx - band.dx) <= 1) {
                last.b = band.b
                for s in 0..<S { last.costs[s] += band.costs[s] }
                if last.dx != band.dx && last.dx != 0 { last.dx = argminD(last.costs, R) - R }
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(a: band.a, b: band.b, dy: band.dy, dx: band.dx, costs: band.costs))
            }
        }

        // Runs with the same offsets separated by a short stretch that does not fit (text lines whose
        // glyphs changed, an image) are one run.
        let bridge = Int((12 * scale).rounded())
        var bridged: [Run] = []
        for run in runs {
            if var last = bridged.last, last.dy == run.dy, abs(last.dx - run.dx) <= 1, run.a - last.b <= bridge {
                last.b = run.b
                for s in 0..<S { last.costs[s] += run.costs[s] }
                bridged[bridged.count - 1] = last
            } else { bridged.append(run) }
        }
        runs = bridged

        var runJSON: [[String: Any]] = []
        var drawn: [(y0: Int, y1: Int, dy: Double, dx: Double)] = []
        input.lumaReference.withUnsafeBufferPointer { rp in
            input.lumaCandidate.withUnsafeBufferPointer { cp in
                let r = rp.baseAddress!, c = cp.baseAddress!
                for run in runs {
                    // Sub-pixel refinement of the offsets by a parabola through the neighbouring costs.
                    var dyF = Double(run.dy)
                    if run.dy != 0 {
                        let s = sums(run.a, run.b), l = run.dy + R
                        if l - 1 >= 0 && l + 1 < S { dyF += parabola(Double(s[l - 1]), Double(s[l]), Double(s[l + 1])) }
                    }
                    var dxF = Double(run.dx)
                    if run.dx != 0 {
                        let l = run.dx + R
                        if l - 1 >= 0 && l + 1 < S { dxF += parabola(run.costs[l - 1], run.costs[l], run.costs[l + 1]) }
                    }
                    let (t0, n0) = sad(r, c, width: W, height: H, run.a, run.b, dy: 0, dx: 0)
                    let (t1, n1) = sad(r, c, width: W, height: H, run.a, run.b, dy: run.dy, dx: run.dx)
                    let c0 = n0 == 0 ? 0 : Double(t0) / Double(n0), c1 = n1 == 0 ? 0 : Double(t1) / Double(n1)
                    let explained = c0 > 0 ? max(0, min(1, 1 - c1 / c0)) : 0
                    let dyPt = ptd(dyF), dxPt = ptd(dxF)
                    let y0 = pt(run.a), y1 = pt(run.b)
                    runJSON.append([
                        "y0": y0, "y1": y1, "dy": dyPt, "dx": dxPt, "dyPx": (dyF * 100).rounded() / 100, "dxPx": (dxF * 100).rounded() / 100,
                        "explained": (explained * 1000).rounded() / 1000,
                        "description": "y \(fmt(y0)) to \(fmt(y1))pt: " + describe(dyPt: dyPt, dxPt: dxPt),
                    ])
                    drawn.append((run.a, run.b, dyF, dxF))
                }
            }
        }
        json["runs"] = runJSON

        // Bands, as segmented (cut at every change of shift), with their final offsets.
        var bandJSON: [[String: Any]] = []
        for band in bands {
            let (diff, counted) = input.rowStats(band.a, band.b)
            let share = counted == 0 ? 0 : Double(diff) / Double(counted)
            let status = (band.dy != 0 || band.dx != 0) ? "shift" : (share > 0.002 ? "unexplained" : "match")
            bandJSON.append(["y0": pt(band.a), "y1": pt(band.b), "dyPx": band.dy, "dxPx": band.dx,
                             "diffShare": (share * 10000).rounded() / 10000, "status": status])
        }
        json["bands"] = bandJSON

        // MARK: zones
        var zones: [String: Any] = [:]
        input.lumaReference.withUnsafeBufferPointer { rp in
            input.lumaCandidate.withUnsafeBufferPointer { cp in
                let r = rp.baseAddress!, c = cp.baseAddress!
                func zone(_ name: String, _ a: Int, _ b: Int) {
                    guard b > a else { return }
                    let s = sums(a, b)
                    let best = argmin(s)
                    let (diff, counted) = input.rowStats(a, b)
                    let share = counted == 0 ? 0 : Double(diff) / Double(counted)
                    var dy = 0, dx = 0
                    var explained = 0.0
                    if best != R, s[R] > 0, Double(s[best]) <= 0.5 * Double(s[R]), s[R] - s[best] >= lambda {
                        dy = best - R
                    }
                    let cost0 = s[R]
                    if cost0 > 0 {
                        var bestCost = Double.greatestFiniteMagnitude, bestDx = 0
                        for d in -R...R {
                            let (t, n) = sad(r, c, width: W, height: H, a, b, dy: dy, dx: d)
                            if n == 0 { continue }
                            let v = Double(t) * Double(W * (b - a)) / Double(n)
                            if v < bestCost { bestCost = v; bestDx = d }
                        }
                        let (t0, n0) = sad(r, c, width: W, height: H, a, b, dy: dy, dx: 0)
                        let base = n0 == 0 ? 0 : Double(t0) * Double(W * (b - a)) / Double(n0)
                        if bestDx != 0, bestCost <= 0.5 * base, base - bestCost >= Double(lambda) { dx = bestDx }
                        let final = dx == 0 ? base : bestCost
                        explained = Double(cost0) > 0 ? max(0, min(1, 1 - final / Double(cost0))) : 0
                    }
                    let moved = dy != 0 || dx != 0
                    var entry: [String: Any] = ["y0": pt(a), "y1": pt(b), "dyPx": dy, "dxPx": dx,
                                                "diffShare": (share * 10000).rounded() / 10000,
                                                "status": moved ? "shift" : (share > 0.002 ? "unexplained" : "match")]
                    if moved {
                        entry["explained"] = (explained * 1000).rounded() / 1000
                        entry["description"] = describe(dyPt: ptd(Double(dy)), dxPt: ptd(Double(dx)))
                    }
                    zones[name] = entry
                }
                zone("statusBar", 0, zoneTop)
                zone("homeIndicator", zoneBottom, H)
            }
        }
        if !zones.isEmpty { json["zones"] = zones }
        return ShiftResult(json: json, runs: drawn)
    }
}
