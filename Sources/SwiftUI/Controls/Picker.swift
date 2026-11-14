// Picker and its styles. The options are resolved to nodes, matched against the selection by
// their `.tag` (or ForEach id), and re-laid out according to the style.

public protocol PickerStyle {}
public struct DefaultPickerStyle: PickerStyle { public init() {} }
public struct MenuPickerStyle: PickerStyle { public init() {} }
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
public struct InlinePickerStyle: PickerStyle { public init() {} }
public struct WheelPickerStyle: PickerStyle { public init() {} }
public struct NavigationLinkPickerStyle: PickerStyle { public init() {} }
public struct PalettePickerStyle: PickerStyle { public init() {} }

extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { DefaultPickerStyle() } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { MenuPickerStyle() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { InlinePickerStyle() } }
extension PickerStyle where Self == WheelPickerStyle { public static var wheel: WheelPickerStyle { WheelPickerStyle() } }
extension PickerStyle where Self == NavigationLinkPickerStyle { public static var navigationLink: NavigationLinkPickerStyle { NavigationLinkPickerStyle() } }
extension PickerStyle where Self == PalettePickerStyle { public static var palette: PalettePickerStyle { PalettePickerStyle() } }

enum PickerKind { case menu, segmented, inline, wheel, navigationLink }
enum PickerKindKey: EnvironmentKey { static let defaultValue = PickerKind.menu }
extension EnvironmentValues {
    var pickerKind: PickerKind {
        get { self[PickerKindKey.self] }
        set { self[PickerKindKey.self] = newValue }
    }
}

extension View {
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        env {
            switch style {
            case is SegmentedPickerStyle, is PalettePickerStyle: $0.pickerKind = .segmented
            case is InlinePickerStyle: $0.pickerKind = .inline
            case is WheelPickerStyle: $0.pickerKind = .wheel
            case is NavigationLinkPickerStyle: $0.pickerKind = .navigationLink
            default: $0.pickerKind = .menu
            }
        }
    }
}

public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let selection: Binding<SelectionValue>
    let content: Content
    let label: Label

    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.selection = selection
        self.content = content()
        self.label = label()
    }
    public init(selection: Binding<SelectionValue>, label: Label, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
        self.label = label
    }

    private func selectedIndex(_ nodes: [Node]) -> Int? {
        let current = selection.wrappedValue
        return nodes.firstIndex { node in
            guard let tag = node.traits[TagTraitKey.self] ?? node.traits[IDTraitKey.self] else { return false }
            if let v = tag.base as? SelectionValue { return v == current }
            return false
        }
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let kind = ctx.env.pickerKind
        let enabled = ctx.env.isEnabled
        let labelNodes = resolveNodes(label, ctx.child("label"))
        let labelView = _NodesView(labelNodes)

        func options(_ tweak: @escaping (inout EnvironmentValues) -> Void, key: String) -> [Node] {
            resolveNodes(content, ctx.child(key).with(tweak))
        }

        let view: AnyView
        var valueText: String?
        switch kind {
        case .menu:
            let nodes = options({ $0.foregroundStyle = AnyShapeStyle(Color.accentColor) }, key: "menu")
            let selected = selectedIndex(nodes).map { nodes[$0] }
            valueText = selected.map { axText([$0]) }
            view = AnyView(HStack(spacing: 8) {
                if !labelNodes.isEmpty { labelView }
                HStack(spacing: 5) {
                    if let selected { _NodeView(selected) }
                    UpDownChevron(color: AnyShapeStyle(Color.accentColor))
                }
            })
        case .navigationLink:
            let nodes = options({ $0.foregroundStyle = AnyShapeStyle(Color(SystemColor.secondaryLabel)) }, key: "nav")
            let selected = selectedIndex(nodes).map { nodes[$0] }
            valueText = selected.map { axText([$0]) }
            view = AnyView(HStack(spacing: 8) {
                labelView
                Spacer(minLength: 8)
                if let selected { _NodeView(selected) }
                Chevron(width: 7, height: 12, weight: 2, color: AnyShapeStyle(Color(SystemColor.tertiaryLabel)))
            })
        case .segmented:
            let glass = ctx.env.designLanguage.isGlass
            let size = glass ? ControlGlassMetrics.segmentedFontSize : 13
            let normal = options({ $0.font = .system(size: size) }, key: "seg")
            let bold = options({ $0.font = .system(size: size, weight: glass ? .semibold : .medium) }, key: "seg")
            let sel = selectedIndex(normal)
            view = AnyView(SegmentedBody(nodes: normal, selectedNode: sel.map { bold[$0] }, selected: sel))
        case .inline:
            let nodes = options({ _ in }, key: "inline")
            let sel = selectedIndex(nodes)
            view = AnyView(VStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                    VStack(spacing: 0) {
                        HStack {
                            _NodeView(pair.element)
                            Spacer(minLength: 8)
                            if pair.offset == sel { Checkmark() }
                        }
                        .padding(.vertical, 11)
                        .axInfo {
                            $0.isElement = true
                            $0.addTraits = pair.offset == sel ? [.button, .selected] : [.button]
                            $0.children = .combine
                            $0.isTapTarget = true
                        }
                        if pair.offset < nodes.count - 1 { Divider() }
                    }
                }
            })
        case .wheel:
            let nodes = options({ $0.font = .system(size: 21) }, key: "wheel")
            let sel = selectedIndex(nodes) ?? 0
            valueText = nodes.indices.contains(sel) ? axText([nodes[sel]]) : nil
            view = AnyView(WheelBody(nodes: nodes, selected: sel))
        }
        let result = view.opacity(enabled ? 1 : 0.4)
        let labelText = axText(labelNodes)
        let info = AccessibilityInfo {
            $0.isElement = true
            $0.role = "picker"
            $0.label = labelText.isEmpty ? nil : labelText
            $0.isEnabled = enabled
            switch kind {
            case .menu:
                $0.addTraits = [.button, .hasPopup]; $0.children = .ignore; $0.value = valueText
                $0.isTapTarget = true; $0.systemHitSlop = true
            case .navigationLink:
                $0.addTraits = [.button]; $0.children = .ignore; $0.value = valueText; $0.isTapTarget = true
            case .wheel:
                $0.addTraits = [.adjustable]; $0.children = .ignore; $0.value = valueText
                $0.isTapTarget = true; $0.systemHitSlop = true
            case .segmented:
                $0.role = "segmentedControl"; $0.children = .contain
            case .inline:
                $0.children = .contain
            }
        }
        resolveView(result.modifier(AXModifier(shared: true) { _ in info }), ctx.child("picker"), into: &out)
    }
}

struct SegmentedBody: View {
    let nodes: [Node]
    let selectedNode: Node?
    let selected: Int?
    @Environment(\.designLanguage) private var design

    var body: some View {
        design.isGlass ? AnyView(glassBody) : AnyView(flatBody)
    }

    /// iOS 26: capsule track, capsule selection inset 3pt.
    private var glassBody: some View {
        let m = ControlGlassMetrics.self
        let segmentHeight = m.segmentedTrackHeight - 2 * m.segmentedInset
        return HStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                let isSel = pair.offset == selected
                if pair.offset > 0 {
                    let hide = isSel || pair.offset - 1 == selected
                    Rectangle().fill(Color(SystemColor.gray3)).frame(width: 1, height: 14).opacity(hide ? 0 : 1)
                }
                Group {
                    if isSel, let selectedNode { _NodeView(selectedNode) } else { _NodeView(pair.element) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: segmentHeight)
                .axInfo {
                    $0.isElement = true
                    $0.addTraits = isSel ? [.button, .selected] : [.button]
                    $0.children = .combine
                    $0.isTapTarget = true
                    $0.systemHitSlop = true
                }
                .background {
                    if isSel {
                        Capsule()
                            .fill(Color(DynamicColor(0xFFFFFF, 0x636366)))
                            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)
                            .shadow(color: Color.black.opacity(0.04), radius: 0.5, x: 0, y: 0.5)
                    }
                }
            }
        }
        .padding(m.segmentedInset)
        .frame(maxWidth: .infinity)
        .background(Color(SystemColor.tertiaryFill), in: Capsule())
    }

    private var flatBody: some View {
        HStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { pair in
                let isSel = pair.offset == selected
                if pair.offset > 0 {
                    let hide = isSel || pair.offset - 1 == selected
                    Rectangle().fill(Color(SystemColor.gray3)).frame(width: 1, height: 14).opacity(hide ? 0 : 1)
                }
                Group {
                    if isSel, let selectedNode { _NodeView(selectedNode) } else { _NodeView(pair.element) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .axInfo {
                    $0.isElement = true
                    $0.addTraits = isSel ? [.button, .selected] : [.button]
                    $0.children = .combine
                    $0.isTapTarget = true
                    $0.systemHitSlop = true
                }
                .background {
                    if isSel {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(DynamicColor(0xFFFFFF, 0x636366)))
                            .shadow(color: Color.black.opacity(0.10), radius: 2.5, x: 0, y: 2)
                            .shadow(color: Color.black.opacity(0.04), radius: 0.5, x: 0, y: 0.5)
                    }
                }
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(Color(SystemColor.tertiaryFill), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct WheelBody: View {
    let nodes: [Node]
    let selected: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(Color(SystemColor.tertiaryFill)).frame(height: 34)
            VStack(spacing: 0) {
                ForEach(-3..<4, id: \.self) { d in
                    let i = selected + d
                    Group {
                        if i >= 0 && i < nodes.count { _NodeView(nodes[i]) } else { Color.clear.frame(width: 1, height: 1) }
                    }
                    .frame(height: 32)
                    .opacity(d == 0 ? 1 : max(0.15, 0.6 - 0.15 * Double(abs(d) - 1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .clipped()
    }
}

extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(titleKey) }
    }
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(title) }
    }
}

extension Picker where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}
