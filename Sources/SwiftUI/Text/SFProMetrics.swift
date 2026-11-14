// SF Pro's advance widths, for setting the substitute font when SF Pro itself is not installed.
//
// The idea is the one web font loaders use to avoid layout shift: keep the fallback font's
// letter shapes but give every character the width it has in the real font, so lines break
// and labels measure the same either way. Unlike a single size-adjust factor this is per
// character, per weight and per size (SF Pro changes its spacing with size).

struct SFProMetrics {
    private static let indexOfCodePoint: [UInt32: Int] = {
        var map: [UInt32: Int] = [:]
        for (i, cp) in SFProMetricsData.codePoints.enumerated() { map[cp] = i }
        return map
    }()

    private static func decode(_ hex: String, signed: Bool) -> [Double] {
        let bytes = Array(hex.utf8)
        var values: [Double] = []
        values.reserveCapacity(bytes.count / 4)
        func nibble(_ b: UInt8) -> Int { b <= 57 ? Int(b) - 48 : Int(b) - 87 }
        var i = 0
        while i + 3 < bytes.count {
            var v = (nibble(bytes[i]) << 12) | (nibble(bytes[i + 1]) << 8) | (nibble(bytes[i + 2]) << 4) | nibble(bytes[i + 3])
            if signed, v >= 0x8000 { v -= 0x10000 }
            values.append(Double(v))
            i += 4
        }
        return values
    }

    private static let at17 = SFProMetricsData.advancesAtOpticalSize17.map { decode($0, signed: false) }
    private static let at28 = SFProMetricsData.advancesAtOpticalSize28.map { decode($0, signed: false) }
    private static let trackingValues = decode(SFProMetricsData.tracking, signed: true)

    private static func bracket(_ value: Double, in stops: [Double]) -> (Int, Int, Double) {
        if value <= stops[0] { return (0, 0, 0) }
        if value >= stops[stops.count - 1] { return (stops.count - 1, stops.count - 1, 0) }
        let upper = stops.firstIndex { $0 >= value }!
        return (upper - 1, upper, (value - stops[upper - 1]) / (stops[upper] - stops[upper - 1]))
    }

    /// Advances in points for one size and weight, by code point index.
    let advances: [CGFloat]
    let tabularDigit: CGFloat

    private static var cache: [[Double]: SFProMetrics] = [:]

    static func resolve(size: CGFloat, weight: CGFloat) -> SFProMetrics {
        let key = [Double(size), Double(weight)]
        if let cached = cache[key] { return cached }
        let (w0, w1, wt) = bracket(Double(weight), in: SFProMetricsData.weights)
        // SF Pro's optical-size axis runs from 17pt to 28pt and is flat outside that range.
        let optical = max(0, min(1, (Double(size) - 17) / 11))
        let (t0, t1, tt) = bracket(Double(size), in: SFProMetricsData.trackingSizes)
        let tracking = trackingValues[t0] + (trackingValues[t1] - trackingValues[t0]) * tt
        let unit = Double(size) / Double(SFProMetricsData.unitsPerEm)
        func value(_ table: [[Double]], _ i: Int) -> Double { table[w0][i] + (table[w1][i] - table[w0][i]) * wt }
        var advances = [CGFloat](repeating: 0, count: SFProMetricsData.codePoints.count)
        for i in advances.indices {
            let a17 = value(at17, i), a28 = value(at28, i)
            // 0 marks a character the font does not map one-to-one; the caller falls back.
            advances[i] = a17 == 0 || a28 == 0 ? 0 : CGFloat((a17 + (a28 - a17) * optical + tracking) * unit)
        }
        func tabular(_ table: [Double]) -> Double { table[w0] + (table[w1] - table[w0]) * wt }
        let t17 = tabular(SFProMetricsData.tabularDigitAtOpticalSize17), t28 = tabular(SFProMetricsData.tabularDigitAtOpticalSize28)
        let metrics = SFProMetrics(advances: advances, tabularDigit: CGFloat((t17 + (t28 - t17) * optical + tracking) * unit))
        if cache.count > 2000 { cache.removeAll() }
        cache[key] = metrics
        return metrics
    }

    /// SF Pro's advance for a character, or nil if it is outside the measured set.
    func advance(of scalar: Unicode.Scalar, tabularDigits: Bool) -> CGFloat? {
        if tabularDigits, scalar.value >= 0x30, scalar.value <= 0x39 { return tabularDigit }
        guard let index = SFProMetrics.indexOfCodePoint[scalar.value] else { return nil }
        let value = advances[index]
        return value > 0 ? value : nil
    }
}
