// Shared plumbing for the iOS 26 / 27 look of standard controls: the estimated measurements in one
// place (so they can be calibrated against reference captures) and the glass surface buttons sit on.
// Everything here applies only when `env.designLanguage.isGlass`; iOS 26 and 27 share the values.

enum ControlGlassMetrics {
    // Toggle: wider, flatter switch with a pill knob and no knob shadow. measured: iOS 27.0
    // simulator (GlassControls): 63x28 track, 37x24 knob 2pt from the edges; the off track is
    // C5C5C7 on white and 464649 on black.
    static let toggleTrack = CGSize(width: 63, height: 28)
    static let toggleKnob = CGSize(width: 37, height: 24)
    static let toggleKnobInset: CGFloat = 2
    static let toggleOffTrack = DynamicColor(0xC5C5C7, 0x464649)
    /// iOS 27, in a sheet: the off track and the fills of date pills are stronger over the sheet's glass.
    /// measured: iOS 27.0 simulator (10_Agenda, form card 214 / 48): off track 139 / 98, date pills 184 / 76.
    static let sheetToggleOffTrack = DynamicColor(0x787880, 0x787880, alpha: 0.78, darkAlpha: 0.69)
    static let sheetPillFill = DynamicColor(0x767680, 0x767680, alpha: 0.31, darkAlpha: 0.4)
    /// The switch takes 61pt in layout; its track overhangs 2pt to the right (measured).
    static let toggleLayoutWidth: CGFloat = 61

    // Slider: 6pt track, pill thumb. measured: iOS 27.0 simulator (ControlsIndicators): 31pt
    // tall, 37x24 thumb kept inside the bounds, labels 8pt from the track, a faint thumb shadow
    // in light mode only. The track is translucent: E6E6E6 on white, 191919 on black and
    // 30355B over the dark blue of 09_MusicPlayer.
    static let sliderTrackHeight: CGFloat = 6
    static let sliderThumb = CGSize(width: 37, height: 24)
    static let sliderHeight: CGFloat = 31
    static let sliderTrack = DynamicColor(0x787880, 0x787880, alpha: 0.185, darkAlpha: 0.21)
    static let sliderLabelSpacing: CGFloat = 8
    static let sliderTickSize: CGFloat = 3                       // est.
    static let sliderMaxTicks = 25

    // Stepper: same size as before, capsule ends.
    static let stepperSize = CGSize(width: 94, height: 32)

    // Segmented picker: capsule track, capsule selection. measured: iOS 27.0 simulator
    // (ControlsInputs): 32pt track, selection inset 2pt, no separators and no selection shadow;
    // selection white / 5A5A5F.
    static let segmentedTrackHeight: CGFloat = 32
    static let segmentedInset: CGFloat = 2
    static let segmentedSelection = DynamicColor(0xFFFFFF, 0x5A5A5F)
    static let segmentedFontSize: CGFloat = 14                   // est. (13 to 14)

    // Containers.
    static let groupBoxRadius: CGFloat = 8                       // measured: iOS 27.0 simulator

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
