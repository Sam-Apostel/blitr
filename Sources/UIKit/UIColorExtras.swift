// The rest of UIColor: more initializers, component access, system colors that only some
// platforms define (all are available here, so shared code compiles for every --platform).

import Foundation
import SwiftUI

extension UIColor {
    public convenience init(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    public convenience init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) {
        self.init(named: name)
    }
    /// A pattern color draws as the image's average color.
    public convenience init(patternImage image: UIImage) {
        var average = RGBA(0.5, 0.5, 0.5, 1)
        if let pixels = image.cgImage?.box.rgba(premultiplied: false), !pixels.isEmpty {
            var sum = [0.0, 0.0, 0.0, 0.0]
            for i in stride(from: 0, to: pixels.count, by: 4) { for k in 0..<4 { sum[k] += Double(pixels[i + k]) } }
            let n = Double(pixels.count / 4) * 255
            average = RGBA(sum[0] / n, sum[1] / n, sum[2] / n, sum[3] / n)
        }
        self.init(average)
    }

    private var currentRGBA: RGBA { UITraitCollection.current.userInterfaceStyle == .dark ? dynamic.dark : dynamic.light }

    @discardableResult
    public func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?,
                       brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        let c = currentRGBA
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) } else if mx == c.g { h = (c.b - c.r) / d + 2 } else { h = (c.r - c.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        hue?.pointee = CGFloat(h)
        saturation?.pointee = CGFloat(mx == 0 ? 0 : d / mx)
        brightness?.pointee = CGFloat(mx)
        alpha?.pointee = CGFloat(c.a)
        return true
    }

    public func withProminence(_ prominence: Prominence) -> UIColor {
        switch prominence {
        case .primary: return self
        case .secondary: return withAlphaComponent(0.6)
        case .tertiary: return withAlphaComponent(0.3)
        case .quaternary: return withAlphaComponent(0.18)
        }
    }
    public enum Prominence: Int, Sendable { case primary, secondary, tertiary, quaternary }
    public var accessibilityName: String { "color" }

    public static var lightText: UIColor { UIColor(white: 1, alpha: 0.6) }
    public static var darkText: UIColor { UIColor(white: 0, alpha: 1) }
    public static var groupTableViewBackground: UIColor { .systemGroupedBackground }
}

extension UIColor {
    public convenience init(cgColor: CGColor) { self.init(RGBA(cgColor.rgba.r, cgColor.rgba.g, cgColor.rgba.b, cgColor.rgba.a)) }
    /// Resolved in the appearance being rendered.
    public var cgColor: CGColor {
        let c = UITraitCollection.current.userInterfaceStyle == .dark ? dynamic.dark : dynamic.light
        return CGColor(r: c.r, g: c.g, b: c.b, a: c.a)
    }
}
