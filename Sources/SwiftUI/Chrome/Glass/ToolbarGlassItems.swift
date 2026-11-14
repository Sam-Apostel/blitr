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
    /// Glyph only: a padded glyph (a circle on its own).
    case icon
    /// A button with text: padded capsule.
    case text
    /// Text that is not a button (a NavigationLink, a plain Text): less padding.
    case plainText
    /// The back button: fills its circle.
    case back
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
    if node is BackButtonNode { return .back }
    visit(node)
    if !plain { return .custom }
    if hasText { return toolbarGlassInfo(of: node) == nil ? .plainText : .text }
    return .icon
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
    /// A fixed `ToolbarSpacer`: keeps the capsules on either side apart (the normal gap).
    case fixedSpace
    case search
}

@MainActor
func makeToolbarGlassSlots(_ tokens: [ToolbarGlassToken], height: CGFloat, metrics: NavigationGlassMetrics,
                           neutral: GlassAppearance, prominent: GlassAppearance, bottom: Bool = false) -> [ToolbarGlassSlot] {
    var slots: [ToolbarGlassSlot] = []
    var run: [Node] = [], kinds: [ToolbarGlassItemKind] = []
    var runProminent = false
    func flush() {
        guard !run.isEmpty else { return }
        slots.append(.group(ToolbarGlassGroupNode(items: run, kinds: kinds, appearance: runProminent ? prominent : neutral,
                                                  height: height, metrics: metrics, bottom: bottom)))
        run = []; kinds = []
    }
    for token in tokens {
        switch token {
        case .spacer(let flexible):
            flush()
            slots.append(flexible ? .flexibleSpace : .fixedSpace)
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
                                                          height: height, metrics: metrics, bottom: bottom)))
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
    /// A capsule of the floating bottom bar (its own spacing and end insets).
    let bottom: Bool
    /// False when the bottom bar draws one capsule for this group and the search field next to it.
    var drawsGlass = true
    /// Shares its capsule with the search field: a lone icon keeps the padding of a shared capsule.
    var besideSearch = false
    var items: [Node] { children }

    init(items: [Node], kinds: [ToolbarGlassItemKind], appearance: GlassAppearance?, height: CGFloat, metrics: NavigationGlassMetrics,
         bottom: Bool = false) {
        self.bottom = bottom
        self.kinds = kinds
        self.appearance = appearance
        self.height = height
        self.metrics = metrics
        super.init(children: items)
    }

    private func natural(_ i: Int) -> CGSize { items[i].sizeThatFits(ProposedViewSize(width: nil, height: height)) }

    /// Width of item `i`'s frame on the glass.
    private func cellWidth(_ i: Int) -> CGFloat {
        let s = natural(i)
        switch kinds[i] {
        case .icon: return s.width + (items.count == 1 && !besideSearch ? metrics.singleIconItemPadding : metrics.iconItemPadding) * 2
        case .text: return s.width + metrics.textItemPadding * 2
        case .plainText: return s.width + metrics.plainTextItemPadding * 2
        case .back: return height
        case .custom: return s.width
        }
    }

    var spacing: CGFloat { bottom ? metrics.bottomItemSpacing : metrics.itemSpacing }
    /// Space between the outer item frames and the ends of the capsule.
    var endInset: CGFloat { appearance == nil || kinds == [.back] ? 0 : bottom ? metrics.bottomItemEndInset : metrics.itemEndInset }

    /// The item frames and the spacing between them.
    private var contentWidth: CGFloat {
        items.indices.reduce(0) { $0 + cellWidth($1) } + CGFloat(max(0, items.count - 1)) * spacing
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        guard appearance != nil else {
            let sizes = items.indices.map(natural)
            return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
        }
        return CGSize(width: max(contentWidth + endInset * 2, height), height: height)
    }

    /// Each item's frame on the glass, in absolute coordinates (its accessibility frame).
    private(set) var cellRects: [CGRect] = []

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let spacing = appearance == nil ? 0 : self.spacing
        var x = (size.width - (appearance == nil ? items.indices.reduce(0) { $0 + natural($1).width } : contentWidth)) / 2
        cellRects = []
        for i in items.indices {
            var s = natural(i)
            let w = appearance == nil ? s.width : cellWidth(i)
            let cellHeight = kinds[i] == .back || appearance == nil ? size.height : min(size.height, metrics.itemFrameHeight)
            cellRects.append(CGRect(x: ctx.origin.x + x, y: ctx.origin.y + (size.height - cellHeight) / 2, width: w, height: cellHeight))
            s.width = min(s.width, w)
            items[i].place(at: CGPoint(x: x + (w - s.width) / 2, y: (size.height - s.height) / 2), size: s, ctx)
            x += w + spacing
        }
    }

    override func drawContent(_ p: Painter) {
        if let appearance, drawsGlass {
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

    /// Capsules the row draws itself: groups that share one piece of glass with the search field.
    private var joinedGlass: [(rect: CGRect, appearance: GlassAppearance)] = []
    /// Whether the search field shares its capsule with a neighbouring group (it then draws no glass of its own).
    private(set) var searchJoined = false

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        // Elements in order; nil width = flexible.
        enum Element { case node(ToolbarGlassGroupNode, CGSize), space, search(CGFloat?) }
        var elements: [Element] = []
        /// Indices of elements that follow a fixed spacer: they never join the element before them.
        var afterFixedSpace = Set<Int>()
        for slot in slots {
            switch slot {
            case .group(let g): elements.append(.node(g, g.measure(ProposedViewSize(width: nil, height: size.height))))
            case .flexibleSpace: elements.append(.space)
            case .fixedSpace: afterFixedSpace.insert(elements.count)
            case .search: if searchActive { elements.append(.search(searchWidth)) }
            }
        }
        // Without an explicit slot the search field goes after the items.
        if searchActive, !slots.contains(where: { if case .search = $0 { return true } else { return false } }) {
            elements.append(.search(searchWidth))
        }
        // iOS 27: a glass group right next to the (unminimized) search field shares its capsule.
        // measured: iOS 27.0 simulator (GlassNavigation: filter button and search field in one capsule).
        func joins(_ i: Int, _ j: Int) -> Bool {
            guard i >= 0, j == i + 1, j < elements.count, !afterFixedSpace.contains(j) else { return false }
            switch (elements[i], elements[j]) {
            case (.node(let g, _), .search(nil)), (.search(nil), .node(let g, _)): return g.appearance != nil
            default: return false
            }
        }
        for (i, e) in elements.enumerated() {
            guard case .node(let g, _) = e else { continue }
            let joined = (i > 0 && joins(i - 1, i)) || (i + 1 < elements.count && joins(i, i + 1))
            // (measure, not sizeThatFits: the cached size does not know about the flag)
            if g.besideSearch != joined {
                g.besideSearch = joined
                elements[i] = .node(g, g.measure(ProposedViewSize(width: nil, height: size.height)))
            }
        }
        func gapBetween(_ i: Int, _ j: Int) -> CGFloat {
            guard joins(i, j) else { return metrics.groupSpacing }
            if case .node(let g, _) = elements[i] { return metrics.searchJoinGap - g.endInset }
            if case .node(let g, _) = elements[j] { return metrics.searchJoinGap - g.endInset }
            return metrics.groupSpacing
        }
        // Gaps sit between adjacent visible elements that are not separated by a flexible space.
        var fixed: CGFloat = 0, flexibleSpaces = 0, flexibleSearch = false
        var gapTotal: CGFloat = 0, spreadGaps = 0
        var previous: Int?
        for (i, e) in elements.enumerated() {
            switch e {
            case .node(_, let s): fixed += s.width
            case .search(let w): if let w { fixed += w } else { flexibleSearch = true }
            case .space: flexibleSpaces += 1; previous = nil; continue
            }
            if let previous {
                gapTotal += gapBetween(previous, i)
                if !joins(previous, i) { spreadGaps += 1 }
            }
            previous = i
        }
        let free = max(0, size.width - fixed - gapTotal)
        var searchW: CGFloat = 0, spaceW: CGFloat = 0, startX: CGFloat = 0, extraGap: CGFloat = 0
        if flexibleSearch {
            searchW = free
        } else if flexibleSpaces > 0 {
            spaceW = free / CGFloat(flexibleSpaces)
        } else if spreadGaps == 0 {
            startX = free / 2                      // one capsule: centred
        } else {
            extraGap = free / CGFloat(spreadGaps)  // several: spread across the bar
        }
        var x = startX
        previous = nil
        searchFrame = nil
        searchJoined = false
        joinedGlass = []
        var placed: [(index: Int, rect: CGRect)] = []
        for (i, e) in elements.enumerated() {
            if case .space = e { x += spaceW; previous = nil; continue }
            if let previous { x += gapBetween(previous, i) + (joins(previous, i) ? 0 : extraGap) }
            switch e {
            case .node(let node, let s):
                node.drawsGlass = true
                let rect = CGRect(x: x, y: (size.height - s.height) / 2, width: s.width, height: s.height)
                node.place(at: rect.origin, size: s, ctx)
                placed.append((i, rect))
                x += s.width
            case .search(let w):
                let rect = CGRect(x: x, y: 0, width: w ?? searchW, height: size.height)
                searchFrame = rect
                placed.append((i, rect))
                x += rect.width
            case .space: break
            }
            previous = i
        }
        // One capsule under each group that shares the search field's glass, and the field.
        for (i, rect) in placed {
            guard case .node(let g, _) = elements[i], let search = searchFrame, let appearance = g.appearance else { continue }
            guard (i > 0 && joins(i - 1, i)) || joins(i, i + 1) else { continue }
            g.drawsGlass = false
            searchJoined = true
            joinedGlass.append((rect.union(search), appearance))
        }
    }

    override func drawContent(_ p: Painter) {
        if let first = joinedGlass.first {
            var union = first.rect
            for g in joinedGlass.dropFirst() { union = union.union(g.rect) }
            p.fillGlass(.roundedRect(union, radius: union.height / 2), appearance: first.appearance)
        }
        drawChildren(p)
    }
}
