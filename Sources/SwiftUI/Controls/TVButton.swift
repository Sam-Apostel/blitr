// tvOS button styles: the bordered platter (the default), bordered prominent, plain, borderless, card,
// and the full-width row a button becomes inside a List. Each draws its own focused state from
// `isFocused`; see Focus/TVFocusLook.swift for the lift and docs/TVOS.md for the sources.
//
// tvOS 18 and earlier draw opaque platters; tvOS 26 and 27 (`DesignLanguage.isGlass`) draw Liquid Glass
// capsules that turn white when focused (HIG Materials: "buttons adopt Liquid Glass when they gain focus").

/// Raises a button on a card when focused (tvOS only).
public struct CardButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        _ButtonVisual(kind: .card, label: AnyView(configuration.label), role: configuration.role)
    }
}
extension PrimitiveButtonStyle where Self == CardButtonStyle {
    /// A button style that doesn't pad the content, and applies a motion effect when the button has focus (tvOS).
    public static var card: CardButtonStyle { CardButtonStyle() }
}

struct _TVButtonVisual: View {
    let kind: _ButtonVisual.Kind
    let label: AnyView
    let role: ButtonRole?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.controlSize) private var size
    @Environment(\.buttonBorderShape) private var borderShape
    @Environment(\.buttonSizing) private var sizing
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accentColor) private var explicitAccent
    @Environment(\.isInListRow) private var inRow
    @Environment(\.font) private var userFont
    @Environment(\.foregroundStyle) private var explicitForeground

    private var focused: Bool { isFocused && isEnabled && !effectDisabled }
    private var destructive: Bool { role == .destructive }

    var body: some View {
        switch kind {
        case .automatic, .bordered, .glass:
            if inRow && kind == .automatic { return AnyView(rowBody) }
            return AnyView(platterBody(prominent: false))
        case .prominent, .glassProminent:
            return AnyView(platterBody(prominent: true))
        case .borderless:
            if inRow { return AnyView(rowBody) }
            return AnyView(liftBody(specular: true))
        case .plain:
            return AnyView(liftBody(specular: false))
        case .card:
            return AnyView(cardBody)
        }
    }

    // MARK: Platter (bordered, bordered prominent)

    private var cornerRadius: CGFloat? {
        switch borderShape.kind {
        case .capsule, .circle: return nil
        case .rounded(let r?): return r
        case .rounded(nil): return TVMetrics.buttonCornerRadius
        case .automatic: return design.isGlass ? nil : TVMetrics.buttonCornerRadius
        }
    }

    private func platterBody(prominent: Bool) -> some View {
        let height = TVMetrics.buttonHeight(size)
        let accent = (explicitAccent ?? Color.accentColor)
        let disabledLabel = Color(SystemColor.tertiaryLabel)
        var content = label
        if let font = TVMetrics.buttonFont(size) { content = AnyView(content.font(userFont ?? font)) }
        content = AnyView(content.lineLimit(1))
        // tvOS 26 draws a prominent button like a bordered one (measured: grey platter, primary label).
        let accentPlatter = prominent && !design.isGlass

        // Label color: primary (or red) on the translucent platter; dark (or red) on the focused white one;
        // white on the accent platter of a prominent button.
        let foreground: Color
        if !isEnabled { foreground = design.isGlass ? Color(SystemColor.secondaryLabel) : disabledLabel }
        else if accentPlatter { foreground = .white }
        else if destructive { foreground = Color(SystemColor.red) }
        else if focused { foreground = Color(TVColors.focusedLabel) }
        else { foreground = Color(SystemColor.label) }
        // An explicit foreground style of the surroundings colors the label until the platter turns white.
        let keepsExplicit = explicitForeground != nil && !focused && !accentPlatter && !destructive && isEnabled
        let styledLabel = (keepsExplicit ? content : AnyView(content.foregroundStyle(foreground))).tvOnWhitePlatter(focused && !accentPlatter)

        let circle = borderShape.kind == .circle
        let padded: AnyView
        if circle {
            padded = AnyView(styledLabel.frame(width: height, height: height))
        } else {
            let p = styledLabel.padding(.horizontal, TVMetrics.buttonPadding(size)).frame(minHeight: height)
            padded = sizing.kind == .flexible ? AnyView(p.frame(maxWidth: .infinity)) : AnyView(p)
        }

        var style = TVLiftStyle()
        style.cornerRadius = cornerRadius
        style.lifted = focused
        let accentRGBA = accent.rgba(in: currentEnv)
        if accentPlatter {
            let fill = isEnabled ? (focused ? accentRGBA.mix(.white, 0.12) : accentRGBA) : TVColors.platter(scheme)
            style.platter = .color(fill)
        } else if focused {
            style.platter = design.isGlass ? .focusedGlass : .color(TVColors.focusedPlatter)
            if design.isGlass { style.useGlassFocus() }
        } else if design.isGlass {
            style.platter = .color(destructive && isEnabled ? TVColors.glassDestructivePlatter : TVColors.glassPlatter(scheme))
        } else {
            style.platter = .color(TVColors.platter(scheme))
        }
        return padded
            .opacity(isEnabled || design.isGlass ? 1 : 0.5)
            .modifier(TVLiftModifier(style: style))
    }

    private var currentEnv: EnvironmentValues {
        var e = EnvironmentValues()
        e.colorScheme = scheme
        if let explicitAccent { e.accentColor = explicitAccent }
        return e
    }

    // MARK: Plain and borderless: the label (its artwork) lifts

    private func liftBody(specular: Bool) -> some View {
        var style = TVLiftStyle()
        style.platter = .none
        style.followsArtwork = true
        style.specular = specular
        style.lifted = focused
        let tinted = destructive ? AnyView(label.foregroundStyle(Color(SystemColor.red))) : label
        return tinted
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(TVLiftModifier(style: style))
    }

    // MARK: Card

    private var cardBody: some View {
        let radius = cornerRadius ?? TVMetrics.cardCornerRadius
        var style = TVLiftStyle()
        style.cornerRadius = radius
        style.lifted = focused
        style.specular = true
        if design.isGlass {
            // measured: tvOS 26.5, a focused card grows its longer side by 40 pt; its platter is a light film.
            style.scaleGrowth = TVMetrics.glassCardLiftGrowth
            style.shadowOpacity = TVMetrics.glassShadowOpacity
            style.shadowRadius = TVMetrics.glassShadowRadius
            style.shadowY = TVMetrics.glassShadowY
            style.platter = .color(TVColors.glassCardPlatter(scheme))
        } else {
            style.platter = .color(focused ? TVColors.cardPlatter(scheme).opacity(1.6) : TVColors.cardPlatter(scheme))
        }
        return label
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(TVLiftModifier(style: style))
    }

    // MARK: A button in a List row: the row draws the platter (Chrome/ListLayout.swift)

    private var rowBody: some View {
        let foreground: Color = !isEnabled ? Color(SystemColor.tertiaryLabel)
            : destructive ? Color(SystemColor.red) : Color(SystemColor.label)
        return label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tvOnWhitePlatter(focused)
    }
}
