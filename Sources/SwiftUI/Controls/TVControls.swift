// tvOS looks of Toggle, Picker, text fields and other value controls. Sources in docs/TVOS.md.
//
// Controls that hold a value (Toggle, Picker, a NavigationLink row) are full-width rows on tvOS: label
// leading, value trailing. Inside a List the row draws the platter (Chrome/ListLayout.swift); elsewhere
// the control draws its own, white and lifted while it has focus.

extension TVLiftStyle {
    /// The platter of a tvOS control in its unfocused or focused state.
    @MainActor static func platter(focused: Bool, design: DesignLanguage, scheme: ColorScheme, cornerRadius: CGFloat?) -> TVLiftStyle {
        var style = TVLiftStyle()
        style.cornerRadius = cornerRadius
        style.lifted = focused
        if focused {
            style.platter = .color(design.isGlass ? TVColors.glassFocusedPlatter(scheme) : TVColors.focusedPlatter)
            if design.isGlass { style.useGlassFocus() }
        } else {
            style.platter = .color(design.isGlass ? TVColors.glassPlatter(scheme) : TVColors.platter(scheme))
        }
        return style
    }
}

/// Corner radius of a full-width tvOS control or list row: rounded rectangles on tvOS 18 (est.), capsules on
/// tvOS 26 (measured).
func tvRowCornerRadius(_ design: DesignLanguage) -> CGFloat? { design.isGlass ? nil : TVMetrics.rowCornerRadius }

/// A full-width control row: the label leading, `trailing` (a value, a chevron) at the trailing edge.
struct _TVRowControl: View {
    let label: AnyView
    let trailing: AnyView?
    /// One of several focusable rows inside a single List row (inline picker options): draws its own
    /// platter only while focused.
    var standalone = false

    @Environment(\.isInListRow) private var inRow
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let focused = isFocused && isEnabled && !effectDisabled
        let row = HStack(spacing: 16) {
            label.lineLimit(1)
            Spacer(minLength: 16)
            if let trailing { trailing }
        }
        // tvOS 26 keeps a disabled control's label in the primary color (measured: tvOS 26.5 simulator, a disabled
        // Toggle outside a list looks like an enabled one).
        .foregroundStyle(isEnabled || design.isGlass ? Color(SystemColor.label) : Color(SystemColor.tertiaryLabel))
        .tvOnWhitePlatter(focused)
        if inRow && !standalone { return AnyView(row) }
        if standalone {
            var style = TVLiftStyle.platter(focused: focused, design: design, scheme: scheme, cornerRadius: tvRowCornerRadius(design))
            if !design.isGlass { style.scale = TVMetrics.rowLiftScale }
            if !focused { style.platter = .none }
            return AnyView(row
                .padding(.horizontal, TVMetrics.rowHorizontalInset)
                .frame(minHeight: TVMetrics.rowMinHeight)
                .frame(maxWidth: .infinity)
                .modifier(TVLiftModifier(style: style)))
        }
        // Outside a list the label sits as far in as a button's (measured: tvOS 26.5).
        return AnyView(row
            .padding(.horizontal, TVMetrics.buttonHorizontalPadding)
            .frame(minHeight: TVMetrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .modifier(TVLiftModifier(style: .platter(focused: focused, design: design, scheme: scheme, cornerRadius: tvRowCornerRadius(design)))))
    }
}

/// The trailing value of a row: secondary label color.
struct _TVValue: View {
    let content: AnyView
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isInListRow) private var inRow
    var body: some View {
        let glass = inRow ? TVColors.rowValue(scheme) : TVColors.controlValue(scheme)
        return content.foregroundStyle(design.isGlass ? Color(glass) : Color(SystemColor.secondaryLabel))
    }
}

/// The disclosure chevron of a row that opens something.
struct _TVChevron: View {
    var body: some View {
        Chevron(width: TVMetrics.chevronSize.width, height: TVMetrics.chevronSize.height, weight: 3,
                color: AnyShapeStyle(Color(SystemColor.tertiaryLabel)))
    }
}

// MARK: - Toggle

/// tvOS toggle. The automatic style "behaves like a button ... takes as much horizontal space as its parent
/// offers, and displays both the toggle's label and a text field that indicates the toggle's state"
/// (ToggleStyle.automatic documentation). `.switch` draws a switch instead of the text (est. look).
struct _TVToggle: View {
    let label: AnyView
    let isOn: Bool
    let showsSwitch: Bool
    @Environment(\.designLanguage) private var design

    var body: some View {
        // tvOS 26 draws `.switch` like the automatic style, with the On/Off text (measured).
        let value: AnyView = showsSwitch && !design.isGlass
            ? AnyView(TVSwitch(isOn: isOn))
            : AnyView(_TVValue(content: AnyView(Text(isOn ? "On" : "Off"))))
        return _TVRowControl(label: label, trailing: value)
    }
}

struct TVSwitch: View {
    let isOn: Bool
    @Environment(\.accentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        let size = TVMetrics.switchSize
        let knob = size.height - 6
        return ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? (accent ?? Color(SystemColor.green)) : Color(SystemColor.secondaryFill))
            Circle().fill(Color.white).frame(width: knob, height: knob).knobShadow().padding(3)
        }
        .frame(width: size.width, height: size.height)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Text fields

/// tvOS text field: a rounded platter with the text or the placeholder; focused it turns white and lifts.
/// Selecting it opens the full-screen keyboard, which is not drawn.
struct _TVFieldBody: View {
    let text: String
    let placeholder: AnyView?
    var secure = false

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme
    @Environment(\.textFieldBordered) private var bordered

    var body: some View {
        if bordered { Runtime.current?.warn(".textFieldStyle(.roundedBorder) is not available on tvOS: a real tvOS build fails to compile") }
        let focused = isFocused && isEnabled && !effectDisabled
        // tvOS 26: the text is headline size, secure text large dots (measured approx.).
        let shown = secure ? String(repeating: design.isGlass ? "\u{25CF}" : "\u{2022}", count: text.count) : text
        let content = Group {
            if text.isEmpty {
                if let placeholder { placeholder.foregroundStyle(Color(SystemColor.placeholderText)) }
            } else {
                Text(verbatim: shown).foregroundStyle(Color(SystemColor.label))
                    .font(design.isGlass ? (secure ? .system(size: 26) : .headline) : nil)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tvOnWhitePlatter(focused)
        var style = TVLiftStyle.platter(focused: focused, design: design, scheme: scheme,
                                        cornerRadius: design.isGlass ? nil : TVMetrics.fieldCornerRadius)
        if design.isGlass && !focused { style.platter = .color(TVColors.glassField(scheme)) }
        return content
            .padding(.horizontal, design.isGlass ? TVMetrics.buttonHorizontalPadding : 24)
            .frame(minHeight: design.isGlass ? TVMetrics.fieldHeight : TVMetrics.buttonHeight)
            .opacity(isEnabled ? 1 : 0.5)
            .modifier(TVLiftModifier(style: style))
    }
}

// MARK: - Picker

/// tvOS segmented control: segments on a translucent track; the focused segment is white and lifted (focus
/// selects a segment on tvOS, HIG Segmented controls), the selected one stays marked when focus leaves.
struct TVSegmentedBody: View {
    let nodes: [Node]
    let onPlatter: [Node]
    let selected: Int?
    let select: @MainActor (Int) -> Void
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let radius: CGFloat? = design.isGlass ? nil : TVMetrics.buttonCornerRadius
        if design.isGlass { return AnyView(glassBody) }
        return AnyView(HStack(spacing: 4) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                TVSegment(node: pair.element, onPlatter: onPlatter[pair.offset], isSelected: pair.offset == selected, cornerRadius: radius)
                    .axInfo {
                        $0.isElement = true
                        $0.addTraits = pair.offset == selected ? [.button, .selected] : [.button]
                        $0.children = .combine
                    }
                    .focusElement(role: "segment", activate: { [select] in select(pair.offset) })
            }
        }
        .padding(4)
        .modifier(TVLiftModifier(style: { var s = TVLiftStyle.platter(focused: false, design: design, scheme: scheme, cornerRadius: radius.map { $0 + 4 }); s.lifted = false; return s }())))
    }

    /// tvOS 26 (measured: tvOS 26.5): segments of equal width across the width offered, 84 pt high, on a light
    /// glass track; the selected segment is a darker pill, and while the control has focus the focused segment
    /// is a white lifted pill.
    private var glassBody: some View {
        HStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                TVGlassSegment(node: pair.element, onPlatter: onPlatter[pair.offset], isSelected: pair.offset == selected)
                    .axInfo {
                        $0.isElement = true
                        $0.addTraits = pair.offset == selected ? [.button, .selected] : [.button]
                        $0.children = .combine
                    }
                    .focusElement(role: "segment", activate: { [select] in select(pair.offset) })
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(TVLiftModifier(style: { var s = TVLiftStyle(); s.cornerRadius = nil; s.lifted = false
                                          s.platter = .color(TVColors.glassSegmentTrack(scheme)); return s }()))
    }
}

extension TVMetrics {
    /// tvOS 26 segmented control: 84 pt high, the segments share the whole track and their pills sit 9.5 pt
    /// inside them (measured: tvOS 26.5 simulator, segments 253 x 84 at 160, 413, 666; the selected pill 422.5 to
    /// 656.5 by 783.5 to 848.5).
    static let segmentedHeight: CGFloat = 84
    static let segmentInset: CGFloat = 9.5
}

struct TVGlassSegment: View {
    let node: Node
    let onPlatter: Node
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let focused = isFocused && !effectDisabled
        var style = TVLiftStyle()
        style.cornerRadius = nil
        style.lifted = focused
        let inset = TVMetrics.segmentInset
        style.outset = EdgeInsets(top: -inset, leading: -inset, bottom: -inset, trailing: -inset)
        if focused { style.platter = .color(TVColors.glassFocusedSegment(scheme)); style.useGlassFocus(); style.growth = 0 }
        else if isSelected { style.platter = .color(TVColors.glassSelectedSegment(scheme)) }
        else { style.platter = .none }
        return _NodeView(focused ? onPlatter : node)
            .lineLimit(1)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: TVMetrics.segmentedHeight)
            .modifier(TVLiftModifier(style: style))
    }
}

struct TVSegment: View {
    let node: Node
    let onPlatter: Node
    let isSelected: Bool
    let cornerRadius: CGFloat?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.designLanguage) private var design

    var body: some View {
        let focused = isFocused && !effectDisabled
        var style = TVLiftStyle()
        style.cornerRadius = cornerRadius
        style.lifted = focused
        style.scale = TVMetrics.smallLiftScale
        if focused { style.platter = .color(design.isGlass ? TVColors.glassFocusedPlatter(scheme) : TVColors.focusedPlatter) }
        else if isSelected { style.platter = .color(TVColors.selectedTab(scheme)) }
        else { style.platter = .none }
        return _NodeView(focused ? onPlatter : node)
            .lineLimit(1)
            .padding(.horizontal, 32)
            .frame(minWidth: 120, minHeight: TVMetrics.buttonHeight - 8)
            .modifier(TVLiftModifier(style: style))
    }
}

/// An inline picker option: a row with a checkmark on the selected option; each option is focusable.
struct TVInlineOption: View {
    let node: AnyView
    let isSelected: Bool
    var body: some View {
        _TVRowControl(label: node,
                      trailing: isSelected ? AnyView(Checkmark(color: AnyShapeStyle(Color(SystemColor.label))).scaleEffect(1.8)) : nil,
                      standalone: true)
    }
}
