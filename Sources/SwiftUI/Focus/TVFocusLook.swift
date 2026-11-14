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
// Sources for the numbers are in docs/TVOS.md. "measured" values come from Apple's HIG; "est." are
// estimates from reference images and should be checked against a tvOS simulator.

enum TVMetrics {
    // MARK: Focus lift
    /// Scale of a focused button platter, card or lifted image (est.: HIG shows focused items "elevated";
    /// community measurements and SwiftUI samples use 1.05 to 1.1).
    static let liftScale: CGFloat = 1.1
    /// A focused list row grows only slightly (HIG Lists: "slightly increases in size"; amount est.).
    static let rowLiftScale: CGFloat = 1.03
    /// Tab bar items and segments grow a little when focused (est.).
    static let smallLiftScale: CGFloat = 1.06
    /// Drop shadow under a lifted element (est.).
    static let liftShadowRadius: CGFloat = 30
    static let liftShadowY: CGFloat = 18
    static let liftShadowOpacity: Double = 0.35
    /// Specular highlight on lifted cards and images: brightest at the top (est.).
    static let specularOpacity: Double = 0.28

    // MARK: Buttons
    /// Height of a regular bordered button (measured from the tvOS 26 media player image in the HIG
    /// Materials page: 44 px at 1280 px wide = 66 pt).
    static let buttonHeight: CGFloat = 66
    static let buttonHorizontalPadding: CGFloat = 40      // est. (HIG images: 45 to 52 pt incl. a minimum width)
    static let buttonIconSpacing: CGFloat = 14            // est.
    /// tvOS 18 bordered buttons are rounded rectangles (est. radius); tvOS 26 buttons are capsules (HIG images).
    static let buttonCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12             // est.

    static func buttonHeight(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 44
        case .small: return 54
        case .regular: return buttonHeight
        case .large: return 80
        case .extraLarge: return 92
        }
    }
    static func buttonPadding(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 22
        case .small: return 30
        case .regular: return buttonHorizontalPadding
        case .large: return 48
        case .extraLarge: return 56
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

    // MARK: Lists
    static let rowMinHeight: CGFloat = 70                 // est.
    static let rowHorizontalInset: CGFloat = 30           // est.
    static let rowVerticalInset: CGFloat = 16             // est.
    static let rowSpacing: CGFloat = 6                    // est.
    static let rowCornerRadius: CGFloat = 12              // est.
    static let sectionSpacing: CGFloat = 40               // est.
    static let headerBottomGap: CGFloat = 14              // est.
    static let chevronSize = CGSize(width: 12, height: 22) // est.
    static let headerFontSize: CGFloat = 29               // est. (body size, semibold, secondary color)
    static let footerFontSize: CGFloat = 25               // est. (caption 1)

    // MARK: Navigation
    /// Title row at the top of a NavigationStack (est.).
    static let navigationTitleHeight: CGFloat = 110
    static let toolbarItemSpacing: CGFloat = 24           // est.

    // MARK: Search and text fields
    static let fieldHeight: CGFloat = 66                  // est.
    static let fieldCornerRadius: CGFloat = 12            // est.
    static let searchFieldHeight: CGFloat = 88            // est.

    // MARK: Alerts
    static let alertButtonWidth: CGFloat = 560            // est. (tvOS 18 full-screen alert)
    static let alertButtonSpacing: CGFloat = 20           // est.
    /// tvOS 26 alert card (measured from the HIG Alerts image: 385 x 178 px at 1280 px = 578 x 267 pt).
    static let glassAlertWidth: CGFloat = 578
    static let glassAlertCornerRadius: CGFloat = 52       // est. from the same image
    static let glassAlertPadding: CGFloat = 48            // measured approx. (33 px)
    static let glassAlertButtonHeight: CGFloat = 72       // measured approx. (48 px)
    static let glassAlertButtonGap: CGFloat = 21          // measured approx. (14 px)
    static let glassAlertButtonInset: CGFloat = 28        // measured approx. (19 px)

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
    /// Unfocused Liquid Glass control (tvOS 26/27): the system glass, tinted grey so it reads on light
    /// backgrounds (HIG Alerts image: the unfocused button is darker than the card it sits on; est.).
    @MainActor static func glass(_ scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
        var a = GlassAppearance.system(.regular, scheme: scheme, design: design)
        a.tint = scheme == .dark ? RGBA(1, 1, 1, 0.14) : RGBA(0.42, 0.42, 0.45, 0.22)
        return a
    }
    static func dim(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(0, 0, 0, 0.7) : RGBA(0.94, 0.94, 0.95, 0.75)
    }
}

/// Environment the tvOS controls set for their content.
enum TVInListRowKey: EnvironmentKey { static let defaultValue = false }
/// True for content resolved on a focused white platter: label colors become the dark ones.
enum TVOnFocusedPlatterKey: EnvironmentKey { static let defaultValue = false }
/// `.hoverEffect(_:)` written on a view.
enum TVHoverEffectKey: EnvironmentKey { static let defaultValue: HoverEffect? = nil }

extension EnvironmentValues {
    var isTV: Bool { renderPlatform == .tvOS }
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
    /// White with a glassy rim (a focused tvOS 26 control).
    case focusedGlass
}

struct TVLiftStyle {
    var scale: CGFloat = TVMetrics.liftScale
    var shadow = true
    var shadowOpacity = TVMetrics.liftShadowOpacity
    var platter: TVPlatter = .none
    /// Platter shape: corner radius (nil: capsule), and how far it extends beyond the content.
    var cornerRadius: CGFloat? = TVMetrics.buttonCornerRadius
    var outset = EdgeInsets()
    var specular = false
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
        CGRect(x: bounds.minX - style.outset.leading, y: bounds.minY - style.outset.top,
               width: bounds.width + style.outset.leading + style.outset.trailing,
               height: bounds.height + style.outset.top + style.outset.bottom)
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
        if style.lifted {
            let s = style.scale
            p.translate(bounds.midX, bounds.midY)
            p.scale(s, s)
            p.translate(-bounds.midX, -bounds.midY)
        }
        let hasPlatter: Bool
        if case .none = style.platter { hasPlatter = false } else { hasPlatter = true }
        if style.lifted && style.shadow {
            // The shadow follows what is drawn: the platter, or the artwork's own shape.
            let shadow = Painter.shadowFilter(color: RGBA(0, 0, 0, style.shadowOpacity), radius: TVMetrics.liftShadowRadius,
                                              x: 0, y: TVMetrics.liftShadowY, scale: p.scale)
            if hasPlatter {
                p.saveLayer(.init(imageFilter: shadow))
                p.fill(shape(plate), with: .color(.black), in: plate)
                p.restore()
                drawPlatter(p, plate)
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
        case .focusedGlass:
            let path = shape(rect)
            p.fill(path, with: .color(RGBA(1, 1, 1, 0.96)), in: rect)
            // Liquid Glass rim: a bright top edge fading down (est.).
            p.save()
            p.clip(path)
            let stops = [GradientStop(color: RGBA(1, 1, 1, 0), location: 0.6), GradientStop(color: RGBA(0.86, 0.87, 0.9, 1), location: 1)]
            p.fill(Path(rect), with: _Paint(.linear(stops: stops, start: .top, end: .bottom)), in: rect)
            p.restore()
            p.stroke(path, with: .color(RGBA(1, 1, 1, 0.9)), style: StrokeStyle(lineWidth: 1.5), in: rect)
        }
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
