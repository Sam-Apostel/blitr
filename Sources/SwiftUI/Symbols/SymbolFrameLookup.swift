import Foundation

// Lookup over SymbolFrames.generated.swift (scripts/mac/measure-symbol-frames.sh): the frame iOS gives
// `Image(systemName:)` for a weight, image scale and point size.

extension SymbolFrames {
    /// name -> 24 pixel sizes at 3x for a 100pt font (weight-major, then scale, then width, height).
    private static let index: [String: [Int32]] = {
        var out: [String: [Int32]] = [:]
        out.reserveCapacity(1300)
        for line in source.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let values = line[line.index(after: tab)...].split(separator: ",").compactMap { Int32($0) }
            guard values.count == weights.count * 3 * 2 else { continue }
            out[String(line[..<tab])] = values
        }
        return out
    }()

    static func contains(_ name: String) -> Bool { index[name] != nil }

    /// The measured size factor for a point size (measured / linear from 100pt): the exact point size and scale
    /// when measured, otherwise the nearest measured point size at medium scale.
    static func sizeFactor(pointSize: CGFloat, scale: Int) -> (width: CGFloat, height: CGFloat) {
        if pointSize == referencePointSize { return (1, 1) }
        if let exact = sizeFactors.first(where: { $0.pointSize == Double(pointSize) && $0.scale == scale }) {
            return (exact.width, exact.height)
        }
        let medium = sizeFactors.filter { $0.scale == 1 }
        guard let nearest = medium.min(by: { abs($0.pointSize - Double(pointSize)) < abs($1.pointSize - Double(pointSize)) }),
              abs(nearest.pointSize - Double(pointSize)) < abs(referencePointSize - Double(pointSize)) else { return (1, 1) }
        return (nearest.width, nearest.height)
    }

    /// The frame of `name` at a font weight (100 ultralight ... 900 black), image scale and point size, rounded to
    /// the nearest 1/3pt: the stored 100pt frame (interpolated between the bracketing stored weights), scaled to
    /// the point size and corrected by the size factor.
    static func frame(named name: String, weight: CGFloat, scale: Image.Scale, pointSize: CGFloat) -> CGSize? {
        guard let v = index[name] else { return nil }
        let s = scale == .small ? 0 : scale == .large ? 2 : 1
        let w = min(max(Double(weight), weights[0]), weights[weights.count - 1])
        let hi = weights.firstIndex(where: { $0 >= w }) ?? weights.count - 1
        let lo = weights[hi] == w ? hi : max(hi - 1, 0)
        let t = hi == lo ? 0 : (w - weights[lo]) / (weights[hi] - weights[lo])
        func at(_ i: Int, _ k: Int) -> Double { Double(v[(i * 3 + s) * 2 + k]) }
        let px = (0...1).map { k in at(lo, k) + (at(hi, k) - at(lo, k)) * t }
        let factor = sizeFactor(pointSize: pointSize, scale: s)
        let k = Double(pointSize) / referencePointSize
        let width = (px[0] * k * Double(factor.width)).rounded() / 3
        let height = (px[1] * k * Double(factor.height)).rounded() / 3
        return CGSize(width: width, height: height)
    }
}

extension SymbolGlyph {
    /// Open-icon artwork laid out at a measured SF Symbol frame: its ink, aspect-fit and centred in the frame
    /// less the vertical padding SF Symbols have (AppleSymbols.verticalPadding x the scaled point size).
    /// Against the iOS 27.0 references (light) this scored best: diffShare summed over 62 screens went from
    /// 51.38% to 41.45%, against 42.28% for fitting the whole square viewBox and 45.78% for stretching the ink
    /// to the frame (six screens worse by 0.05% or more).
    @MainActor static func fitted(_ viewBox: CGSize, _ layers: [Layer], frame: CGSize, pointSize: CGFloat, scale: Image.Scale) -> SymbolGlyph {
        let scaled = pointSize * (scale == .small ? 0.795 : scale == .large ? 1.28 : 1)
        var pad = ((AppleSymbols.verticalPadding * scaled) * 3).rounded() / 3
        if frame.height - 2 * pad <= 0 { pad = 0 }
        var ink: CGRect?
        for layer in layers {
            let r = (layer.stroke.map { layer.path.stroke($0) } ?? layer.path).boundingRect
            if r.width > 0 || r.height > 0 { ink = ink.map { $0.union(r) } ?? r }
        }
        guard let ink, ink.height > 0,
              var glyph = inkCropped(viewBox: viewBox, layers: layers, unit: (frame.height - 2 * pad) / ink.height, verticalPadding: pad)
        else { return SymbolGlyph(size: frame, viewBox: viewBox, layers: layers) }
        glyph.size = frame
        return glyph
    }
}
