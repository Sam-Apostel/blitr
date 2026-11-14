// UIColor / UIImage / UIFont: the value types app code passes into SwiftUI. On iOS, tvOS and visionOS
// `import SwiftUI` makes them visible too (the preprocessor adds `import UIKit`), so `Color(.systemBackground)`
// works with only `import SwiftUI` there, as on Apple platforms.

import Foundation
import SwiftUI

public enum UIUserInterfaceStyle: Int, Hashable, Sendable { case unspecified, light, dark }
public enum UIUserInterfaceSizeClass: Int, Hashable, Sendable { case unspecified, compact, regular }
public enum UIUserInterfaceIdiom: Int, Hashable, Sendable { case unspecified = -1, phone, pad, tv, carPlay, mac, vision }

public final class UIColor: Hashable {
    let dynamic: DynamicColor

    init(_ dynamic: DynamicColor) { self.dynamic = dynamic }
    convenience init(_ rgba: RGBA) { self.init(DynamicColor(light: rgba, dark: rgba)) }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(RGBA(Double(red), Double(green), Double(blue), Double(alpha)))
    }
    public convenience init(white: CGFloat, alpha: CGFloat) { self.init(red: white, green: white, blue: white, alpha: alpha) }
    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let c = Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
        self.init(c.rgba(in: EnvironmentValues()))
    }
    public convenience init(_ color: Color) {
        var light = EnvironmentValues(), dark = EnvironmentValues()
        light.colorScheme = .light
        dark.colorScheme = .dark
        self.init(DynamicColor(light: color.rgba(in: light), dark: color.rgba(in: dark)))
    }
    public convenience init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) {
        let light = dynamicProvider(UITraitCollection(userInterfaceStyle: .light)).dynamic.light
        let dark = dynamicProvider(UITraitCollection(userInterfaceStyle: .dark)).dynamic.dark
        self.init(DynamicColor(light: light, dark: dark))
    }
    /// Colors from an asset catalog (pass `--assets`); a missing color renders magenta.
    public convenience init?(named name: String) {
        let found = MainActor.assumeIsolated { () -> DynamicColor? in
            guard let light = AssetCatalog.shared.color(named: name, scheme: .light) else { return nil }
            return DynamicColor(light: light, dark: AssetCatalog.shared.color(named: name, scheme: .dark) ?? light)
        }
        self.init(found ?? DynamicColor(light: RGBA(1, 0, 1, 1), dark: RGBA(1, 0, 1, 1)))
    }

    public func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        UIColor(DynamicColor(light: dynamic.light.withAlpha(Double(alpha)), dark: dynamic.dark.withAlpha(Double(alpha))))
    }
    public func resolvedColor(with traitCollection: UITraitCollection) -> UIColor {
        UIColor(traitCollection.userInterfaceStyle == .dark ? dynamic.dark : dynamic.light)
    }
    @discardableResult
    public func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?,
                       blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        let c = dynamic.light
        red?.pointee = CGFloat(c.r); green?.pointee = CGFloat(c.g); blue?.pointee = CGFloat(c.b); alpha?.pointee = CGFloat(c.a)
        return true
    }
    @discardableResult
    public func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        white?.pointee = CGFloat(dynamic.light.luminance); alpha?.pointee = CGFloat(dynamic.light.a)
        return true
    }

    public static func == (a: UIColor, b: UIColor) -> Bool { a.dynamic == b.dynamic }
    public func hash(into hasher: inout Hasher) { hasher.combine(dynamic) }

    // Fixed colors
    public static var black: UIColor { UIColor(RGBA.black) }
    public static var white: UIColor { UIColor(RGBA.white) }
    public static var clear: UIColor { UIColor(RGBA.clear) }
    public static var red: UIColor { UIColor(RGBA(1, 0, 0)) }
    public static var green: UIColor { UIColor(RGBA(0, 1, 0)) }
    public static var blue: UIColor { UIColor(RGBA(0, 0, 1)) }
    public static var cyan: UIColor { UIColor(RGBA(0, 1, 1)) }
    public static var yellow: UIColor { UIColor(RGBA(1, 1, 0)) }
    public static var magenta: UIColor { UIColor(RGBA(1, 0, 1)) }
    public static var orange: UIColor { UIColor(RGBA(1, 0.5, 0)) }
    public static var purple: UIColor { UIColor(RGBA(0.5, 0, 0.5)) }
    public static var brown: UIColor { UIColor(RGBA(0.6, 0.4, 0.2)) }
    public static var gray: UIColor { UIColor(RGBA(0.5, 0.5, 0.5)) }
    public static var darkGray: UIColor { UIColor(RGBA(1.0 / 3, 1.0 / 3, 1.0 / 3)) }
    public static var lightGray: UIColor { UIColor(RGBA(2.0 / 3, 2.0 / 3, 2.0 / 3)) }

    // Adaptive system colors
    public static var systemRed: UIColor { UIColor(SystemColor.red) }
    public static var systemOrange: UIColor { UIColor(SystemColor.orange) }
    public static var systemYellow: UIColor { UIColor(SystemColor.yellow) }
    public static var systemGreen: UIColor { UIColor(SystemColor.green) }
    public static var systemMint: UIColor { UIColor(SystemColor.mint) }
    public static var systemTeal: UIColor { UIColor(SystemColor.teal) }
    public static var systemCyan: UIColor { UIColor(SystemColor.cyan) }
    public static var systemBlue: UIColor { UIColor(SystemColor.blue) }
    public static var systemIndigo: UIColor { UIColor(SystemColor.indigo) }
    public static var systemPurple: UIColor { UIColor(SystemColor.purple) }
    public static var systemPink: UIColor { UIColor(SystemColor.pink) }
    public static var systemBrown: UIColor { UIColor(SystemColor.brown) }
    public static var systemGray: UIColor { UIColor(SystemColor.gray) }
    public static var systemGray2: UIColor { UIColor(SystemColor.gray2) }
    public static var systemGray3: UIColor { UIColor(SystemColor.gray3) }
    public static var systemGray4: UIColor { UIColor(SystemColor.gray4) }
    public static var systemGray5: UIColor { UIColor(SystemColor.gray5) }
    public static var systemGray6: UIColor { UIColor(SystemColor.gray6) }
    public static var tintColor: UIColor { UIColor(SystemColor.blue) }

    public static var label: UIColor { UIColor(SystemColor.label) }
    public static var secondaryLabel: UIColor { UIColor(SystemColor.secondaryLabel) }
    public static var tertiaryLabel: UIColor { UIColor(SystemColor.tertiaryLabel) }
    public static var quaternaryLabel: UIColor { UIColor(SystemColor.quaternaryLabel) }
    public static var placeholderText: UIColor { UIColor(SystemColor.placeholderText) }
    public static var separator: UIColor { UIColor(SystemColor.separator) }
    public static var opaqueSeparator: UIColor { UIColor(SystemColor.opaqueSeparator) }
    public static var link: UIColor { UIColor(SystemColor.link) }
    public static var systemBackground: UIColor { UIColor(SystemColor.background) }
    public static var secondarySystemBackground: UIColor { UIColor(SystemColor.secondaryBackground) }
    public static var tertiarySystemBackground: UIColor { UIColor(SystemColor.tertiaryBackground) }
    public static var systemGroupedBackground: UIColor { UIColor(SystemColor.groupedBackground) }
    public static var secondarySystemGroupedBackground: UIColor { UIColor(SystemColor.secondaryGroupedBackground) }
    public static var tertiarySystemGroupedBackground: UIColor { UIColor(SystemColor.tertiaryGroupedBackground) }
    public static var systemFill: UIColor { UIColor(SystemColor.fill) }
    public static var secondarySystemFill: UIColor { UIColor(SystemColor.secondaryFill) }
    public static var tertiarySystemFill: UIColor { UIColor(SystemColor.tertiaryFill) }
    public static var quaternarySystemFill: UIColor { UIColor(SystemColor.quaternaryFill) }
}

extension DynamicColor {
    init(light: RGBA, dark: RGBA) {
        self.init(0, 0)
        self.light = light
        self.dark = dark
    }
}
extension RGBA {
    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
}

extension Color {
    public init(_ color: UIColor) { self.init(color.dynamic) }
    public init(uiColor: UIColor) { self.init(uiColor.dynamic) }
}

