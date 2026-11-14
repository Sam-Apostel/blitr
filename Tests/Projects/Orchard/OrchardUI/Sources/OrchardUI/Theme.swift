import SwiftUI
import CoreText

public enum OrchardTheme {
    /// Registers the bundled pixel font once. On Linux the registration is a no-op that succeeds; the
    /// renderer finds the font among the package's resources.
    private static let registered: Void = {
        if let url = Bundle.module.url(forResource: "OrchardPixel", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    public static func registerFonts() { _ = registered }

    public static func pixel(_ size: CGFloat) -> Font {
        registerFonts()
        return .custom("OrchardPixel", size: size)
    }

    /// Looked up by name in the package's catalog.
    public static let leaf = Color("Leaf", bundle: .module)
    /// The generated symbol for the same catalog (display P3, with a high-contrast variant).
    public static let bark = Color(.bark)
    public static let blossom = Color(.blossom)

    public static let cardRadius: CGFloat = 14
}

extension View {
    /// The card every orchard surface sits on.
    public func orchardCard() -> some View {
        padding(14)
            .background(OrchardTheme.blossom.opacity(0.35), in: RoundedRectangle(cornerRadius: OrchardTheme.cardRadius, style: .continuous))
    }
}
