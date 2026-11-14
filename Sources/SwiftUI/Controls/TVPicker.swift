// Picker on tvOS. The automatic style is a segmented control ("On tvOS, the default is a segmented
// control", PickerStyle.automatic documentation); inside a List it is drawn as a row showing the value,
// which opens the options (est.: "the default picker style may also take into account other factors —
// like whether the picker appears in a container view"). `.menu` and `.navigationLink` are rows with the
// value; `.inline` lists every option as a focusable row with a checkmark. `.wheel` and `.palette` do not
// exist on tvOS.

/// A tvOS 26 menu picker outside a list: the selected value on a bordered button platter.
struct _TVValueButton: View {
    let normal: [Node]
    let onPlatter: [Node]
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.focusEffectDisabled) private var effectDisabled
    @Environment(\.designLanguage) private var design
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let focused = isFocused && isEnabled && !effectDisabled
        return _TVFocusVariant(normal: normal, onPlatter: onPlatter)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? Color(SystemColor.label) : Color(SystemColor.secondaryLabel))
            .tvOnWhitePlatter(focused)
            .padding(.horizontal, TVMetrics.buttonHorizontalPadding)
            .frame(minHeight: TVMetrics.buttonHeight)
            .modifier(TVLiftModifier(style: .platter(focused: focused, design: design, scheme: scheme, cornerRadius: nil)))
    }
}

/// Shows one of two resolutions of the same option: the normal one, or the one resolved for a focused
/// white platter (dark colors), depending on focus.
struct _TVFocusVariant: View {
    let normal: [Node]
    let onPlatter: [Node]
    init(normal: Node, onPlatter: Node) { self.normal = [normal]; self.onPlatter = [onPlatter] }
    init(normal: [Node], onPlatter: [Node]) { self.normal = normal; self.onPlatter = onPlatter }
    @Environment(\.isFocused) private var isFocused
    @Environment(\.focusEffectDisabled) private var effectDisabled
    var body: some View { _NodesView(isFocused && !effectDisabled ? onPlatter : normal) }
}

extension Picker {
    func resolveTV(_ ctx: ResolveContext, into out: inout [Node]) {
        let env = ctx.env
        var kind = env.pickerKind
        if env[PickerPaletteKey.self] {
            ctx.runtime.warn("PickerStyle.palette is not available on tvOS: a real tvOS build fails to compile. Drawn as a segmented picker")
        }
        // tvOS 26: in a List the automatic picker is a segmented control with focusable segments; in a Form it is
        // a row showing the value (measured: tvOS 26.5).
        if !env[PickerKindExplicitKey.self] {
            kind = env.isInListRow && (!env.designLanguage.isGlass || env[TVInFormKey.self]) ? .navigationLink : .segmented
        }
        // tvOS 26 draws an inline picker outside a list as a segmented control (measured: tvOS 26.5).
        if kind == .inline && env.designLanguage.isGlass && !env.isInListRow { kind = .segmented }
        if kind == .wheel {
            ctx.runtime.warn("PickerStyle.wheel is not available on tvOS: a real tvOS build fails to compile. Drawn as a navigation-link row")
            kind = .navigationLink
        }
        let enabled = env.isEnabled
        let labelNodes = resolveNodes(label, ctx.child("label"))
        let labelOnPlatter = resolveNodes(label, ctx.child("label").with { $0.colorScheme = .light; $0.tvOnFocusedPlatter = true })
        let binding = selection
        func options(_ key: String, _ tweak: @escaping (inout EnvironmentValues) -> Void = { _ in }) -> [Node] {
            resolveNodes(content, ctx.child(key).with(tweak))
        }
        func onPlatter(_ e: inout EnvironmentValues) { e.colorScheme = .light; e.tvOnFocusedPlatter = true }
        func selector(_ nodes: [Node]) -> @MainActor (Int) -> Void {
            let tags = nodes.map { $0.traits[TagTraitKey.self] ?? $0.traits[IDTraitKey.self] }
            return { i in
                guard tags.indices.contains(i), let tag = tags[i], let value = tag.base as? SelectionValue else {
                    Runtime.current?.warn("Picker option \(i + 1) has no tag matching the selection type; select does nothing")
                    return
                }
                binding.wrappedValue = value
                Runtime.current?.needsAnotherPass = true
            }
        }
        let labelText = axText(labelNodes)

        switch kind {
        case .segmented, .wheel:
            let normal = options("seg")
            let dark = options("seg", onPlatter)
            let sel = selectedIndex(normal)
            let view = TVSegmentedBody(nodes: normal, onPlatter: dark, selected: sel, select: selector(normal))
                .axInfo { $0.role = "segmentedControl"; $0.children = .contain; $0.label = labelText.isEmpty ? nil : labelText }
                .opacity(enabled ? 1 : 0.4)
            resolveView(view, ctx.child("picker"), into: &out)
        case .inline:
            let normal = options("inline")
            let dark = options("inline", onPlatter)
            let sel = selectedIndex(normal)
            let select = selector(normal)
            let view = VStack(spacing: 0) {
                ForEach(Array(normal.indices), id: \.self) { i in
                    TVInlineOption(node: AnyView(_TVFocusVariant(normal: normal[i], onPlatter: dark[i])), isSelected: i == sel)
                        .axInfo {
                            $0.isElement = true
                            $0.addTraits = i == sel ? [.button, .selected] : [.button]
                            $0.children = .combine
                        }
                        .focusElement(role: "option", activate: { select(i) })
                }
            }
            .opacity(enabled ? 1 : 0.4)
            resolveView(view, ctx.child("picker"), into: &out)
        case .menu where env.designLanguage.isGlass && !env.isInListRow:
            // tvOS 26: a menu picker outside a list is a bordered button showing the value (measured: tvOS 26.5).
            let normal = options("value")
            let dark = options("value", onPlatter)
            let sel = selectedIndex(normal)
            let valueText = sel.map { axText([normal[$0]]) }
            let view = _TVValueButton(normal: sel.map { [normal[$0]] } ?? [], onPlatter: sel.map { [dark[$0]] } ?? [])
                .axInfo {
                    $0.isElement = true
                    $0.role = "picker"
                    $0.label = labelText.isEmpty ? nil : labelText
                    $0.value = valueText
                    $0.addTraits = [.button, .hasPopup]
                    $0.children = .ignore
                    $0.isEnabled = enabled
                }
                .focusElement(role: "picker", activate: {
                    Runtime.current?.warn("select on a Picker would open its options; choosing an option is not simulated")
                })
            resolveView(view, ctx.child("picker"), into: &out)
        case .menu, .navigationLink:
            let secondary: (inout EnvironmentValues) -> Void = { $0.foregroundStyle = AnyShapeStyle(Color(SystemColor.secondaryLabel)) }
            let normal = options("value", secondary)
            let dark = options("value") { secondary(&$0); onPlatter(&$0) }
            let sel = selectedIndex(normal)
            let valueText = sel.map { axText([normal[$0]]) }
            let value = HStack(spacing: 14) {
                if let sel { _TVFocusVariant(normal: normal[sel], onPlatter: dark[sel]) }
                if kind == .menu {
                    UpDownChevron(color: AnyShapeStyle(Color(SystemColor.tertiaryLabel))).scaleEffect(1.8)
                } else {
                    _TVChevron()
                }
            }
            let view = _TVRowControl(label: AnyView(_TVFocusVariant(normal: labelNodes, onPlatter: labelOnPlatter)), trailing: AnyView(value))
                .opacity(enabled ? 1 : 0.4)
                .axInfo {
                    $0.isElement = true
                    $0.role = "picker"
                    $0.label = labelText.isEmpty ? nil : labelText
                    $0.value = valueText
                    $0.addTraits = kind == .menu ? [.button, .hasPopup] : [.button]
                    $0.children = .ignore
                    $0.isEnabled = enabled
                }
                .focusElement(role: "picker", activate: {
                    Runtime.current?.warn("select on a Picker would open its options; choosing an option is not simulated")
                })
            resolveView(view, ctx.child("picker"), into: &out)
        }
    }
}
