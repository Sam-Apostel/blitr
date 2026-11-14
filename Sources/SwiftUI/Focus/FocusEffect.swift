// The default focus effect: the one place that draws "this control has focus" on tvOS.
//
// Deliberately small and isolated so it can be replaced when tvOS controls get their own focused
// styles (those should read `@Environment(\.isFocused)`, which `FocusElementModifier` sets for the
// focused element, and call `.focusEffectDisabled()` to opt out of this one).
//
// Look: the control is scaled up slightly around its centre over a rounded platter with a soft shadow
// (white in light mode, a translucent light platter in dark mode so white labels stay readable).

@MainActor
enum FocusEffect {
    static let scale: CGFloat = 1.06
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = 10

    static func platterColor(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(1, 1, 1, 0.28) : RGBA(1, 1, 1, 1)
    }

    /// Wraps the nodes of the focused element (applied at resolve time, tvOS only).
    static func wrap(_ nodes: [Node], _ env: EnvironmentValues) -> [Node] {
        nodes.map { FocusEffectNode(child: $0, platter: platterColor(env.colorScheme)) }
    }

    /// Focus on system chrome the engine synthesizes (tab bar items, alert buttons, the search field)
    /// has no view to wrap; it is drawn over the finished frame instead.
    static func drawChromeHighlight(_ p: Painter, rect: CGRect, scheme: ColorScheme) {
        let r = rect.insetBy(dx: -4, dy: -4)
        let path = Path(roundedRect: r, cornerRadius: min(cornerRadius, r.height / 2), style: .continuous)
        p.fill(path, with: .color(RGBA(1, 1, 1, scheme == .dark ? 0.22 : 0.35)), in: r)
        p.stroke(path, with: .color(RGBA(1, 1, 1, 1)), style: StrokeStyle(lineWidth: 4), in: r)
        p.stroke(Path(roundedRect: r.insetBy(dx: -2.5, dy: -2.5), cornerRadius: min(cornerRadius, r.height / 2) + 2.5, style: .continuous),
                 with: .color(RGBA(0, 0, 0, 0.35)), style: StrokeStyle(lineWidth: 1), in: r)
    }
}

final class FocusEffectNode: WrapperNode {
    let platter: RGBA

    init(child: Node, platter: RGBA) {
        self.platter = platter
        super.init(child: child)
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let s = FocusEffect.scale
        p.save()
        p.translate(bounds.midX, bounds.midY)
        p.scale(s, s)
        p.translate(-bounds.midX, -bounds.midY)
        // A small control (a text button) gets a platter with some room around its label; a large one
        // (a poster) is lifted as it is, the platter hidden behind it.
        let pad: CGFloat = min(bounds.width, bounds.height) < 120 ? 14 : 0
        let plate = bounds.insetBy(dx: -pad * 1.4, dy: -pad * 0.7)
        let radius = min(FocusEffect.cornerRadius, min(plate.width, plate.height) / 2)
        let path = Path(roundedRect: plate, cornerRadius: radius, style: .continuous)
        p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, 0.35), radius: FocusEffect.shadowRadius,
                                                            x: 0, y: FocusEffect.shadowOffset, scale: p.scale)))
        p.fill(path, with: .color(platter), in: plate)
        p.restore()
        drawChildren(p)
        p.restore()
    }
}
