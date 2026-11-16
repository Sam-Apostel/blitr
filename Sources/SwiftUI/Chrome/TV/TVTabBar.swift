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

    // tvOS 26 top tab bar (measured: tvOS 26.5). A light glass capsule, 68 pt high, 46 pt from the top; each
    // tab is its icon and a semibold title; tab contents 62 pt apart, 39 pt from the capsule's ends; the selected
    // or focused pill reaches 27 pt beyond the content and 14 pt inside the capsule's top and bottom.
    static let glassTabTitleFont = Font.system(size: 29, weight: .semibold)
    static let glassTabIconSpacing: CGFloat = 12
    static let glassTabContentSpacing: CGFloat = 62
    static let glassTabEndPadding: CGFloat = 39
    static let glassTabPillPadding: CGFloat = 27
    static let glassTabPillInset: CGFloat = 14
    /// From the bottom of the bar to the top of the content's safe area (measured: 157 - 114).
    static let glassTabContentGap: CGFloat = 43
    // tvOS 26 sidebar while a tab has focus (measured): a glass panel at (35, 35), 340 pt wide, fitted to its
    // rows (66 pt, 10 apart, 19 pt in from the sides, 25 from the top, 21 from the bottom); the screen behind
    // is dimmed by 30% black; the content keeps its place, 60 pt below the safe area's top.
    static let glassSidebarOrigin: CGFloat = 35
    static let glassSidebarWidth: CGFloat = 340
    static let glassSidebarRowGap: CGFloat = 10
    static let glassSidebarRowInset: CGFloat = 19
    static let glassSidebarTopPadding: CGFloat = 25
    static let glassSidebarBottomPadding: CGFloat = 21
    static let glassSidebarDim: Double = 0.3
    static let glassSidebarContentTop: CGFloat = 60
    static let glassSidebarTitleFont = Font.system(size: 28, weight: .medium)
}

extension TVColors {
    /// tvOS 26 tab bar capsule (measured: light, white at about 80%; dark, black at about 13%) and the
    /// selected tab's pill while focus is elsewhere (light, black at 10%; dark, white at about 10% over the bar:
    /// 43 -> 64.4). The focused tab is white in light and (234, 235, 235) in dark; a focused sidebar row stays white.
    /// measured: tvOS 26.5 simulator
    static func glassTabBar(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(0, 0, 0, 0.13) : RGBA(1, 1, 1, 0.8) }
    static func glassSelectedTab(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(1, 1, 1, 0.14) : RGBA(0, 0, 0, 0.1) }
    /// Unselected titles of the expanded tvOS 26 sidebar (measured: tvOS 26.5 simulator; light (86, 87, 90) over 213,
    /// black at about 55%; dark (222, 223, 225) over 33, white at about 85%).
    static func glassSidebarTitle(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(1, 1, 1, 0.85) : RGBA(0, 0, 0, 0.54) }
    static func glassFocusedTab(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(234 / 255.0, 235 / 255.0, 235 / 255.0, 1) : RGBA(1, 1, 1, 1) }
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
            let glass = env.designLanguage.isGlass
            if isFocused { color = TVColors.focusedLabel(glass: glass) }
            else if isSelected || (glass && !layout.isSidebar) { color = scheme == .dark ? .white : TVColors.focusedLabel(glass: glass) }
            else if glass && layout.isSidebar { color = TVColors.glassSidebarTitle(scheme) }
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
                item.icon = label(adjust(glass ? TVMetrics.glassSidebarTitleFont : TVMetrics.sidebarIconFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first
                if !collapsed {
                    item.title = label(adjust(glass ? TVMetrics.glassSidebarTitleFont : TVMetrics.sidebarTitleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
                }
            } else if glass {
                // tvOS 26: icon and title (measured).
                item.icon = label(adjust(TVMetrics.glassTabTitleFont)).lazy.compactMap { $0.firstDescendant(ImageNode.self) }.first
                item.title = label(adjust(TVMetrics.glassTabTitleFont)).lazy.compactMap { $0.firstDescendant(TextNode.self) }.first
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
        case .topBar where design.isGlass:
            let top = screen.minY + TVMetrics.tabBarTop
            let height = TVMetrics.tabBarHeight
            let parts = items.map { (icon: $0.icon?.sizeThatFits(.unspecified), title: $0.title?.sizeThatFits(.unspecified)) }
            let widths = parts.map { p -> CGFloat in
                let i = p.icon?.width ?? 0, t = p.title?.width ?? 0
                return i + t + (p.icon != nil && p.title != nil ? TVMetrics.glassTabIconSpacing : 0)
            }
            let total = widths.reduce(0, +) + TVMetrics.glassTabContentSpacing * CGFloat(max(0, widths.count - 1)) + TVMetrics.glassTabEndPadding * 2
            capsule = CGRect(x: screen.midX - total / 2, y: top, width: total, height: height)
            var x = capsule.minX + TVMetrics.glassTabEndPadding
            itemRects = []
            for (i, item) in items.enumerated() {
                let mid = top + height / 2
                var cx = x
                if let s = parts[i].icon {
                    item.icon?.place(at: CGPoint(x: cx, y: mid - s.height / 2), size: s, ctx)
                    cx += s.width + TVMetrics.glassTabIconSpacing
                }
                if let s = parts[i].title { item.title?.place(at: CGPoint(x: cx, y: mid - s.height / 2), size: s, ctx) }
                let pad = TVMetrics.glassTabPillPadding, inset = TVMetrics.glassTabPillInset
                itemRects.append(CGRect(x: x - pad, y: top + inset, width: widths[i] + pad * 2, height: height - inset * 2))
                x += widths[i] + TVMetrics.glassTabContentSpacing
            }
            barTop = top
            glassItemFrames = itemRects.map { CGRect(x: $0.minX, y: top, width: $0.width, height: height) }
            glassBarFrame = capsule
            let safeTop = max(ctx.safeRect.minY, ctx.origin.y + top + height + TVMetrics.glassTabContentGap)
            inner.safeRect = CGRect(x: ctx.safeRect.minX, y: safeTop, width: ctx.safeRect.width, height: max(0, ctx.safeRect.maxY - safeTop))
        case .sidebar(let expanded) where design.isGlass && expanded:
            let o = TVMetrics.glassSidebarOrigin, rowH = TVMetrics.sidebarRowHeight, gap = TVMetrics.glassSidebarRowGap
            let width = TVMetrics.glassSidebarWidth, inset = TVMetrics.glassSidebarRowInset
            let panelHeight = TVMetrics.glassSidebarTopPadding + CGFloat(items.count) * rowH + CGFloat(max(0, items.count - 1)) * gap
                + TVMetrics.glassSidebarBottomPadding
            capsule = CGRect(x: screen.minX + o, y: screen.minY + o, width: width, height: panelHeight)
            itemRects = []
            for (i, item) in items.enumerated() {
                let rect = CGRect(x: capsule.minX + inset, y: capsule.minY + TVMetrics.glassSidebarTopPadding + CGFloat(i) * (rowH + gap),
                                  width: width - inset * 2, height: rowH)
                itemRects.append(rect)
                let iconSize = item.icon?.sizeThatFits(.unspecified) ?? .zero
                item.icon?.place(at: CGPoint(x: rect.minX + 16, y: rect.midY - iconSize.height / 2), size: iconSize, ctx)
                if let title = item.title {
                    let textX = rect.minX + 16 + (item.icon == nil ? 0 : 44)
                    var s = title.sizeThatFits(.unspecified)
                    s.width = min(s.width, rect.maxX - 16 - textX)
                    title.place(at: CGPoint(x: textX, y: rect.midY - s.height / 2), size: s, ctx)
                }
            }
            barTop = capsule.minY
            glassItemFrames = itemRects
            glassBarFrame = capsule
            let safeTop = ctx.safeRect.minY + TVMetrics.glassSidebarContentTop
            inner.safeRect = CGRect(x: ctx.safeRect.minX, y: safeTop, width: ctx.safeRect.width, height: max(0, ctx.safeRect.maxY - safeTop))
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
                p.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2, style: .circular), with: .color(TVColors.glassTabBar(scheme)), in: capsule)
            } else {
                // tvOS 18: "By default, a tab bar is translucent" (HIG).
                p.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2, style: .circular), with: .color(TVColors.tabBar(scheme)), in: capsule)
            }
        case .sidebar(let expanded) where glass && expanded:
            let screen = CGRect(x: -frame.minX - 4000, y: -frame.minY - 4000, width: 12000, height: 12000)
            p.fill(Path(screen), with: .color(RGBA(0, 0, 0, TVMetrics.glassSidebarDim)), in: screen)
            p.fillGlass(.roundedRect(capsule, radius: 40), appearance: TVColors.glassCard(scheme, design: design))
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
            if glass && i == tvFocusedIndex {
                // tvOS 26: white, 4 pt larger, the focus shadow (measured).
                let plate = rect.insetBy(dx: -TVMetrics.glassFocusGrowth, dy: -TVMetrics.glassFocusGrowth)
                let r = layout.isSidebar ? min(plate.height / 2, 22) : plate.height / 2
                let shadow = plate.insetBy(dx: TVMetrics.glassShadowInset, dy: 0).offsetBy(dx: 0, dy: TVMetrics.glassShadowY)
                p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: TVMetrics.glassShadowRadius, scale: p.scale)))
                p.fill(Path(roundedRect: shadow, cornerRadius: r, style: .continuous), with: .color(RGBA(0, 0, 0, TVMetrics.glassShadowOpacity)), in: shadow)
                p.restore()
                p.fill(Path(roundedRect: plate, cornerRadius: r, style: .continuous), with: .color(layout.isSidebar ? TVColors.focusedPlatter : TVColors.glassFocusedTab(scheme)), in: plate)
                item.icon?.draw(p); item.title?.draw(p)
                continue
            }
            if glass && i == selectedIndex && !layout.isSidebar {
                p.fill(pill, with: .color(TVColors.glassSelectedTab(scheme)), in: rect)
                item.icon?.draw(p); item.title?.draw(p)
                continue
            }
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
