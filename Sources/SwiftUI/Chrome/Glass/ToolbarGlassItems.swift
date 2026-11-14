// Liquid Glass toolbar items: the environment bar items resolve in, how items are grouped onto
// shared glass capsules, and the nodes that draw those capsules (navigation bar and bottom bar).

// MARK: - Button look inside a glass bar

/// What a button in a glass bar reports to the bar, so the bar can choose its glass.
struct ToolbarGlassItemInfo {
    var role: ButtonRole?
    var isEnabled: Bool
}
enum ToolbarGlassItemTraitKey: TraitKey { typealias Value = ToolbarGlassItemInfo }

/// The default button look in a glass bar: monochrome label (the bar sets the accent to the label
/// color, so an explicit `.tint` still wins), white on prominent glass, and the role reported to the bar.
struct _ToolbarGlassButtonVisual: View {
    let label: AnyView
    let role: ButtonRole?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.foregroundStyle) private var explicitForeground

    var body: some View {
        let content: AnyView
        if !isEnabled {
            content = AnyView(label.foregroundStyle(Color(SystemColor.tertiaryLabel)))
        } else if role == .confirm {
            content = AnyView(label.foregroundStyle(Color.white).fontWeight(.semibold))
        } else if role == .destructive {
            content = AnyView(label.foregroundStyle(Color.red))
        } else if explicitForeground != nil {
            content = label
        } else {
            content = AnyView(label.foregroundStyle(Color.accentColor))
        }
        return content.trait(ToolbarGlassItemTraitKey.self, ToolbarGlassItemInfo(role: role, isEnabled: isEnabled))
    }
}

extension ButtonStyleBox {
    /// Installed by glass bars for their items; a `buttonStyle` on the item itself still overrides it.
    static let toolbarGlass = ButtonStyleBox { label, role, _ in AnyView(_ToolbarGlassButtonVisual(label: label, role: role)) }
}

extension LabelStyleBox {
    /// Bars show a `Label` as its icon.
    static let toolbarIconOnly = LabelStyleBox { _, icon in icon }
}

// MARK: - Role buttons without a label (iOS 26)

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// A button whose label comes from its role: close / cancel show an xmark, confirm a checkmark.
    public init(role: ButtonRole, action: @escaping @MainActor () -> Void) {
        let (title, symbol): (String, String)
        switch role {
        case .close: (title, symbol) = ("Close", "xmark")
        case .cancel: (title, symbol) = ("Cancel", "xmark")
        case .confirm: (title, symbol) = ("Done", "checkmark")
        default: (title, symbol) = ("Delete", "trash")
        }
        self.init(role: role, action: action) { SwiftUI.Label(title, systemImage: symbol) }
    }
}

// MARK: - Classifying items

enum ToolbarGlassItemKind {
    /// Glyph only: a 44pt cell (a circle on its own).
    case icon
    /// Has text: padded capsule.
    case text
    /// Anything else (shapes, controls, stacks of styled views): drawn as is, without glass.
    case custom
}

@MainActor
func toolbarGlassKind(of node: Node) -> ToolbarGlassItemKind {
    var hasText = false, plain = true
    func visit(_ n: Node) {
        switch n {
        case is TextNode: hasText = true
        case is ImageNode, is BackButtonNode, is EllipsisCircleNode, is SpacerNode, is EmptyNode: break
        default:
            if n.children.isEmpty { plain = false }
            for child in n.children { visit(child) }
        }
    }
    visit(node)
    if !plain { return .custom }
    return hasText ? .text : .icon
}

@MainActor
func toolbarGlassInfo(of node: Node) -> ToolbarGlassItemInfo? {
    if let info = node.traits[ToolbarGlassItemTraitKey.self] { return info }
    for child in node.children {
        if let info = toolbarGlassInfo(of: child) { return info }
    }
    return nil
}

// MARK: - Grouping

/// One element of a placement, in order, before items are grouped onto capsules.
enum ToolbarGlassToken {
    case item(Node, prominent: Bool, sharesBackground: Bool)
    case spacer(flexible: Bool)
    case searchSlot
}

/// The bar's items grouped into capsules, with flexible gaps and the search slot (bottom bar).
enum ToolbarGlassSlot {
    case group(ToolbarGlassGroupNode)
    case flexibleSpace
    case search
}

@MainActor
func makeToolbarGlassSlots(_ tokens: [ToolbarGlassToken], height: CGFloat, metrics: NavigationGlassMetrics,
                           neutral: GlassAppearance, prominent: GlassAppearance) -> [ToolbarGlassSlot] {
    var slots: [ToolbarGlassSlot] = []
    var run: [Node] = [], kinds: [ToolbarGlassItemKind] = []
    var runProminent = false
    func flush() {
        guard !run.isEmpty else { return }
        slots.append(.group(ToolbarGlassGroupNode(items: run, kinds: kinds, appearance: runProminent ? prominent : neutral,
                                                  height: height, metrics: metrics)))
        run = []; kinds = []
    }
    for token in tokens {
        switch token {
        case .spacer(let flexible):
            flush()
            if flexible { slots.append(.flexibleSpace) }
        case .searchSlot:
            flush()
            slots.append(.search)
        case .item(let node, let prominentPlacement, let shares):
            if node is SpacerNode { flush(); slots.append(.flexibleSpace); continue }
            let kind = toolbarGlassKind(of: node)
            let info = toolbarGlassInfo(of: node)
            let isProminent = (prominentPlacement || info?.role == .confirm) && info?.isEnabled != false
            if kind == .custom || !shares {
                flush()
                slots.append(.group(ToolbarGlassGroupNode(items: [node], kinds: [kind == .custom ? .custom : kind], appearance: nil,
                                                          height: height, metrics: metrics)))
                continue
            }
            // A prominent item gets its own capsule.
            if !run.isEmpty && (isProminent || runProminent) { flush() }
            runProminent = isProminent
            run.append(node)
            kinds.append(kind)
        }
    }
    flush()
    return slots
}

// MARK: - Nodes

/// Items sharing one glass capsule (or one item drawn without glass when `appearance` is nil).
final class ToolbarGlassGroupNode: Node {
    let kinds: [ToolbarGlassItemKind]
    let appearance: GlassAppearance?
    let height: CGFloat
    let metrics: NavigationGlassMetrics
    var items: [Node] { children }

    init(items: [Node], kinds: [ToolbarGlassItemKind], appearance: GlassAppearance?, height: CGFloat, metrics: NavigationGlassMetrics) {
        self.kinds = kinds
        self.appearance = appearance
        self.height = height
        self.metrics = metrics
        super.init(children: items)
    }

    private func natural(_ i: Int) -> CGSize { items[i].sizeThatFits(ProposedViewSize(width: nil, height: height)) }

    private func cellWidth(_ i: Int) -> CGFloat {
        let s = natural(i)
        switch kinds[i] {
        case .icon: return max(metrics.iconCellWidth, s.width + 12)
        case .text: return max(metrics.iconCellWidth, s.width + metrics.textItemPadding * 2)
        case .custom: return s.width
        }
    }

    /// Room at both ends so that icon cells of a taller capsule stay centred in its round ends.
    private var endPadding: CGFloat { appearance == nil ? 0 : max(0, (height - metrics.iconCellWidth) / 2) }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        guard appearance != nil else {
            let sizes = items.indices.map(natural)
            return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
        }
        let width = items.indices.reduce(0) { $0 + cellWidth($1) } + endPadding * 2
        return CGSize(width: max(width, height), height: height)
    }

    /// Each item's cell on the glass, in absolute coordinates (its tap area, for accessibility).
    private(set) var cellRects: [CGRect] = []

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let total = items.indices.reduce(0) { $0 + cellWidth($1) }
        var x = (size.width - total) / 2
        cellRects = []
        for i in items.indices {
            let w = cellWidth(i)
            cellRects.append(CGRect(x: ctx.origin.x + x, y: ctx.origin.y, width: w, height: size.height))
            var s = natural(i)
            s.width = min(s.width, w)
            items[i].place(at: CGPoint(x: x + (w - s.width) / 2, y: (size.height - s.height) / 2), size: s, ctx)
            x += w
        }
    }

    override func drawContent(_ p: Painter) {
        if let appearance {
            let bounds = CGRect(origin: .zero, size: frame.size)
            p.fillGlass(.roundedRect(bounds, radius: bounds.height / 2), appearance: appearance)
        }
        drawChildren(p)
    }
}

/// The floating bottom bar: capsules spread by flexible spaces, with an optional search slot.
/// The search field itself stays a child of the navigation stack (the stack places it at `searchFrame`).
final class ToolbarGlassRowNode: Node {
    let slots: [ToolbarGlassSlot]
    let metrics: NavigationGlassMetrics
    /// Set by the stack before layout: whether the search slot is used, and whether it is a fixed-size button.
    var searchActive = false
    var searchWidth: CGFloat?
    private(set) var searchFrame: CGRect?

    init(slots: [ToolbarGlassSlot], metrics: NavigationGlassMetrics) {
        self.slots = slots
        self.metrics = metrics
        super.init(children: slots.compactMap { if case .group(let g) = $0 { return g } else { return nil } })
    }

    var isEmpty: Bool { children.isEmpty && !searchActive }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: metrics.bottomBarHeight)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        // Elements in order; nil width = flexible.
        enum Element { case node(Node, CGSize), space, search(CGFloat?) }
        var elements: [Element] = []
        for slot in slots {
            switch slot {
            case .group(let g): elements.append(.node(g, g.sizeThatFits(ProposedViewSize(width: nil, height: size.height))))
            case .flexibleSpace: elements.append(.space)
            case .search: if searchActive { elements.append(.search(searchWidth)) }
            }
        }
        // Without an explicit slot the search field goes after the items.
        if searchActive, !slots.contains(where: { if case .search = $0 { return true } else { return false } }) {
            elements.append(.search(searchWidth))
        }
        let gap = metrics.groupSpacing
        // Gaps sit between adjacent visible elements that are not separated by a flexible space.
        var fixed: CGFloat = 0, flexibleSpaces = 0, flexibleSearch = false
        var gaps = 0
        var previousVisible = false
        for e in elements {
            switch e {
            case .node(_, let s): fixed += s.width; if previousVisible { gaps += 1 }; previousVisible = true
            case .search(let w):
                if let w { fixed += w } else { flexibleSearch = true }
                if previousVisible { gaps += 1 }
                previousVisible = true
            case .space: flexibleSpaces += 1; previousVisible = false
            }
        }
        let free = max(0, size.width - fixed - CGFloat(gaps) * gap)
        var searchW: CGFloat = 0, spaceW: CGFloat = 0, startX: CGFloat = 0, extraGap: CGFloat = 0
        if flexibleSearch {
            searchW = free
        } else if flexibleSpaces > 0 {
            spaceW = free / CGFloat(flexibleSpaces)
        } else if gaps == 0 {
            startX = free / 2                      // one capsule: centred
        } else {
            extraGap = free / CGFloat(gaps)        // several: spread across the bar
        }
        var x = startX
        previousVisible = false
        searchFrame = nil
        for e in elements {
            switch e {
            case .node(let node, let s):
                if previousVisible { x += gap + extraGap }
                node.place(at: CGPoint(x: x, y: (size.height - s.height) / 2), size: s, ctx)
                x += s.width
                previousVisible = true
            case .search(let w):
                if previousVisible { x += gap + extraGap }
                let width = w ?? searchW
                searchFrame = CGRect(x: x, y: 0, width: width, height: size.height)
                x += width
                previousVisible = true
            case .space:
                x += spaceW
                previousVisible = false
            }
        }
    }
}
