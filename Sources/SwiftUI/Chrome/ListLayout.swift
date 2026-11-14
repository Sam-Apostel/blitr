// List layout and drawing: rows grouped into sections, cards, separators, headers, footers and
// trailing accessories. One static frame at scroll offset zero.

/// One row: the content plus what the List draws around it (background, badge, chevron).
final class ListRowNode: Node {
    let content: Node
    let background: Node?
    let badge: Node?
    let hasChevron: Bool
    var insets: EdgeInsets
    /// True when the row has no `.listRowInsets`: the List fills in its style's horizontal insets.
    let usesDefaultInsets: Bool
    let minHeight: CGFloat
    let chevronPaint: _Paint
    let chevronSize: CGSize
    let chevronTrailingPad: CGFloat
    let chevronReserveWidth: CGFloat
    let separator: SeparatorSetting?
    let separatorTint: TintSetting?
    /// Leading x of the separator below this row, in the row's coordinates (set after layout).
    var separatorLeading: CGFloat = 0
    /// tvOS: the row is one focusable element (it draws the platter), and whether that element has focus.
    var tvRow = false
    var tvSingleElement = false
    var tvFocused = false
    var tvGlass = false
    var tvScheme = ColorScheme.light

    /// Per-edge overrides from `.listRowInsets(_:_:)`, applied over the default insets.
    let partialInsets: PartialRowInsets?

    init(content: Node, background: Node?, badge: Node?, hasChevron: Bool, insets: EdgeInsets?, partialInsets: PartialRowInsets? = nil,
         design: ListDesignMetrics, minHeight: CGFloat,
         chevronPaint: _Paint, separator: SeparatorSetting?, separatorTint: TintSetting?) {
        self.content = content
        self.background = background
        self.badge = badge
        self.hasChevron = hasChevron
        self.usesDefaultInsets = insets == nil
        self.partialInsets = partialInsets
        self.insets = insets ?? EdgeInsets(top: design.rowInsetVertical, leading: design.rowInsetHorizontal,
                                           bottom: design.rowInsetVertical, trailing: design.rowInsetHorizontal)
        self.minHeight = minHeight
        self.chevronPaint = chevronPaint
        chevronSize = design.chevronSize
        chevronTrailingPad = design.chevronTrailingPad
        chevronReserveWidth = design.chevronReserve
        self.separator = separator
        self.separatorTint = separatorTint
        var kids: [Node] = []
        if let background { kids.append(background) }
        kids.append(content)
        if let badge { kids.append(badge) }
        super.init(children: kids)
        traits = content.traits
        applyPartialInsets()
    }

    func applyPartialInsets() {
        guard let p = partialInsets else { return }
        if let v = p.top { insets.top = v }
        if let v = p.leading { insets.leading = v }
        if let v = p.bottom { insets.bottom = v }
        if let v = p.trailing { insets.trailing = v }
    }

    private var chevronReserve: CGFloat { hasChevron ? chevronReserveWidth : 0 }
    private func badgeReserve() -> CGFloat {
        guard let badge else { return 0 }
        return badge.sizeThatFits(.unspecified).width + ListMetrics.badgeGap
    }
    private func contentWidth(_ width: CGFloat) -> CGFloat {
        max(0, width - insets.leading - insets.trailing - chevronReserve - badgeReserve())
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let width: CGFloat
        if let w = proposal.width, w.isFinite {
            width = w
        } else {
            width = content.sizeThatFits(.unspecified).width + insets.leading + insets.trailing + chevronReserve + badgeReserve()
        }
        let c = content.sizeThatFits(ProposedViewSize(width: contentWidth(width), height: nil))
        return CGSize(width: width, height: max(minHeight, c.height + insets.top + insets.bottom))
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        background?.place(at: .zero, size: size, ctx)
        let c = content.sizeThatFits(ProposedViewSize(width: contentWidth(size.width), height: nil))
        let available = size.height - insets.top - insets.bottom
        content.place(at: CGPoint(x: insets.leading, y: insets.top + (available - c.height) / 2), size: c, ctx)
        if let badge {
            let b = badge.sizeThatFits(.unspecified)
            badge.place(at: CGPoint(x: size.width - insets.trailing - chevronReserve - b.width, y: (size.height - b.height) / 2), size: b, ctx)
        }
        if let text = content.firstDescendant(TextNode.self) {
            separatorLeading = text.absoluteOrigin.x - ctx.origin.x
        } else {
            separatorLeading = insets.leading
        }
    }

    override func drawContent(_ p: Painter) {
        if tvRow { drawTV(p); return }
        drawChildren(p)
        guard hasChevron else { return }
        let w = chevronSize.width, h = chevronSize.height
        let right = frame.width - insets.trailing - chevronTrailingPad
        let midY = frame.height / 2
        var path = Path()
        path.move(to: CGPoint(x: right - w, y: midY - h / 2))
        path.addLine(to: CGPoint(x: right, y: midY))
        path.addLine(to: CGPoint(x: right - w, y: midY + h / 2))
        p.stroke(path, with: chevronPaint,
                 style: StrokeStyle(lineWidth: ListMetrics.chevronLineWidth, lineCap: .round, lineJoin: .round),
                 in: CGRect(origin: .zero, size: frame.size))
    }
}

final class ListNode: Node {
    struct Section {
        var header: Node?
        var rows: [ListRowNode]
        var footer: Node?
        var spacing: ListSectionSpacing?
        var separator: SeparatorSetting?
        var separatorTint: TintSetting?
    }

    let style: ListStyleKind
    let sections: [Section]
    let backgroundColor: RGBA?
    let cardColor: RGBA
    let separatorColor: RGBA
    let rowSpacing: CGFloat?
    let listSectionSpacing: ListSectionSpacing
    let design: ListDesignMetrics
    /// The glass looks apply to inset grouped lists only (plain and grouped keep their geometry).
    let usesGlassGeometry: Bool
    /// tvOS: rows without cards or separators; the focused row is a raised white platter (Chrome/TV/TVList.swift).
    let tv: Bool
    /// The List is the content of a NavigationStack (its bar sits right above it).
    let underNavigationBar: Bool

    // Results of layout, in this node's coordinates.
    private var cards: [(rect: CGRect, radius: CGFloat, rows: Range<Int>, section: Int)] = []
    private var separators: [(rect: CGRect, color: RGBA)] = []
    var bleed = EdgeInsets()
    /// Structural identity, so the focus engine can scroll the list to the focused row.
    var scrollIdentity: IdentityPath?
    /// Height of everything in the list (after layout), for the largest scroll offset.
    var contentHeight: CGFloat = 0
    /// Glass: VoiceOver frames of each section's header and footer box (local coordinates, by section), and
    /// whether a row's only element takes the row's frame, as UIKit cells report them.
    var axHeaderBoxes: [Int: CGRect] = [:]
    var axFooterBoxes: [Int: CGRect] = [:]
    var axRowFrames: Bool { design.sections != nil || design.plainSections != nil }

    init(items: [Node], style: ListStyleKind, env: EnvironmentValues) {
        self.style = style
        let colors = ListMetrics.colors(env, style: style)
        // tvOS lists have no background of their own (est.): the screen shows through.
        backgroundColor = env.scrollContentBackground == .hidden || env.renderPlatform == .tvOS ? nil : colors.background
        cardColor = colors.card
        rowSpacing = env.listRowSpacing
        listSectionSpacing = env.listSectionSpacing
        tv = env.renderPlatform == .tvOS
        usesGlassGeometry = !tv && env.designLanguage.isGlass && style == .insetGrouped
        let design = tv ? ListMetrics.forTV() : ListMetrics.forDesign(env.designLanguage, style: style)
        self.design = design
        if let colors = design.separatorColors {
            separatorColor = env.colorScheme == .dark ? colors.dark : colors.light
        } else {
            separatorColor = SystemColor.separator.resolve(env.colorScheme)
        }
        underNavigationBar = env.navigationStackIdentity != nil
        let minHeight = env.explicitMinListRowHeight ?? design.minRowHeight
        let chevronPaint = _Paint.color(SystemColor.tertiaryLabel.resolve(env.colorScheme))
        var badgeEnv = env
        badgeEnv.font = .system(size: ListMetrics.badgeFontSize)
        badgeEnv.foregroundStyle = AnyShapeStyle(Color(SystemColor.secondaryLabel.resolve(env.colorScheme)))
        badgeEnv.foregroundStyleLevels = nil
        badgeEnv.textCase = nil

        func makeRow(_ node: Node, inherited: Traits?) -> ListRowNode {
            func trait<K: TraitKey>(_ key: K.Type) -> K.Value? { node.traits[key] ?? inherited?[key] }
            let row = ListRowNode(content: node, background: trait(ListRowBackgroundTraitKey.self),
                               badge: trait(BadgeTraitKey.self).map { $0.makeNode(badgeEnv) },
                               hasChevron: ListNode.hasDisclosure(node),
                               insets: trait(ListRowInsetsTraitKey.self), partialInsets: trait(ListRowPartialInsetsTraitKey.self),
                               design: design, minHeight: minHeight,
                               chevronPaint: chevronPaint, separator: trait(ListRowSeparatorTraitKey.self),
                               separatorTint: trait(ListRowSeparatorTintTraitKey.self))
            if let inset = design.switchRowInsetVertical, row.usesDefaultInsets, ListNode.containsSwitch(node) {
                row.insets.top = inset
                row.insets.bottom = inset
                row.applyPartialInsets()
            }
            return row
        }

        var sections: [Section] = []
        var loose: [ListRowNode] = []
        func flushLoose() {
            if !loose.isEmpty { sections.append(Section(header: nil, rows: loose, footer: nil)) }
            loose = []
        }
        for item in items {
            if let marker = item as? SectionMarkerNode {
                flushLoose()
                sections.append(Section(header: marker.header, rows: marker.rows.map { makeRow($0, inherited: marker.traits) },
                                        footer: marker.footer, spacing: marker.spacing,
                                        separator: marker.traits[ListSectionSeparatorTraitKey.self],
                                        separatorTint: marker.traits[ListSectionSeparatorTintTraitKey.self]))
            } else {
                loose.append(makeRow(item, inherited: nil))
            }
        }
        flushLoose()
        self.sections = sections
        if tv { ListNode.markTVFocus(sections.flatMap(\.rows), glass: env.designLanguage.isGlass, scheme: env.colorScheme) }
        var kids: [Node] = []
        for s in sections {
            if let h = s.header { kids.append(h) }
            kids.append(contentsOf: s.rows as [Node])
            if let f = s.footer { kids.append(f) }
        }
        super.init(children: kids)
    }

    static func hasDisclosure(_ node: Node) -> Bool {
        if node.traits[ListRowAccessoryTraitKey.self] == .disclosureIndicator { return true }
        return node.children.contains { hasDisclosure($0) }
    }

    /// Whether a large-title navigation bar sits right above the list. The bar is not visible from here, so this
    /// reads how far the stack pushed the safe area down: an inline bar takes 54pt below the screen's (or a
    /// sheet's) top inset, a large title 106pt.
    private func underLargeTitle(_ ctx: PlaceContext) -> Bool {
        guard underNavigationBar else { return false }
        var depth = ctx.safeRect.minY - ctx.container.minY
        if ctx.container.minY < 1 { depth -= _currentConfiguration().device.safeArea.top }
        return depth > ListMetrics.largeTitleDepthThreshold
    }

    /// A row holding a Toggle drawn as a switch.
    static func containsSwitch(_ node: Node) -> Bool {
        if node.ax?.info.role == "switch" { return true }
        return node.children.contains { containsSwitch($0) }
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let own = CGRect(origin: ctx.origin, size: size)
        bleed = ctx.safeAreaBleed(for: own, edges: .all)
        if tv { layoutTV(size: size, ctx); return }
        cards = []
        separators = []
        axHeaderBoxes = [:]
        axFooterBoxes = [:]
        let margin = ChromeMetrics.layoutMargin(forWidth: size.width)
        let cardX: CGFloat = (style == .insetGrouped || style == .inset) ? ChromeMetrics.insetListMargin(forWidth: size.width) : 0
        let cardW = max(0, size.width - cardX * 2)
        let radius: CGFloat = style == .insetGrouped ? design.cardCornerRadius : 0
        let plainInset = margin + design.plainExtraInset
        for section in sections {
            for row in section.rows where row.usesDefaultInsets && style == .plain {
                row.insets.leading = plainInset
                row.insets.trailing = plainInset
                row.applyPartialInsets()
            }
        }
        // Rows, headers and footers have no safe area of their own (no bleeding out of a row).
        var inner = ctx
        let unbounded = CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
        inner.container = unbounded
        inner.safeRect = unbounded

        // Scrolled by the focus engine (tvOS: the focused row is kept on screen); zero otherwise.
        let scrollOffset = scrollIdentity.flatMap { Runtime.current?.focus.scrollOffsets[$0]?.y } ?? 0
        var y = max(0, ctx.safeRect.minY - ctx.origin.y) - scrollOffset
        let grouped = style.isGroupedFamily
        let thickness = design.separatorThickness
        var previousHadFooter = false

        for (index, section) in sections.enumerated() {
            let hasHeader = section.header != nil
            // Space above the section.
            if grouped, let g = design.sections {
                // Glass: the previous section ended with its footer box or `sectionBottom`; this one starts
                // with its header box or `sectionTop` (custom spacing replaces the gap between the two).
                let custom = (section.spacing?.value ?? listSectionSpacing.value)
                if index == 0 {
                    if !hasHeader { y += underLargeTitle(ctx) ? g.firstSectionTopUnderLargeTitle : g.firstSectionTop }
                } else if let custom {
                    y += custom
                } else {
                    if !previousHadFooter { y += g.sectionBottom }
                    if !hasHeader { y += g.sectionTop }
                }
            } else if grouped {
                let custom = (section.spacing?.value ?? listSectionSpacing.value)
                if index == 0 {
                    y += hasHeader ? ListMetrics.firstHeaderTop : ListMetrics.firstSectionTop
                } else if let custom {
                    y += custom
                } else if previousHadFooter {
                    y += hasHeader ? ListMetrics.afterFooterHeaderSpacing : ListMetrics.afterFooterSpacing
                } else {
                    y += hasHeader ? ListMetrics.headerTopSpacing : ListMetrics.sectionSpacing
                }
            }
            // Header.
            if let header = section.header {
                if grouped, let g = design.sections {
                    let width = cardW - design.headerInset * 2
                    let h = header.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    header.place(at: CGPoint(x: cardX + design.headerInset, y: y + g.headerPaddingTop), size: h, inner)
                    let box = g.headerPaddingTop + h.height + g.headerPaddingBottom
                    axHeaderBoxes[index] = CGRect(x: cardX, y: y, width: cardW, height: box)
                    y += box
                } else if grouped {
                    let width = cardW - ListMetrics.headerInset * 2
                    let h = header.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    header.place(at: CGPoint(x: cardX + ListMetrics.headerInset, y: y), size: h, inner)
                    let baseline = header.explicitAlignment(VerticalAlignment.lastTextBaseline.key, size: h) ?? h.height
                    y += baseline + design.headerBaselineToCard
                } else if let plain = design.plainSections {
                    if index > 0 { y += plain.gap }
                    let width = size.width - plainInset * 2
                    let h = header.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    header.place(at: CGPoint(x: plainInset, y: y + plain.headerPadding), size: h, inner)
                    axHeaderBoxes[index] = CGRect(x: 0, y: y, width: size.width, height: h.height + plain.headerPadding * 2)
                    y += h.height + plain.headerPadding * 2
                } else {
                    let width = size.width - plainInset * 2
                    let h = header.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    let blockHeight = max(ListMetrics.plainHeaderHeight, h.height + 8)
                    header.place(at: CGPoint(x: plainInset, y: y + (blockHeight - h.height) / 2), size: h, inner)
                    y += blockHeight
                }
            }
            // Rows.
            let separateCards = grouped && (rowSpacing ?? 0) > 0
            var cardTop = y
            for (i, row) in section.rows.enumerated() {
                if separateCards && i > 0 { y += rowSpacing ?? 0; cardTop = y }
                let rowSize = row.sizeThatFits(ProposedViewSize(width: cardW, height: nil))
                row.place(at: CGPoint(x: cardX, y: y), size: rowSize, inner)
                y += rowSize.height
                if separateCards {
                    cards.append((CGRect(x: cardX, y: cardTop, width: cardW, height: y - cardTop), radius, i..<(i + 1), index))
                } else if !grouped, let spacing = rowSpacing, spacing > 0, i < section.rows.count - 1 {
                    y += spacing
                }
            }
            if !section.rows.isEmpty && !separateCards {
                cards.append((CGRect(x: cardX, y: cardTop, width: cardW, height: y - cardTop), radius, 0..<section.rows.count, index))
            }
            // Separators between rows (and below the last row in plain lists).
            if !separateCards {
                for (i, row) in section.rows.enumerated() {
                    let isLast = i == section.rows.count - 1
                    let next = isLast ? nil : section.rows[i + 1]
                    if isLast && grouped { continue }
                    if isLast && section.separator?.hides(.bottom) == true { continue }
                    if row.separator?.hides(.bottom) == true || next?.separator?.hides(.top) == true { continue }
                    let leading = row.frame.minX + row.separatorLeading
                    let trailing = cardX + cardW - design.separatorTrailingInset
                    let tint = (row.separatorTint?.edges.contains(.bottom) == true ? row.separatorTint?.color : nil)
                        ?? (isLast ? section.separatorTint?.color : nil) ?? separatorColor
                    separators.append((CGRect(x: leading, y: row.frame.maxY - thickness, width: max(0, trailing - leading), height: thickness), tint))
                }
            }
            // Grouped: full-width section separators above and below the card.
            if style == .grouped, !section.rows.isEmpty, !separateCards, let card = cards.last?.rect {
                let tint = section.separatorTint?.color ?? separatorColor
                if section.separator?.hides(.top) != true {
                    separators.append((CGRect(x: card.minX, y: card.minY, width: card.width, height: thickness), tint))
                }
                if section.separator?.hides(.bottom) != true {
                    separators.append((CGRect(x: card.minX, y: card.maxY - thickness, width: card.width, height: thickness), tint))
                }
            }
            // Footer.
            previousHadFooter = section.footer != nil
            if let footer = section.footer {
                if grouped, let g = design.sections {
                    let width = cardW - design.headerInset * 2
                    let f = footer.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    footer.place(at: CGPoint(x: cardX + design.headerInset, y: y + g.footerPaddingTop), size: f, inner)
                    let box = g.footerPaddingTop + f.height + g.footerPaddingBottom
                    axFooterBoxes[index] = CGRect(x: cardX, y: y, width: cardW, height: box)
                    y += box
                } else if grouped {
                    y += ListMetrics.footerTopSpacing
                    let width = cardW - ListMetrics.headerInset * 2
                    let f = footer.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    footer.place(at: CGPoint(x: cardX + ListMetrics.headerInset, y: y), size: f, inner)
                    y += f.height
                } else {
                    let width = size.width - plainInset * 2
                    let f = footer.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    footer.place(at: CGPoint(x: plainInset, y: y + ListMetrics.plainFooterVerticalPadding), size: f, inner)
                    y += f.height + ListMetrics.plainFooterVerticalPadding * 2
                }
            }
        }
        contentHeight = y + scrollOffset + max(0, ctx.origin.y + size.height - ctx.safeRect.maxY)
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let visible = bounds.outset(by: bleed)
        p.save()
        p.clip(visible)
        if let backgroundColor {
            p.fill(Path(visible), with: .color(backgroundColor), in: visible)
        }
        if tv {
            for section in sections {
                section.header?.draw(p)
                for row in section.rows { row.draw(p) }
                section.footer?.draw(p)
            }
            p.restore()
            return
        }
        for (index, section) in sections.enumerated() {
            section.header?.draw(p)
            for card in cards where card.section == index {
                let path = Path(roundedRect: card.rect, cornerRadius: card.radius, style: .continuous)
                if style.hasCards || style == .inset {
                    p.fill(path, with: .color(cardColor), in: card.rect)
                }
                p.save()
                if card.radius > 0 { p.clip(path) }
                for row in section.rows[card.rows] { row.draw(p) }
                p.restore()
            }
            section.footer?.draw(p)
        }
        for separator in separators {
            p.fill(Path(separator.rect), with: .color(separator.color), in: separator.rect)
        }
        p.restore()
    }
}
