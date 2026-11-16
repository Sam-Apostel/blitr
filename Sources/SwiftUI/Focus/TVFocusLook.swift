// The tvOS look of focus: metrics, colors and the one node that draws a focused (lifted) control.
//
// Every tvOS control draws its own focused state (Controls/TVButton.swift, Chrome/TV/*): it reads
// `isFocused`, which `FocusElementModifier` sets for the focused element, and wraps itself in a
// `TVLiftNode` with the matching style. There is no generic effect laid over arbitrary views any more:
// tvOS does not draw one for custom `ButtonStyle`s or `.focusable()` views either (WWDC20 "Build
// SwiftUI apps for tvOS": a custom button style "adds no existing effects for pressing and focused
// states"); `hoverEffect(_:)` is how such views opt into the system lift.
//
// The scale of a focused control is drawn only: frames, and so the focus engine's geometry, stay
// those of the unscaled layout (as on tvOS, where focus movement uses the unfocused frames).
//
// Sources for the numbers are in docs/TVOS.md. "measured" values come from the tvOS 26.5 simulator
// (Tests/Reference/tvos-26.5, scripts/calibrate.py --platform tvos) or Apple's HIG where noted; "est." are
// estimates (tvOS 18, and states the reference set does not show).

enum TVMetrics {
    // MARK: Focus lift
    /// Scale of a focused button platter, card or lifted image (est.: HIG shows focused items "elevated";
    /// community measurements and SwiftUI samples use 1.05 to 1.1).
    static let liftScale: CGFloat = 1.1
    /// A focused list row grows only slightly (HIG Lists: "slightly increases in size"; amount est.).
    static let rowLiftScale: CGFloat = 1.03
    /// Tab bar items and segments grow a little when focused (est.).
    static let smallLiftScale: CGFloat = 1.06
    /// tvOS 26: a focused button, toggle, text field or list row does not scale; its platter grows by 4 pt on
    /// every side and turns white (measured: 170.5 x 66 -> 178.5 x 74, a 1760 x 66 row -> 1768 x 74).
    static let glassFocusGrowth: CGFloat = 4
    /// tvOS 26: a focused `.card` button scales so that its longer side grows by 40 pt (measured: 300 x 170 ->
    /// 340 x 192.7, 300 x 420 -> 328.6 x 460, 480 x 270 -> 520 x 292.5, 200 x 200 -> 240 x 240).
    static let glassCardLiftGrowth: CGFloat = 40
    /// tvOS 26 shadow under a focused platter (measured from its falloff: 39% darker 3 pt below the
    /// platter, 26% at 11 pt, 15% at 19 pt, gone by 35 pt; 9% at 1 pt beside it, 5% at 1 pt above): a
    /// gaussian of sigma 10 (radius 20) at 50% black, 12 pt down, 8 pt narrower than the platter on each side.
    static let glassShadowRadius: CGFloat = 20
    static let glassShadowY: CGFloat = 12
    static let glassShadowOpacity: Double = 0.5
    static let glassShadowInset: CGFloat = 8
    /// Drop shadow under a lifted element (tvOS 18, est.).
    static let liftShadowRadius: CGFloat = 30
    static let liftShadowY: CGFloat = 18
    static let liftShadowOpacity: Double = 0.35
    /// Specular highlight on lifted cards and images: brightest at the top (est.).
    static let specularOpacity: Double = 0.28

    // MARK: Buttons
    /// Height of a regular bordered button (measured from the tvOS 26 media player image in the HIG
    /// Materials page: 44 px at 1280 px wide = 66 pt).
    static let buttonHeight: CGFloat = 66
    /// measured: tvOS 26.5, every control size (label ink starts 31-33 pt in, incl. side bearing).
    static let buttonHorizontalPadding: CGFloat = 30
    static let buttonIconSpacing: CGFloat = 20            // measured approx. ("Play" with play.fill: 153 pt wide)
    /// tvOS 26 `.plain` buttons: unfocused, the bare label; focused, a light platter reaching 30 pt beyond the
    /// label at the sides and 15 pt above and below (then grown by the usual 4 pt), corners of 36.5 pt (a
    /// capsule around one line of text), a 1.5 pt white rim, and the focus shadow. The label does not move or
    /// scale (measured: tvOS 26.5 simulator, "Plain text" 118 x 35 -> a 178 x 65 element whose platter spans
    /// 1045.5 to 1229.5 by 373 to 446; a 240 x 404 artwork label -> 735.5 to 1043.5 by 373 to 815).
    static let glassPlainHorizontalOutset: CGFloat = 30
    static let glassPlainVerticalOutset: CGFloat = 15
    static let glassPlainCornerRadius: CGFloat = 36.5
    static let glassPlainRim: CGFloat = 1.5
    /// tvOS 18 bordered buttons are rounded rectangles (est. radius); tvOS 26 buttons are capsules (HIG images).
    static let buttonCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12             // est.

    /// Small 50 and large 85 are measured (tvOS 26.5); mini and extra large est.
    static func buttonHeight(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 42
        case .small: return 50
        case .regular: return buttonHeight
        case .large: return 85
        case .extraLarge: return 96
        }
    }
    static func buttonPadding(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 22
        case .small, .regular, .large: return buttonHorizontalPadding
        case .extraLarge: return 36
        }
    }
    /// Label font by control size (measured: small labels are caption size, large ones callout size).
    static func buttonFont(_ size: ControlSize) -> Font? {
        switch size {
        case .mini: return .caption2
        case .small: return .caption
        case .regular: return nil
        case .large, .extraLarge: return .callout
        }
    }

    // MARK: Tab bar
    /// HIG Tab bars (tvOS): "The height of a tab bar is 68 points, and its top edge is 46 points from
    /// the top of the screen." (measured; tvOS 18 and earlier).
    static let tabBarTop: CGFloat = 46
    static let tabBarHeight: CGFloat = 68
    static let tabItemHorizontalPadding: CGFloat = 28     // est.
    static let tabItemSpacing: CGFloat = 4                // est.
    static let tabItemInset: CGFloat = 6                  // est.: selection pill inside the bar
    /// Space between the bottom of the tab bar and the content's safe area (est.).
    static let tabBarContentGap: CGFloat = 26

    // MARK: Sidebar (`.sidebarAdaptable`)
    static let sidebarWidth: CGFloat = 400                // est.
    static let sidebarCollapsedWidth: CGFloat = 112       // est.
    static let sidebarRowHeight: CGFloat = 66             // est.
    static let sidebarInset: CGFloat = 40                 // est.

    // MARK: Lists (measured: tvOS 26.5 Form, rows 66 pt on an 80 pt pitch, labels 20 pt in)
    static let rowMinHeight: CGFloat = 66
    /// A `Toggle` row in a plain `List` (not a `Form`) is 79 pt high, still 14 pt apart (measured: tvOS 26.5
    /// simulator, the focus recording of a List in a TabView: rows at 302 and 395, 79 pt high).
    static let listToggleRowHeight: CGFloat = 79
    static let rowHorizontalInset: CGFloat = 20
    static let rowVerticalInset: CGFloat = 15.5
    static let rowSpacing: CGFloat = 14
    static let rowCornerRadius: CGFloat = 12              // est. (tvOS 18); tvOS 26 rows are capsules
    /// From the last row (or footer) of a section to the next header.
    static let sectionSpacing: CGFloat = 26
    static let headerBottomGap: CGFloat = 6
    /// From the last row to the footer.
    static let footerTopGap: CGFloat = 20
    static let chevronSize = CGSize(width: 12, height: 22) // est.
    /// tvOS 26 rows that open something: the chevron's tip 3 pt further in than the row's text inset, the trailing
    /// value ending 81 pt before that inset (measured: tvOS 26.5 simulator, "12" ends at 1739, the tip at 1817.5,
    /// in a row whose text runs to 1820).
    static let glassChevronInset: CGFloat = 3
    static let glassChevronReserve: CGFloat = 81
    /// Headers: uppercase on tvOS 26, 29 pt (35 pt line), the dimmed title color; footers 29 pt secondary.
    static let headerFontSize: CGFloat = 29
    static let footerFontSize: CGFloat = 29

    // MARK: Navigation
    /// Title row at the top of a NavigationStack: content starts 91 pt below the safe area's top, the title
    /// (title 2, 57 pt) 4 pt below it (measured: tvOS 26.5).
    static let navigationTitleHeight: CGFloat = 91
    static let toolbarItemSpacing: CGFloat = 24           // est.

    // MARK: Search and text fields
    static let fieldHeight: CGFloat = 70                  // measured approx. (69.5 to 71 pt, tvOS 26.5)
    static let fieldCornerRadius: CGFloat = 12            // est.
    static let searchFieldHeight: CGFloat = 88            // est.

    // MARK: Alerts
    static let alertButtonWidth: CGFloat = 560            // est. (tvOS 18 full-screen alert)
    static let alertButtonSpacing: CGFloat = 20           // est.
    /// tvOS 26 alert and confirmation dialog cards (measured: tvOS 26.5). An alert with two actions is
    /// 586 pt wide with the buttons side by side (250 pt each, 24 apart, cancel first); a dialog is 502 pt
    /// wide with 440 pt buttons stacked 16 apart. Title 46 pt below the top, buttons 31 pt from the edges.
    static let glassAlertWidth: CGFloat = 586
    static let glassDialogWidth: CGFloat = 502
    static let glassAlertCornerRadius: CGFloat = 62
    static let glassAlertPadding: CGFloat = 46
    static let glassAlertButtonHeight: CGFloat = 66
    static let glassAlertButtonGap: CGFloat = 24
    static let glassDialogButtonGap: CGFloat = 16
    static let glassAlertButtonInset: CGFloat = 31
    static let glassAlertTitleGap: CGFloat = 17.5         // title to message
    static let glassAlertMessageGap: CGFloat = 37.5       // message to buttons
    static let glassDialogTitleGap: CGFloat = 83.5        // dialog title (no message) to buttons
    /// Black over the screen behind an alert or dialog (measured: the backdrop at 55%), and behind a sheet (80%).
    static let glassAlertDim: Double = 0.45
    static let glassSheetDim: Double = 0.2
    /// In dark mode the presenter is dimmed by 48% black (measured: tvOS 26.5 simulator, the backdrop 50 -> 26.4, a
    /// poster 187.5 -> 97).
    static func glassSheetDim(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.48 : glassSheetDim }
    /// Unfocused button labels in a dark tvOS 26 sheet are a softer white (measured: tvOS 26.5 simulator, 214).
    static let glassSheetButtonLabelDark = RGBA(214 / 255.0, 214 / 255.0, 214 / 255.0, 1)
    /// A tvOS 26 sheet is a glass card fitted to its content, 5 pt above and below it (measured).
    static let glassSheetVerticalPadding: CGFloat = 5

    // MARK: Switch (`.toggleStyle(.switch)`)
    static let switchSize = CGSize(width: 76, height: 44) // est.
}

/// Colors of tvOS controls (est., sampled from the HIG reference images where noted).
enum TVColors {
    /// Unfocused platter of a bordered button or toggle (HIG Alerts image: about 10% black over the
    /// light card, 20% white over the dark one).
    static func platter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.18) : RGBA(0.5, 0.5, 0.52, 0.24)
    }
    /// The focused platter: white in both appearances (HIG focus states image).
    static let focusedPlatter = RGBA(1, 1, 1, 1)
    /// Label on the focused white platter.
    static let focusedLabel = RGBA(0, 0, 0, 0.88)
    /// tvOS 26: labels on a focused platter, and the tab bar's titles in light, are black (measured: tvOS 26.5
    /// simulator, (0, 0, 0) on focused buttons, rows, alert actions, tabs and sidebar rows).
    static let glassFocusedLabel = RGBA(0, 0, 0, 1)
    static func focusedLabel(glass: Bool) -> RGBA { glass ? glassFocusedLabel : focusedLabel }
    /// A card's platter before it is focused (est.).
    static func cardPlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.12) : RGBA(0, 0, 0, 0.06)
    }
    /// The tab bar's translucent background (tvOS 18, est.).
    static func tabBar(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(0.2, 0.2, 0.21, 0.7) : RGBA(0.86, 0.86, 0.88, 0.75)
    }
    /// The selected tab while focus is elsewhere (est.: "only the selected tab is opaque").
    static func selectedTab(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.24) : RGBA(1, 1, 1, 0.85)
    }
    /// Unfocused tvOS 26 button, toggle or picker platter: a flat film over what is behind (measured, light:
    /// the backdrop at 91%; dark: white at 10%, (47, 49, 52) -> (67.5, 70, 73.5)).
    static func glassPlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.10) : RGBA(0, 0, 0, 0.09) // measured: tvOS 26.5 simulator
    }
    /// A focused tvOS 26 button, toggle, text field or segment (measured: tvOS 26.5 simulator): white in light,
    /// a light grey (207, 212, 217) in dark. Focused list rows and alert actions stay white in dark.
    static func glassFocusedPlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(207 / 255.0, 212 / 255.0, 217 / 255.0, 1) : RGBA(1, 1, 1, 1)
    }
    /// A focused tvOS 26 `.plain` button's platter (measured: tvOS 26.5 simulator; light: 242 over a backdrop of
    /// about 185, 245 -> 230 down a tall platter, white at about 82%; dark: 228 over about 45, white at 88%).
    static func glassPlainPlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.88) : RGBA(1, 1, 1, 0.82)
    }
    /// Unfocused tvOS 26 list row: a light film (measured: white at 15% in light, 10% in dark).
    static func glassRow(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.10) : RGBA(1, 1, 1, 0.15)
    }
    /// Unfocused tvOS 26 text field (measured: tvOS 26.5 simulator; light: white at 55%; dark: black at 32%,
    /// (50, 53, 58) -> (33, 36, 41)).
    static func glassField(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(0, 0, 0, 0.32) : RGBA(1, 1, 1, 0.55)
    }
    /// tvOS 26 segmented control track and its selected segment while focus is elsewhere (measured: tvOS 26.5
    /// simulator; light: white at 60%, the selected segment black at 18% over it; dark: no track, the
    /// selected segment white at 20%, (42, 40, 33) -> (84, 82, 77)).
    static func glassSegmentTrack(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? .clear : RGBA(1, 1, 1, 0.6)
    }
    static func glassSelectedSegment(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.2) : RGBA(0, 0, 0, 0.18)
    }
    /// A destructive bordered button on tvOS 26 is a red platter (measured: tvOS 26.5 simulator; light
    /// (237, 40, 48) with a red label; dark (255, 92, 96) with a lighter label, (255, 112, 117)).
    static func glassDestructivePlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 92 / 255.0, 96 / 255.0, 1) : RGBA(237 / 255.0, 40 / 255.0, 48 / 255.0, 1)
    }
    static let glassDestructiveLabelDark = RGBA(1, 112 / 255.0, 117 / 255.0, 1) // measured: tvOS 26.5 simulator
    /// Destructive actions in alerts and dialogs: red at 20% over the card (measured).
    static let glassDestructiveAction = RGBA(1, 0.23, 0.19, 0.2)
    /// Unfocused actions in alerts and dialogs (measured: tvOS 26.5 simulator; light: black at 10% over the card;
    /// dark: white at 10%, (23, 23, 23) -> (48, 47, 45)).
    static func glassAction(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.1) : RGBA(0, 0, 0, 0.1)
    }
    /// Navigation titles and section headers on tvOS 26 (measured: light (130, 135, 144) over the backdrop,
    /// black at about 42%; dark (103, 107, 111), white at about 27%).
    static func dimmedTitle(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.3) : RGBA(0, 0, 0, 0.42)
    }
    /// The value of a toggle outside a list (measured: tvOS 26.5 simulator; "Off" (49, 53, 63) over a (204, 208,
    /// 219) platter, black at about 76%; dark (199, 202, 206) over 70, white at about 70%).
    static func controlValue(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.7) : RGBA(0, 0, 0, 0.76)
    }
    /// A `.navigationLink` picker outside a list: no chevron, a dimmed label and a strong value (measured: tvOS
    /// 26.5 simulator; light: label (89, 87, 86) and value (33, 27, 21) over 193; dark: label 142 and value 191
    /// over 65).
    static func outsidePickerLabel(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.4) : RGBA(0, 0, 0, 0.54)
    }
    static func outsidePickerValue(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.66) : RGBA(0, 0, 0, 0.83)
    }
    /// An unfocused tvOS 26 toolbar item beside the navigation title (measured: tvOS 26.5 simulator, see
    /// TVMetrics.glassToolbarItemTop).
    static func glassToolbarItem(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.105) : RGBA(0, 0, 0, 0.075)
    }
    /// Trailing values of rows (measured: black at about 57%, white at about 55%).
    static func rowValue(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.55) : RGBA(0, 0, 0, 0.57)
    }
    /// The glass card of a tvOS 26 alert, dialog or sheet (measured: tvOS 26.5 simulator; light: the dimmed
    /// screen behind, 107, turns into 194 inside the card, about 60% white; dark: the dimmed screen, 23, turns
    /// into 25 inside the card).
    @MainActor static func glassCard(_ scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
        var a = GlassAppearance.system(.regular, scheme: scheme, design: design)
        a.tint = scheme == .dark ? RGBA(0.1, 0.1, 0.1, 0.6) : RGBA(1, 1, 1, 0.6)
        return a
    }
    /// The message of a tvOS 26 alert in dark mode (measured: tvOS 26.5 simulator, (154, 154, 152) over the
    /// card, white at about 56%).
    static let glassAlertMessageDark = RGBA(1, 1, 1, 0.56)
    /// A `.card` button's platter on tvOS 26 (measured: tvOS 26.5 simulator; light: white at about 28%; dark:
    /// white at 11%, (40, 40, 35) -> (65, 63, 59)).
    static func glassCardPlatter(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.11) : RGBA(1, 1, 1, 0.28)
    }
    static func dim(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(0, 0, 0, 0.7) : RGBA(0.94, 0.94, 0.95, 0.75)
    }
}

/// Environment the tvOS controls set for their content.
enum TVInListRowKey: EnvironmentKey { static let defaultValue = false }
/// True for content resolved on a focused white platter: label colors become the dark ones.
enum TVOnFocusedPlatterKey: EnvironmentKey { static let defaultValue = false }
/// Rows of a `Form` (not a plain `List`): tvOS 26 draws an automatic picker there as a value row.
enum TVInFormKey: EnvironmentKey { static let defaultValue = false }
/// Content of a tvOS sheet.
enum TVInSheetKey: EnvironmentKey { static let defaultValue = false }
/// A tvOS navigation bar item.
enum TVToolbarItemKey: EnvironmentKey { static let defaultValue = false }
/// Content of a tvOS bordered button's platter.
enum TVInButtonPlatterKey: EnvironmentKey { static let defaultValue = false }
/// `.hoverEffect(_:)` written on a view.
enum TVHoverEffectKey: EnvironmentKey { static let defaultValue: HoverEffect? = nil }

extension EnvironmentValues {
    var isTV: Bool { renderPlatform == .tvOS }
    var tvInSheet: Bool {
        get { self[TVInSheetKey.self] }
        set { self[TVInSheetKey.self] = newValue }
    }
    var tvToolbarItem: Bool {
        get { self[TVToolbarItemKey.self] }
        set { self[TVToolbarItemKey.self] = newValue }
    }
    var tvInButtonPlatter: Bool {
        get { self[TVInButtonPlatterKey.self] }
        set { self[TVInButtonPlatterKey.self] = newValue }
    }
    var tvOnFocusedPlatter: Bool {
        get { self[TVOnFocusedPlatterKey.self] }
        set { self[TVOnFocusedPlatterKey.self] = newValue }
    }
    /// The focused element on tvOS (focus effects are not disabled).
    var tvShowsFocus: Bool { renderPlatform == .tvOS && isFocused && !focusEffectDisabled }
}

extension View {
    /// Content drawn on a focused white platter: resolved in the light appearance so labels, secondary
    /// labels and symbols take their dark colors (as tvOS does), whatever the screen's appearance.
    func tvOnWhitePlatter(_ on: Bool = true) -> some View {
        env { if on { $0.colorScheme = .light; $0.tvOnFocusedPlatter = true } }
    }
}

// MARK: - Lift node

/// What sits behind a lifted element.
enum TVPlatter {
    case none
    case color(RGBA)
    case glass(GlassAppearance)
}

struct TVLiftStyle {
    var scale: CGFloat = TVMetrics.liftScale
    /// Points the platter grows by on every side while lifted (tvOS 26 focus).
    var growth: CGFloat = 0
    /// When set, the scale is chosen so that the longer side grows by this many points (tvOS 26 cards).
    var scaleGrowth: CGFloat?
    var shadow = true
    var shadowOpacity = TVMetrics.liftShadowOpacity
    var shadowRadius = TVMetrics.liftShadowRadius
    var shadowY = TVMetrics.liftShadowY
    /// The shadow is this much narrower than the platter on each side.
    var shadowInset: CGFloat = 0
    var platter: TVPlatter = .none
    /// Platter shape: corner radius (nil: capsule), and how far it extends beyond the content.
    var cornerRadius: CGFloat? = TVMetrics.buttonCornerRadius
    var outset = EdgeInsets()
    var specular = false
    /// Width of a white rim drawn inside the platter's edge while lifted (tvOS 26 `.plain`).
    var rim: CGFloat = 0
    /// The shadow and highlight follow the largest image or shape inside (a poster), not the bounds.
    var followsArtwork = false
    /// Scale and shadow are drawn (focused); when false only the platter is drawn (unfocused).
    var lifted = true
}

/// Draws its child, optionally over a platter, scaled about its centre with a drop shadow and a
/// specular highlight. Layout is untouched: the scale is drawn only.
final class TVLiftNode: WrapperNode {
    let style: TVLiftStyle

    init(child: Node, style: TVLiftStyle) {
        self.style = style
        super.init(child: child)
    }

    private func platterRect(_ bounds: CGRect) -> CGRect {
        let g = style.lifted ? style.growth : 0
        return CGRect(x: bounds.minX - style.outset.leading - g, y: bounds.minY - style.outset.top - g,
                      width: bounds.width + style.outset.leading + style.outset.trailing + g * 2,
                      height: bounds.height + style.outset.top + style.outset.bottom + g * 2)
    }

    private func shape(_ rect: CGRect) -> Path {
        let radius = min(style.cornerRadius ?? rect.height / 2, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: radius, style: style.cornerRadius == nil ? .circular : .continuous)
    }

    /// The largest image or shape below this node, in this node's coordinates.
    private func artworkRect() -> CGRect? {
        var best: CGRect?
        func visit(_ node: Node, _ origin: CGPoint) {
            for child in node.children {
                let o = CGPoint(x: origin.x + child.frame.minX, y: origin.y + child.frame.minY)
                if child is ImageNode || child is ShapeNode {
                    let r = CGRect(origin: o, size: child.frame.size)
                    if r.width * r.height > (best.map { $0.width * $0.height } ?? 0) { best = r }
                }
                visit(child, o)
            }
        }
        visit(self, .zero)
        return best
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let plate = platterRect(bounds)
        let body = style.followsArtwork ? (artworkRect() ?? bounds) : plate
        p.save()
        let scale = style.scaleGrowth.map { 1 + $0 / max(1, bounds.width, bounds.height) } ?? style.scale
        if style.lifted && scale != 1 {
            let s = scale
            p.translate(bounds.midX, bounds.midY)
            p.scale(s, s)
            p.translate(-bounds.midX, -bounds.midY)
        }
        let hasPlatter: Bool
        if case .none = style.platter { hasPlatter = false } else { hasPlatter = true }
        if style.lifted && style.shadow {
            // The shadow follows what is drawn: the platter, or the artwork's own shape.
            let shadow = Painter.shadowFilter(color: RGBA(0, 0, 0, style.shadowOpacity), radius: style.shadowRadius,
                                              x: 0, y: style.shadowY, scale: p.scale)
            if hasPlatter {
                if style.shadowInset > 0 {
                    // The shadow alone, from a narrower shape (the platter covers the rest of it).
                    let moved = plate.insetBy(dx: style.shadowInset, dy: 0).offsetBy(dx: 0, dy: style.shadowY)
                    p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: style.shadowRadius, scale: p.scale)))
                    p.fill(shape(moved), with: .color(RGBA(0, 0, 0, style.shadowOpacity)), in: moved)
                    p.restore()
                } else {
                    p.saveLayer(.init(imageFilter: shadow))
                    p.fill(shape(plate), with: .color(.black), in: plate)
                    p.restore()
                }
                drawPlatter(p, plate)
                if style.rim > 0 {
                    let r = plate.insetBy(dx: style.rim / 2, dy: style.rim / 2)
                    p.stroke(shape(r), with: .color(RGBA(1, 1, 1, 1)), style: StrokeStyle(lineWidth: style.rim), in: r)
                }
                drawChildren(p)
            } else {
                p.saveLayer(.init(imageFilter: shadow))
                drawChildren(p)
                p.restore()
            }
        } else {
            drawPlatter(p, plate)
            drawChildren(p)
        }
        if style.lifted && style.specular {
            let path = style.followsArtwork ? Path(roundedRect: body, cornerRadius: min(TVMetrics.cardCornerRadius, body.height / 2), style: .continuous)
                                            : shape(plate)
            p.save()
            p.clip(path)
            let stops = [GradientStop(color: RGBA(1, 1, 1, TVMetrics.specularOpacity), location: 0),
                         GradientStop(color: RGBA(1, 1, 1, 0), location: 1)]
            p.fill(Path(body), with: _Paint(.radial(stops: stops, center: UnitPoint(x: 0.3, y: 0), startRadius: 0,
                                                    endRadius: max(body.width, body.height) * 0.75)), in: body)
            p.restore()
        }
        p.restore()
    }

    private func drawPlatter(_ p: Painter, _ rect: CGRect) {
        switch style.platter {
        case .none: break
        case .color(let c): p.fill(shape(rect), with: .color(c), in: rect)
        case .glass(let a):
            let radius = min(style.cornerRadius ?? rect.height / 2, min(rect.width, rect.height) / 2)
            p.fillGlass(.roundedRect(rect, radius: radius), appearance: a)
        }
    }
}

extension TVLiftStyle {
    /// A tvOS 26 platter while focused: white, grown by 4 pt, with the measured shadow; not scaled.
    mutating func useGlassFocus() {
        scale = 1
        growth = TVMetrics.glassFocusGrowth
        shadowOpacity = TVMetrics.glassShadowOpacity
        shadowRadius = TVMetrics.glassShadowRadius
        shadowY = TVMetrics.glassShadowY
        shadowInset = TVMetrics.glassShadowInset
    }
}

/// Wraps the content's nodes in a `TVLiftNode`.
struct TVLiftModifier: ViewModifier, NodeModifier {
    let style: TVLiftStyle
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { TVLiftNode(child: child, style: style) }
}

// MARK: - hoverEffect

struct HoverEffectModifier: ViewModifier, PrimitiveModifier {
    let effect: HoverEffect
    let isEnabled: Bool
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = content.nodes(ctx)
        // On tvOS the effect shows while the nearest focusable ancestor has focus.
        guard isEnabled, ctx.env.tvShowsFocus, ctx.env[HoverEffectDisabledKey.self] == false else {
            out.append(contentsOf: nodes)
            return
        }
        var style = TVLiftStyle()
        style.followsArtwork = true
        switch effect.kind {
        case .highlight:
            // Projection + specular highlight; a smaller lift than `.lift` (est.).
            style.scale = TVMetrics.smallLiftScale
            style.specular = true
            style.shadowOpacity = TVMetrics.liftShadowOpacity * 0.7
        case .lift, .automatic:
            style.specular = false
        }
        out.append(contentsOf: nodes.map { TVLiftNode(child: $0, style: style) })
    }
}

enum HoverEffectDisabledKey: EnvironmentKey { static let defaultValue = false }

// MARK: - Chrome highlight fallback

@MainActor
enum FocusEffect {
    /// Focus on system chrome the engine synthesizes and that has no tvOS look of its own is drawn over
    /// the finished frame as an outline. tvOS chrome (tab items, alert buttons, the search field) draws its
    /// own focused state, so this is only a fallback.
    static func drawChromeHighlight(_ p: Painter, rect: CGRect, scheme: ColorScheme) {
        let r = rect.insetBy(dx: -4, dy: -4)
        let radius = min(TVMetrics.buttonCornerRadius, r.height / 2)
        let path = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        p.stroke(path, with: .color(RGBA(1, 1, 1, 1)), style: StrokeStyle(lineWidth: 4), in: r)
        p.stroke(Path(roundedRect: r.insetBy(dx: -2.5, dy: -2.5), cornerRadius: radius + 2.5, style: .continuous),
                 with: .color(RGBA(0, 0, 0, 0.35)), style: StrokeStyle(lineWidth: 1), in: r)
    }
}
