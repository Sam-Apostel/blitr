internal import CSkia
import Foundation

// Pixel comparison for `blitr compare`. The command-line tool does not link Skia, so it
// hands a job list to a runner (`--compare <jobs.json>`) that decodes the PNGs, compares them, writes the
// heatmap and composite images and prints one JSON result per job.
//
// Pixels are decoded to sRGB, flattened over white, and packed as 0xAABBGGRR (bytes R,G,B,A in memory).

enum ImageComparison {
    struct Image {
        var width: Int
        var height: Int
        var pixels: [UInt32]
    }

    // MARK: PNG in and out

    static func decode(_ path: String) -> Image? {
        guard let data = sk_data_new_from_file(path) else { return nil }
        defer { sk_data_unref(data) }
        guard let image = sk_image_new_from_encoded(data) else { return nil }
        defer { sk_image_unref(image) }
        let w = Int(sk_image_get_width(image)), h = Int(sk_image_get_height(image))
        guard w > 0, h > 0 else { return nil }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(w), height: Int32(h),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: UNPREMUL_SK_ALPHATYPE)
        var pixels = [UInt32](repeating: 0, count: w * h)
        let ok = pixels.withUnsafeMutableBytes {
            sk_image_read_pixels(image, &info, $0.baseAddress, w * 4, 0, 0, ALLOW_SK_IMAGE_CACHING_HINT)
        }
        guard ok else { return nil }
        for i in 0..<pixels.count {
            let p = pixels[i]
            let a = Int(p >> 24)
            if a == 255 { continue }
            func blend(_ c: Int) -> UInt32 { UInt32((c * a + 255 * (255 - a) + 127) / 255) }
            pixels[i] = 0xFF00_0000 | blend(Int((p >> 16) & 0xFF)) << 16 | blend(Int((p >> 8) & 0xFF)) << 8 | blend(Int(p & 0xFF))
        }
        return Image(width: w, height: h, pixels: pixels)
    }

    static func writePNG(_ pixels: [UInt32], width: Int, height: Int, to path: String) -> Bool {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent.isEmpty ? "." : (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(width), height: Int32(height),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: OPAQUE_SK_ALPHATYPE)
        return pixels.withUnsafeBytes { buf -> Bool in
            guard let pixmap = sk_pixmap_new_with_params(&info, buf.baseAddress, width * 4) else { return false }
            defer { sk_pixmap_destructor(pixmap) }
            guard let stream = sk_filewstream_new(path), sk_filewstream_is_valid(stream) else { return false }
            var options = sk_pngencoder_options_t(fFilterFlags: ALL_SK_PNGENCODER_FILTER_FLAGS, fZLibLevel: 6, fComments: nil, fGainmap: nil, fGainmapInfo: nil)
            let ok = sk_pngencoder_encode(stream, pixmap, &options)
            sk_filewstream_destroy(stream)
            return ok
        }
    }

    // MARK: colour distance (pixelmatch's YIQ metric)

    @inline(__always) static func yiq(_ p: UInt32) -> (Double, Double, Double) {
        let r = Double(p & 0xFF), g = Double((p >> 8) & 0xFF), b = Double((p >> 16) & 0xFF)
        return (r * 0.29889531 + g * 0.58662247 + b * 0.11448223,
                r * 0.59597799 - g * 0.27417610 - b * 0.32180189,
                r * 0.21147017 - g * 0.52261711 + b * 0.31114694)
    }
    static let maxDelta = 35215.0

    @inline(__always) static func delta(_ a: UInt32, _ b: UInt32) -> Double {
        let (y1, i1, q1) = yiq(a), (y2, i2, q2) = yiq(b)
        let dy = y1 - y2, di = i1 - i2, dq = q1 - q2
        return 0.5053 * dy * dy + 0.299 * di * di + 0.1957 * dq * dq
    }

    static func lumaDelta(_ a: UInt32, _ b: UInt32) -> Double { yiq(a).0 - yiq(b).0 }

    static func hasManySiblings(_ img: UnsafePointer<UInt32>, _ x1: Int, _ y1: Int, _ w: Int, _ h: Int) -> Bool {
        let x0 = max(x1 - 1, 0), y0 = max(y1 - 1, 0), x2 = min(x1 + 1, w - 1), y2 = min(y1 + 1, h - 1)
        var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0
        let p = img[y1 * w + x1]
        for x in x0...x2 {
            for y in y0...y2 where !(x == x1 && y == y1) {
                if img[y * w + x] == p { zeroes += 1 }
                if zeroes > 2 { return true }
            }
        }
        return false
    }

    /// pixelmatch's anti-aliasing test: is pixel (x1, y1) of `img` an edge pixel that only differs
    /// from `other` because of sub-pixel placement?
    static func antialiased(_ img: UnsafePointer<UInt32>, _ x1: Int, _ y1: Int, _ w: Int, _ h: Int, _ other: UnsafePointer<UInt32>) -> Bool {
        let x0 = max(x1 - 1, 0), y0 = max(y1 - 1, 0), x2 = min(x1 + 1, w - 1), y2 = min(y1 + 1, h - 1)
        var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0
        var mn = 0.0, mx = 0.0
        var minX = 0, minY = 0, maxX = 0, maxY = 0
        let p = img[y1 * w + x1]
        for x in x0...x2 {
            for y in y0...y2 where !(x == x1 && y == y1) {
                let d = lumaDelta(p, img[y * w + x])
                if d == 0 {
                    zeroes += 1
                    if zeroes > 2 { return false }
                } else if d < mn { mn = d; minX = x; minY = y }
                else if d > mx { mx = d; maxX = x; maxY = y }
            }
        }
        if mn == 0 || mx == 0 { return false }
        return (hasManySiblings(img, minX, minY, w, h) && hasManySiblings(other, minX, minY, w, h))
            || (hasManySiblings(img, maxX, maxY, w, h) && hasManySiblings(other, maxX, maxY, w, h))
    }

    // MARK: comparison

    struct Parameters {
        var scale = 3.0
        var threshold = 0.1
        var masks: [(x: Double, y: Double, w: Double, h: Double)] = []
        var statusBarPt = 54.0
        var homeIndicatorPt = 34.0
        var maxShift = 12
        var mergeGapPt = 6.0
    }

    // Pixel states. Anything above `diff` is excluded from or forgiven by the metrics.
    static let same: UInt8 = 0, diff: UInt8 = 1, forgiven: UInt8 = 2, faint: UInt8 = 3, outside: UInt8 = 4, masked: UInt8 = 5

    struct Cluster {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var pixels = 0
        var sums = [Int](repeating: 0, count: 6)
    }

    static func compare(_ ref: Image, _ cand: Image, _ params: Parameters,
                        heatmapPath: String?, compositePath: String?) -> [String: Any] {
        let W = min(ref.width, cand.width), H = min(ref.height, cand.height)
        let UW = max(ref.width, cand.width), UH = max(ref.height, cand.height)
        let scale = params.scale
        func crop(_ img: Image) -> [UInt32] {
            if img.width == W && img.height == H { return img.pixels }
            var out = [UInt32](repeating: 0, count: W * H)
            for y in 0..<H { for x in 0..<W { out[y * W + x] = img.pixels[y * img.width + x] } }
            return out
        }
        let pa = crop(ref), pb = crop(cand)

        var state = [UInt8](repeating: same, count: UW * UH)
        var maskedCount = 0
        for m in params.masks {
            let x0 = max(0, Int((m.x * scale).rounded(.down))), x1 = min(UW, Int(((m.x + m.w) * scale).rounded(.up)))
            let y0 = max(0, Int((m.y * scale).rounded(.down))), y1 = min(UH, Int(((m.y + m.h) * scale).rounded(.up)))
            if x1 > x0 && y1 > y0 { for y in y0..<y1 { for x in x0..<x1 { state[y * UW + x] = masked } } }
        }
        var outsideCount = 0
        if UW != W || UH != H {
            for y in 0..<UH { for x in 0..<UW where x >= W || y >= H {
                if state[y * UW + x] != masked { state[y * UW + x] = outside; outsideCount += 1 }
            } }
        }

        var sumD = 0.0, maxD = 0.0, diffCount = 0, forgivenCount = 0
        let limit = maxDelta * params.threshold * params.threshold
        pa.withUnsafeBufferPointer { a in pb.withUnsafeBufferPointer { b in
            state.withUnsafeMutableBufferPointer { st in
                compareLoop(a.baseAddress!, b.baseAddress!, st.baseAddress!, W, H, UW, limit, &sumD, &maxD, &diffCount, &forgivenCount)
            }
        } }
        for s in state where s == masked { maskedCount += 1 }
        let counted = max(1, UW * UH - maskedCount)
        let allDiff = diffCount + outsideCount
        let diffShare = Double(allDiff) / Double(counted)
        let meanD = (sumD + Double(outsideCount)) / Double(counted)
        let score = max(0, (1 - diffShare) * (1 - meanD))

        // Clusters.
        let clusters = findClusters(pa, pb, state, W, H, UW, mergeGapPx: Int((params.mergeGapPt * scale).rounded()))

        // Shift detection.
        func luma(_ px: [UInt32]) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: W * H)
            for y in 0..<H { for x in 0..<W {
                if state[y * UW + x] == masked { out[y * W + x] = 128; continue }
                let p = px[y * W + x]
                out[y * W + x] = UInt8((77 * Int(p & 0xFF) + 150 * Int((p >> 8) & 0xFF) + 29 * Int((p >> 16) & 0xFF)) >> 8)
            } }
            return out
        }
        let hasContent = W >= 64 && H >= 64
        let bigEnough = Double(H) / scale >= 400
        let shiftInput = ShiftDetector.Input(
            lumaReference: luma(pa), lumaCandidate: luma(pb), width: W, height: H, scale: scale,
            statusBarPx: bigEnough ? Int((params.statusBarPt * scale).rounded()) : 0,
            homeIndicatorPx: bigEnough ? Int((params.homeIndicatorPt * scale).rounded()) : 0,
            maxShift: params.maxShift,
            rowStats: { a, b in
                var d = 0, n = 0
                for y in a..<b { for x in 0..<W {
                    let s = state[y * UW + x]
                    if s == masked { continue }
                    n += 1
                    if s == diff { d += 1 }
                } }
                return (d, n)
            })
        let shift = (hasContent && allDiff > 0) ? ShiftDetector.detect(shiftInput) : ShiftResult(json: [:], runs: [])

        // Images.
        var images: [String: Any] = [:]
        if heatmapPath != nil || compositePath != nil {
            let heat = heatmap(ref, cand, state, UW, UH, clusters: clusters, shiftRuns: shift.runs)
            if let p = heatmapPath, writePNG(heat, width: UW, height: UH, to: p) { images["heatmap"] = p }
            if let p = compositePath {
                let (px, w, h) = composite(ref, cand, heat, UW, UH)
                if writePNG(px, width: w, height: h, to: p) { images["composite"] = p }
            }
        }

        func r(_ v: Double, _ digits: Double = 100) -> Double { (v * digits).rounded() / digits }
        func rgb(_ sums: [Int], _ off: Int, _ n: Int) -> String {
            func c(_ v: Int) -> Int { n == 0 ? 0 : v / n }
            return String(format: "#%02x%02x%02x", c(sums[off]), c(sums[off + 1]), c(sums[off + 2]))
        }
        let clusterJSON: [[String: Any]] = clusters.map { c in
            ["x": r(Double(c.minX) / scale), "y": r(Double(c.minY) / scale),
             "width": r(Double(c.maxX - c.minX + 1) / scale), "height": r(Double(c.maxY - c.minY + 1) / scale),
             "pixels": c.pixels, "referenceColor": rgb(c.sums, 0, c.pixels), "candidateColor": rgb(c.sums, 3, c.pixels)]
        }
        var result: [String: Any] = [
            "reference": ["width": ref.width, "height": ref.height],
            "candidate": ["width": cand.width, "height": cand.height],
            "sizeMismatch": ref.width != cand.width || ref.height != cand.height,
            "compared": ["width": W, "height": H, "widthPt": r(Double(W) / scale), "heightPt": r(Double(H) / scale)],
            "metrics": ["score": (score * 1_000_000).rounded() / 1_000_000, "diffPixels": allDiff,
                        "diffShare": (diffShare * 1_000_000).rounded() / 1_000_000,
                        "meanDistance": (meanD * 1_000_000).rounded() / 1_000_000, "maxDistance": r(maxD, 10000),
                        "antialiasedIgnored": forgivenCount, "maskedPixels": maskedCount, "comparedPixels": counted,
                        "outsidePixels": outsideCount],
            "clusters": clusterJSON,
            "shift": shift.json,
            "images": images,
        ]
        if W != UW || UH != H { result["note"] = "sizes differ: pixels outside the common top-left \(W)x\(H) region count as differing" }
        return result
    }

    @_optimize(speed)
    static func compareLoop(_ a: UnsafePointer<UInt32>, _ b: UnsafePointer<UInt32>, _ st: UnsafeMutablePointer<UInt8>,
                            _ W: Int, _ H: Int, _ UW: Int, _ limit: Double,
                            _ sumD: inout Double, _ maxD: inout Double, _ diffCount: inout Int, _ forgivenCount: inout Int) {
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x, u = y * UW + x
                if st[u] == masked { continue }
                let p = a[i], q = b[i]
                if p == q { continue }
                let d = delta(p, q)
                if d > limit {
                    if antialiased(a, x, y, W, H, b) || antialiased(b, x, y, W, H, a) {
                        st[u] = forgiven
                        forgivenCount += 1
                    } else {
                        st[u] = diff
                        diffCount += 1
                        let n = min(1, (d / maxDelta).squareRoot())
                        sumD += n
                        if n > maxD { maxD = n }
                    }
                } else {
                    st[u] = faint
                    sumD += (d / maxDelta).squareRoot()
                }
            }
        }
    }

    // MARK: clusters

    static func findClusters(_ pa: [UInt32], _ pb: [UInt32], _ state: [UInt8], _ W: Int, _ H: Int, _ UW: Int,
                             mergeGapPx: Int) -> [Cluster] {
        let B = 4
        let bw = (W + B - 1) / B, bh = (H + B - 1) / B
        var active = [Bool](repeating: false, count: bw * bh)
        var any = false
        for y in 0..<H { for x in 0..<W where state[y * UW + x] == diff { active[(y / B) * bw + x / B] = true; any = true } }
        guard any else { return [] }
        var parent = [Int32](repeating: -1, count: bw * bh)
        for i in 0..<active.count where active[i] { parent[i] = Int32(i) }
        func find(_ i: Int) -> Int {
            var r = i
            while Int(parent[r]) != r { r = Int(parent[r]) }
            var c = i
            while Int(parent[c]) != r { let n = Int(parent[c]); parent[c] = Int32(r); c = n }
            return r
        }
        let g = max(1, (mergeGapPx + B - 1) / B)
        for by in 0..<bh { for bx in 0..<bw where active[by * bw + bx] {
            let me = by * bw + bx
            for dy in 0...g { for dx in -g...g {
                if dy == 0 && dx <= 0 { continue }
                let nx = bx + dx, ny = by + dy
                if nx < 0 || nx >= bw || ny >= bh { continue }
                if active[ny * bw + nx] {
                    let ra = find(me), rb = find(ny * bw + nx)
                    if ra != rb { parent[ra] = Int32(rb) }
                }
            } }
        } }
        var acc: [Int: Cluster] = [:]
        for y in 0..<H { for x in 0..<W where state[y * UW + x] == diff {
            let root = find((y / B) * bw + x / B)
            var c = acc[root] ?? Cluster(minX: x, minY: y, maxX: x, maxY: y)
            c.minX = min(c.minX, x); c.maxX = max(c.maxX, x); c.minY = min(c.minY, y); c.maxY = max(c.maxY, y)
            c.pixels += 1
            let p = pa[y * W + x], q = pb[y * W + x]
            c.sums[0] += Int(p & 0xFF); c.sums[1] += Int((p >> 8) & 0xFF); c.sums[2] += Int((p >> 16) & 0xFF)
            c.sums[3] += Int(q & 0xFF); c.sums[4] += Int((q >> 8) & 0xFF); c.sums[5] += Int((q >> 16) & 0xFF)
            acc[root] = c
        } }
        var list = Array(acc.values).sorted { $0.pixels > $1.pixels }
        if list.count > 1500 { list = Array(list.prefix(1500)) }
        // Merge boxes that touch or are within the gap of each other.
        var merged = true
        while merged {
            merged = false
            outer: for i in 0..<list.count {
                for j in (i + 1)..<max(list.count, i + 1) {
                    let a = list[i], b = list[j]
                    if a.minX - mergeGapPx <= b.maxX && b.minX - mergeGapPx <= a.maxX
                        && a.minY - mergeGapPx <= b.maxY && b.minY - mergeGapPx <= a.maxY {
                        var m = a
                        m.minX = min(a.minX, b.minX); m.maxX = max(a.maxX, b.maxX)
                        m.minY = min(a.minY, b.minY); m.maxY = max(a.maxY, b.maxY)
                        m.pixels += b.pixels
                        for k in 0..<6 { m.sums[k] += b.sums[k] }
                        list[i] = m
                        list.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        list.sort { $0.pixels > $1.pixels }
        return Array(list.prefix(10))
    }

    // MARK: images

    static func gray(_ p: UInt32) -> Int {
        (77 * Int(p & 0xFF) + 150 * Int((p >> 8) & 0xFF) + 29 * Int((p >> 16) & 0xFF)) >> 8
    }
    @inline(__always) static func pack(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        0xFF00_0000 | UInt32(max(0, min(255, b))) << 16 | UInt32(max(0, min(255, g))) << 8 | UInt32(max(0, min(255, r)))
    }

    static func heatmap(_ ref: Image, _ cand: Image, _ state: [UInt8], _ UW: Int, _ UH: Int,
                        clusters: [Cluster], shiftRuns: [(y0: Int, y1: Int, dy: Double, dx: Double)]) -> [UInt32] {
        var out = [UInt32](repeating: pack(225, 225, 225), count: UW * UH)
        for y in 0..<UH { for x in 0..<UW {
            let i = y * UW + x
            let base: Int
            if x < ref.width && y < ref.height { base = gray(ref.pixels[y * ref.width + x]) }
            else if x < cand.width && y < cand.height { base = gray(cand.pixels[y * cand.width + x]) }
            else { base = 200 }
            let v = 255 - (255 - base) * 35 / 100   // desaturated, low contrast
            switch state[i] {
            case diff: out[i] = pack(235, 20, 20)
            case forgiven: out[i] = pack(255, 200, 0)
            case outside: out[i] = ((x + y) / 6) % 2 == 0 ? pack(200, 60, 200) : pack(235, 200, 235)
            case masked:
                let hatch = ((x + y) / 5) % 4 == 0
                out[i] = hatch ? pack(40, 90, 220) : pack(v * 6 / 10 + 70, v * 6 / 10 + 90, v * 6 / 10 + 130)
            default: out[i] = pack(v, v, v)
            }
        } }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: UInt32, _ t: Int) {
            for y in max(0, y0)...min(UH - 1, y1) { for x in max(0, x0)...min(UW - 1, x1) {
                if x - x0 < t || x1 - x < t || y - y0 < t || y1 - y < t { out[y * UW + x] = color }
            } }
        }
        for c in clusters where c.maxX >= c.minX {
            let m = 4
            rect(c.minX - m, c.minY - m, c.maxX + m, c.maxY + m, pack(0, 150, 60), 2)
        }
        for run in shiftRuns where run.y1 > run.y0 {
            for y in run.y0..<min(UH, run.y1) { for x in 0..<min(UW, 8) { out[y * UW + x] = pack(0, 90, 255) } }
        }
        return out
    }

    static func panel(_ img: Image, _ UW: Int, _ UH: Int) -> [UInt32] {
        var out = [UInt32](repeating: pack(200, 200, 200), count: UW * UH)
        for y in 0..<img.height { for x in 0..<img.width { out[y * UW + x] = img.pixels[y * img.width + x] } }
        return out
    }

    /// `reference | candidate | heatmap`, shrunk by an integer factor if wider than 2400 pixels.
    static func composite(_ ref: Image, _ cand: Image, _ heat: [UInt32], _ UW: Int, _ UH: Int) -> ([UInt32], Int, Int) {
        let gap = 16
        let total = UW * 3 + gap * 2
        var big = [UInt32](repeating: pack(50, 50, 55), count: total * UH)
        let panels = [panel(ref, UW, UH), panel(cand, UW, UH), heat]
        for (k, p) in panels.enumerated() {
            let ox = k * (UW + gap)
            for y in 0..<UH { for x in 0..<UW { big[y * total + ox + x] = p[y * UW + x] } }
        }
        let f = max(1, (total + 2399) / 2400)
        if f == 1 { return (big, total, UH) }
        let w = total / f, h = UH / f
        var out = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var r = 0, g = 0, b = 0
            for dy in 0..<f { for dx in 0..<f {
                let p = big[(y * f + dy) * total + x * f + dx]
                r += Int(p & 0xFF); g += Int((p >> 8) & 0xFF); b += Int((p >> 16) & 0xFF)
            } }
            let n = f * f
            out[y * w + x] = pack(r / n, g / n, b / n)
        } }
        return (out, w, h)
    }

    // MARK: runner mode

    /// `--compare <jobs.json>`: {"jobs": [{"id", "reference", "candidate", "scale", "threshold", "masks": [[x,y,w,h]],
    /// "heatmap", "composite", "statusBar", "homeIndicator", "maxShift"}]}. Prints {"results": [...]}.
    static func runJobs(_ jobsPath: String) -> Never {
        func die(_ m: String) -> Never {
            FileHandle.standardError.write(Data(("error: " + m + "\n").utf8))
            exit(2)
        }
        guard let data = FileManager.default.contents(atPath: jobsPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = root["jobs"] as? [[String: Any]] else { die("cannot read compare jobs from \(jobsPath)") }
        var results: [[String: Any]] = []
        for job in jobs {
            var out: [String: Any] = ["id": job["id"] ?? ""]
            var params = Parameters()
            if let v = job["scale"] as? Double { params.scale = v }
            if let v = job["threshold"] as? Double { params.threshold = v }
            if let v = job["statusBar"] as? Double { params.statusBarPt = v }
            if let v = job["homeIndicator"] as? Double { params.homeIndicatorPt = v }
            if let v = job["maxShift"] as? Int { params.maxShift = v }
            for m in (job["masks"] as? [[Double]]) ?? [] where m.count == 4 { params.masks.append((m[0], m[1], m[2], m[3])) }
            guard let rp = job["reference"] as? String, let cp = job["candidate"] as? String else {
                out["error"] = "missing paths"; results.append(out); continue
            }
            guard let ref = decode(rp) else { out["error"] = "cannot decode reference \(rp)"; results.append(out); continue }
            guard let cand = decode(cp) else { out["error"] = "cannot decode candidate \(cp)"; results.append(out); continue }
            out.merge(compare(ref, cand, params, heatmapPath: job["heatmap"] as? String, compositePath: job["composite"] as? String)) { a, _ in a }
            results.append(out)
        }
        guard let json = try? JSONSerialization.data(withJSONObject: ["results": results], options: [.sortedKeys]) else { die("cannot encode results") }
        print(String(decoding: json, as: UTF8.self))
        exit(0)
    }
}
