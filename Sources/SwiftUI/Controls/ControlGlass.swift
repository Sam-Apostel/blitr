// Shared plumbing for the iOS 26 / 27 look of standard controls: the estimated measurements in one
// place (so they can be calibrated against reference captures) and the glass surface buttons sit on.
// Everything here applies only when `env.designLanguage.isGlass`; iOS 26 and 27 share the values.

enum ControlGlassMetrics {
    // Toggle: wider, flatter switch with a pill knob.
    static let toggleTrack = CGSize(width: 64, height: 28)       // est.
    static let toggleKnob = CGSize(width: 39, height: 24)        // est.
    static let toggleKnobInset: CGFloat = 2                      // est.

    // Slider: 6pt track, pill thumb.
    static let sliderTrackHeight: CGFloat = 6                    // est.
    static let sliderThumb = CGSize(width: 38, height: 24)       // est.
    static let sliderHeight: CGFloat = 28
    static let sliderTickSize: CGFloat = 3                       // est.
    static let sliderMaxTicks = 25

    // Stepper: same size as before, capsule ends.
    static let stepperSize = CGSize(width: 94, height: 32)

    // Segmented picker: capsule track, capsule selection.
    static let segmentedTrackHeight: CGFloat = 36                // est.
    static let segmentedInset: CGFloat = 3                       // est.
    static let segmentedFontSize: CGFloat = 14                   // est. (13 to 14)

    // Containers.
    static let groupBoxRadius: CGFloat = 20                      // est.

    // Prominent glass: opacity of the accent tint over the backdrop.
    static let prominentTintAlpha26: Double = 0.86
    static let prominentTintAlpha27: Double = 0.94               // iOS 27: better label contrast
    /// iOS 27 also darkens the accent a little under the white label.
    static let prominentDarken27: Double = 0.88
}

/// A Liquid Glass surface for button styles: neutral, or tinted with the accent color.
struct ControlGlassSurface: ViewModifier, NodeModifier {
    let prominent: Bool
    let borderShape: ButtonBorderShape
    var enabled = true

    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        let env = ctx.env
        var appearance = GlassAppearance.system(.regular, scheme: env.colorScheme, design: env.designLanguage)
        if prominent && enabled {
            let accent = (Color.accentColor).rgba(in: env)
            let refined = env.designLanguage == .liquidGlass27
            let k = refined ? ControlGlassMetrics.prominentDarken27 : 1
            appearance.tint = RGBA(accent.r * k, accent.g * k, accent.b * k,
                                   (refined ? ControlGlassMetrics.prominentTintAlpha27 : ControlGlassMetrics.prominentTintAlpha26) * accent.a)
        }
        let shape = borderShape
        return GlassNode(child: child, outline: { rect in
            switch shape.kind {
            case .circle:
                let side = min(rect.width, rect.height)
                return .roundedRect(CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), radius: side / 2)
            case .rounded(let r?): return .roundedRect(rect, radius: r)
            case .rounded(nil): return .roundedRect(rect, radius: 8)
            case .capsule, .automatic: return .roundedRect(rect, radius: min(rect.width, rect.height) / 2)
            }
        }, appearance: appearance)
    }
}
