// The tvOS tab bar: text tabs centred at the top of the screen (HIG: 68pt high, top edge 46pt from the top
// of the screen), and the `.sidebarAdaptable` sidebar ("macOS and tvOS always show a sidebar";
// WWDC24 "Migrate your TVML app to SwiftUI": a floating sidebar that shrinks to a compact indicator).
//
// States, drawn distinctly: the focused tab is a white, lifted pill with a dark title; the selected tab
// keeps a translucent pill while focus is elsewhere; other tabs show a secondary title. tvOS 26/27 put
// the tabs in a Liquid Glass capsule (est.). The focus engine reads the drawn frames (`glassItemFrames`,
// `glassBarFrame`), so the bar is a focus section at the top of the screen, where it is drawn.

enum TVTabLayout: Equatable {
    case topBar
    /// `.sidebarAdaptable`: expanded while a tab has focus, a compact column of icons otherwise.
    case sidebar(expanded: Bool)

    var isSidebar: Bool { if case .sidebar = self { return true }; return false }
}

extension TVMetrics {
    static let tabTitleFont = Font.system(size: 31, weight: .medium)   // est. (callout size)
    static let sidebarTitleFont = Font.system(size: 29, weight: .medium) // est. (body)
    static let sidebarIconFont = Font.system(size: 30, weight: .medium)  // est.
    static let pageDotScale: CGFloat = 2                                // est.
}

extension TabViewNode {
    /// Resolves the tab items in the colors of their state.
    static func tvItems(_ entries: [TabEntry], selected: Int, focused: Int?, layout: TVTabLayout, env: EnvironmentValues) -> [Item] {
        let scheme = env.colorScheme
        let collapsed = layout == .sidebar(expanded: false)
        return entries.enumerated().map { i, entry in
            let isFocused = i == focused
            let isSelected = i == selected
            let color: RGBA
            if isFocused { color = TVColors.focusedLabel }
            else if isSelected { color = scheme == .dark ? .white : TVColors.focusedLabel }
            else { color = SystemColor.secondaryLabel.resolve(scheme) }
            func adjust(_ font: Font) -> (inout EnvironmentValues) -> Void {
                { e in
                    e.font = font
                    e.fontWeight = nil
                    e.imageScale = .medium
                    e.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color(color)))
                    e.foregroundStyleLevels = nil
                    e.lineLimit = 1
                    e.stackAxis = nil
                    if isFocused { e.colorScheme = .light }
                }
            }
            var item = Item()
            guard let label = entry.label else { return item }
            if layout.isSidebar {
                item.icon = label(adjust(TVMetrics.sidebarIconFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first
                if !collapsed {
                    item.title = label(adjust(TVMetrics.sidebarTitleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
                }
            } else {
                item.title = label(adjust(TVMetrics.tabTitleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
                if item.title == nil {
                    item.icon = label(adjust(TVMetrics.sidebarIconFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first
                }
            }
            return item
        }
    }

    func layoutTV(_ layout: TVTabLayout, size: CGSize, _ ctx: PlaceContext) {
        let screen = ctx.container.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        var inner = ctx
        switch layout {
        case .topBar:
            let top = screen.minY + TVMetrics.tabBarTop
            let height = TVMetrics.tabBarHeight
            let pad = TVMetrics.tabItemHorizontalPadding
            let inset = TVMetrics.tabItemInset
            let sizes = items.map { ($0.title ?? $0.icon)?.sizeThatFits(.unspecified) ?? .zero }
            let widths = sizes.map { $0.width + pad * 2 }
            let total = widths.reduce(0, +) + TVMetrics.tabItemSpacing * CGFloat(max(0, widths.count - 1)) + inset * 2
            capsule = CGRect(x: screen.midX - total / 2, y: top, width: total, height: height)
            var x = capsule.minX + inset
            itemRects = []
            for (item, (s, w)) in zip(items, zip(sizes, widths)) {
                let rect = CGRect(x: x, y: top + inset, width: w, height: height - inset * 2)
                itemRects.append(rect)
                (item.title ?? item.icon)?.place(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), size: s, ctx)
                x += w + TVMetrics.tabItemSpacing
            }
            barTop = top
            glassItemFrames = itemRects.map { CGRect(x: $0.minX, y: top, width: $0.width, height: height) }
            glassBarFrame = capsule
            // Content: full screen, its safe area starting below the bar.
            let safeTop = max(ctx.safeRect.minY, ctx.origin.y + top + height + TVMetrics.tabBarContentGap)
            inner.safeRect = CGRect(x: ctx.safeRect.minX, y: safeTop, width: ctx.safeRect.width, height: max(0, ctx.safeRect.maxY - safeTop))
        case .sidebar(let expanded):
            let safe = ctx.safeRect.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
            let width = expanded ? TVMetrics.sidebarWidth : TVMetrics.sidebarCollapsedWidth
            let rowH = TVMetrics.sidebarRowHeight, gap: CGFloat = 8, pad: CGFloat = 20
            let panelHeight = expanded ? safe.height : pad * 2 + CGFloat(items.count) * rowH + CGFloat(max(0, items.count - 1)) * gap
            capsule = CGRect(x: screen.minX + TVMetrics.sidebarInset, y: safe.minY, width: width, height: panelHeight)
            itemRects = []
            for (i, item) in items.enumerated() {
                let rect = CGRect(x: capsule.minX + 12, y: capsule.minY + pad + CGFloat(i) * (rowH + gap), width: width - 24, height: rowH)
                itemRects.append(rect)
                let iconSize = item.icon?.sizeThatFits(.unspecified) ?? .zero
                let iconX = expanded ? rect.minX + 22 : rect.midX - iconSize.width / 2
                item.icon?.place(at: CGPoint(x: iconX, y: rect.midY - iconSize.height / 2), size: iconSize, ctx)
                if let title = item.title {
                    let textX = item.icon == nil ? rect.minX + 22 : rect.minX + 22 + 44
                    var s = title.sizeThatFits(.unspecified)
                    s.width = min(s.width, rect.maxX - 16 - textX)
                    title.place(at: CGPoint(x: textX, y: rect.midY - s.height / 2), size: s, ctx)
                }
            }
            barTop = capsule.minY
            glassItemFrames = itemRects
            glassBarFrame = capsule
            // The sidebar floats over the content; the content keeps clear of the compact sidebar.
            let leading = ctx.origin.x + capsule.minX + TVMetrics.sidebarCollapsedWidth + 40
            let safeLeft = max(ctx.safeRect.minX, leading)
            inner.safeRect = CGRect(x: safeLeft, y: ctx.safeRect.minY, width: max(0, ctx.safeRect.maxX - safeLeft), height: ctx.safeRect.height)
        }
        let area = inner.safeRect.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        let c = content.sizeThatFits(ProposedViewSize(area.size))
        content.place(at: CGPoint(x: area.midX - c.width / 2, y: area.midY - c.height / 2), size: c, inner)
    }

    func drawTV(_ layout: TVTabLayout, _ p: Painter) {
        let glass = design.isGlass
        switch layout {
        case .topBar:
            if glass {
                p.fillGlass(.roundedRect(capsule, radius: capsule.height / 2), appearance: GlassAppearance.system(.regular, scheme: scheme, design: design))
            } else {
                // tvOS 18: "By default, a tab bar is translucent" (HIG).
                p.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2, style: .circular), with: .color(TVColors.tabBar(scheme)), in: capsule)
            }
        case .sidebar(let expanded):
            if expanded {
                // The content behind an open sidebar is dimmed (est.).
                let shade = CGRect(x: 0, y: 0, width: capsule.maxX + 600, height: frame.height)
                let stops = [GradientStop(color: RGBA(0, 0, 0, scheme == .dark ? 0.6 : 0.25), location: 0),
                             GradientStop(color: RGBA(0, 0, 0, 0), location: 1)]
                p.fill(Path(shade), with: _Paint(.linear(stops: stops, start: .leading, end: .trailing)), in: shade)
            }
            let radius: CGFloat = expanded ? 32 : capsule.width / 2
            if glass {
                p.fillGlass(.roundedRect(capsule, radius: radius), appearance: GlassAppearance.system(.regular, scheme: scheme, design: design))
            } else {
                p.fill(Path(roundedRect: capsule, cornerRadius: radius, style: .continuous), with: .color(TVColors.tabBar(scheme)), in: capsule)
            }
        }
        for (i, item) in items.enumerated() where itemRects.indices.contains(i) {
            let rect = itemRects[i]
            let radius = layout.isSidebar ? min(rect.height / 2, 18) : rect.height / 2
            let pill = Path(roundedRect: rect, cornerRadius: radius, style: layout.isSidebar ? .continuous : .circular)
            if i == tvFocusedIndex {
                // The focused tab: white, raised (HIG: "the selected tab includes a drop shadow").
                p.save()
                let s = TVMetrics.smallLiftScale
                p.translate(rect.midX, rect.midY); p.scale(s, s); p.translate(-rect.midX, -rect.midY)
                p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, 0.3), radius: 16, x: 0, y: 8, scale: p.scale)))
                p.fill(pill, with: .color(TVColors.focusedPlatter), in: rect)
                p.restore()
                item.icon?.draw(p); item.title?.draw(p)
                p.restore()
                continue
            }
            if i == selectedIndex {
                p.fill(pill, with: .color(TVColors.selectedTab(scheme)), in: rect)
            }
            item.icon?.draw(p); item.title?.draw(p)
        }
    }
}
