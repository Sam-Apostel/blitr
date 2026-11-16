// tvOS NavigationStack: no bar chrome and no back button (the remote's Menu button goes back). The title
// is centred at the top of the safe area; leading and trailing toolbar items sit beside it as tvOS
// buttons; `searchable` adds the search field of a tvOS search screen below the title. Sizes are
// estimates (TVMetrics). The on-screen keyboard of a search screen is not drawn.

extension TVMetrics {
    /// tvOS 26: 57 pt bold (measured: tvOS 26.5 simulator, "Account" inks 217.5 pt wide where the medium weight
    /// inks 206, the cap height 40.5 in both); tvOS 18 est. (title 3 size, medium).
    static func navigationTitleFont(glass: Bool) -> Font { .system(size: glass ? 57 : 48, weight: glass ? .bold : .medium) }
    /// The title's top below the safe area's top: tvOS 26 places it 4 pt above it (measured: tvOS 26.5 simulator,
    /// the ink of "Account" and "Settings" 8 pt higher than with the title's top 4 pt below the safe area's top);
    /// tvOS 18 est.
    static func navigationTitleTop(glass: Bool) -> CGFloat { glass ? -4 : 4 }
    /// tvOS 26 toolbar items beside the title: capsules 70 pt high, 2 pt below the safe area's top, headline
    /// labels 36 pt in, white in both appearances, on a film of black 7.5% (light) or white 10.5% (dark)
    /// (measured: tvOS 26.5 simulator, "Help": 1690 to 1840 by 62 to 131 across its middle, (230, 231, 241) ->
    /// (214, 212, 222) light, (55, 55, 59) -> (76, 76, 80) dark, the H 27 pt high; "Edit" 1705 to 1840 by 62 to
    /// 131). Focused, it is white and grows by 4 pt like other controls ("Edit": 1701 to 1844 by 58 to 136).
    static let glassToolbarItemTop: CGFloat = 2
    /// tvOS 26: a `List` whose first section has no header starts 6 pt higher under a navigation title than a
    /// header does (measured: tvOS 26.5 simulator, the first row of a List under "Account" at 145, where a Form's
    /// first header sits at 151).
    static let glassHeaderlessListLift: CGFloat = 6
    /// tvOS 26: a NavigationStack in a tab of the tab bar has its title 60.5 pt and its content 60 pt lower than the
    /// tab's content would start (measured: tvOS 26.5 simulator, TVFocus "Settings Tabs": the ink of the "Settings" title from
    /// 226 to 278, the first row of its headerless List at 302, where content under the bar starts at 157).
    static let glassTabbedTitleDrop: CGFloat = 60.5
    static let glassTabbedContentDrop: CGFloat = 60
    /// tvOS 26: a segmented picker in a List row sits 5.5 pt inside its 95 pt row (measured: tvOS 26.5 simulator,
    /// rows at 60 and 249, the segments 84 pt high at 146).
    static let glassSegmentedRowInset: CGFloat = 5.5
    static let glassToolbarItemHeight: CGFloat = 70
    static let glassToolbarItemPadding: CGFloat = 36
    static let searchFont = Font.system(size: 38, weight: .medium)            // est. (HIG search screen image)

    // tvOS 26 search screen (measured: tvOS 26.5). No field platter: a large magnifier and the prompt in bold,
    // the "Press ⏯ to change keyboards" hint at the trailing edge, then the keyboard row (123, SPACE, a-z,
    // delete: letters 54 pt apart, keys 64 pt high, 104.5 pt below the top), a hairline 214 pt below the top,
    // and the results 245.5 pt below the top.
    static let glassSearchFont = Font.system(size: 57, weight: .bold)
    static let glassSearchHeight: CGFloat = 214
    static let glassSearchContentTop: CGFloat = 245.5
    static let glassKeyRowTop: CGFloat = 104.5
    static let glassKeyHeight: CGFloat = 64
    static let glassKeyPitch: CGFloat = 54
    static let glassFirstLetterX: CGFloat = 245
    static let glassPromptX: CGFloat = 116
}

extension SearchFieldNode {
    /// The keyboard row of a tvOS 26 search screen and the hint: keys first (123, SPACE, a-z, delete).
    static func tvGlassKeyboard(env: EnvironmentValues, focused: Bool) -> (keys: [Node], hint: [Node]) {
        let scheme = env.colorScheme
        func text(_ s: String, font: Font, color: RGBA, light: Bool = false) -> Node {
            var e = env
            if light { e.colorScheme = .light }
            e.font = font
            e.fontWeight = nil
            e.lineLimit = 1
            e.textCase = nil
            e.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color(color)))
            e.foregroundStyleLevels = nil
            return Text(verbatim: s).makeNode(e)
        }
        func image(_ name: String, size: CGFloat, color: RGBA) -> Node {
            var e = env
            e.font = .system(size: size, weight: .medium)
            e.imageScale = .medium
            e.foregroundStyle = AnyShapeStyle(_FixedPaintStyle(.color(color)))
            e.foregroundStyleLevels = nil
            let node = ImageNode(content: Image(systemName: name).content(in: e), isResizable: false)
            node.isDecorative = true
            return node
        }
        let dim = TVColors.dimmedTitle(scheme)
        let badge = scheme == .dark ? RGBA(0, 0, 0, 0.85) : RGBA(1, 1, 1, 1)
        var keys = [text("123", font: .system(size: 19, weight: .semibold), color: badge),
                    text("SPACE", font: .system(size: 19, weight: .semibold), color: badge)]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            let isFocusedKey = focused && i == 0
            keys.append(text(String(c), font: .system(size: 46), color: isFocusedKey ? TVColors.focusedLabel : TVColors.glassKeyBadge(scheme), light: isFocusedKey))
        }
        keys.append(image("delete.left.fill", size: 30, color: TVColors.glassKeyBadge(scheme)))
        let hint = [text("Press", font: .headline, color: dim), image("playpause.circle.fill", size: 36, color: dim),
                    text("to change keyboards", font: .headline, color: dim)]
        return (keys, hint)
    }
}

extension TVColors {
    /// The 123 / SPACE badges and the delete key of the tvOS 26 keyboard row (measured: dark grey, about 60% black).
    static func glassKeyBadge(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(1, 1, 1, 0.6) : RGBA(0, 0, 0, 0.62) }
}

extension NavigationStackNode {
    func layoutTV(size: CGSize, _ ctx: PlaceContext) {
        let safe = ctx.safeRect.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        barTop = max(0, safe.minY)
        let hasTitle = inlineTitle != nil || principal != nil
        let barHeight = hasTitle || !leading.isEmpty || !trailing.isEmpty ? TVMetrics.navigationTitleHeight : 0
        // Under the tab bar (the safe area starts below the bar, not at the screen's inset).
        let tabbed = tvGlassBar && barVisible && barHeight > 0
            && ctx.safeRect.minY >= ctx.container.minY + TVMetrics.tabBarTop + TVMetrics.tabBarHeight
        var y = barTop + (barVisible ? barHeight : 0)
        if tabbed {
            barTop += TVMetrics.glassTabbedTitleDrop
            y += TVMetrics.glassTabbedContentDrop
        }
        if tvGlassBar, barVisible, barHeight > 0, search == nil, let list = content.firstDescendant(ListNode.self),
           let first = list.sections.first, first.header == nil {
            y -= TVMetrics.glassHeaderlessListLift
        }
        if barVisible, let search {
            if let field = search as? SearchFieldNode, !field.tvGlassKeys.isEmpty {
                search.place(at: CGPoint(x: safe.minX, y: y), size: CGSize(width: safe.width, height: TVMetrics.glassSearchHeight), ctx)
                y += TVMetrics.glassSearchContentTop
                Runtime.current?.warn("searchable on tvOS: the keyboard row is drawn as it first appears; typing and suggestions are not simulated")
            } else {
                search.place(at: CGPoint(x: safe.minX, y: y), size: CGSize(width: safe.width, height: TVMetrics.searchFieldHeight), ctx)
                y += TVMetrics.searchFieldHeight + 24
                Runtime.current?.warn("searchable on tvOS: the search field is drawn, the on-screen keyboard of a tvOS search screen is not")
            }
        }
        barRegionBottom = y

        let contentRect = CGRect(x: 0, y: barRegionBottom, width: size.width, height: max(0, safe.maxY - barRegionBottom))
        var inner = ctx
        inner.safeRect = CGRect(x: ctx.safeRect.minX, y: ctx.origin.y + contentRect.minY, width: ctx.safeRect.width, height: contentRect.height)
        let c = content.sizeThatFits(ProposedViewSize(contentRect.size))
        content.place(at: CGPoint(x: contentRect.midX - c.width / 2, y: contentRect.midY - c.height / 2), size: c, inner)
        guard barVisible else { return }

        let proposal = ProposedViewSize(width: nil, height: barHeight)
        var x = safe.minX
        for item in leading {
            let s = item.sizeThatFits(proposal)
            item.place(at: CGPoint(x: x, y: tvGlassBar ? barTop + TVMetrics.glassToolbarItemTop : barTop + (barHeight - s.height) / 2), size: s, ctx)
            x += s.width + TVMetrics.toolbarItemSpacing
        }
        let leadingEnd = x
        let sizes = trailing.map { $0.sizeThatFits(proposal) }
        var tx = safe.maxX - sizes.reduce(0) { $0 + $1.width } - CGFloat(max(0, trailing.count - 1)) * TVMetrics.toolbarItemSpacing
        let trailingStart = tx
        for (item, s) in zip(trailing, sizes) {
            item.place(at: CGPoint(x: tx, y: tvGlassBar ? barTop + TVMetrics.glassToolbarItemTop : barTop + (barHeight - s.height) / 2), size: s, ctx)
            tx += s.width + TVMetrics.toolbarItemSpacing
        }
        if let center = principal ?? inlineTitle {
            let maxWidth = max(0, min(size.width / 2 - leadingEnd, trailingStart - size.width / 2) * 2 - 40)
            var s = center.sizeThatFits(ProposedViewSize(width: maxWidth, height: barHeight))
            s.width = min(s.width, maxWidth)
            let top = TVMetrics.navigationTitleTop(glass: tvGlassBar)
            let titleY = tvGlassBar || barHeight >= s.height + top * 2 ? barTop + top : barTop + (barHeight - s.height) / 2
            center.place(at: CGPoint(x: size.width / 2 - s.width / 2, y: titleY), size: s, ctx)
        }
        statusItem?.place(at: .zero, size: .zero, ctx)
        bottomItems?.place(at: .zero, size: .zero, ctx)
        if statusItem != nil || bottomItems != nil {
            Runtime.current?.warn("Bottom-bar and status toolbar items are not drawn on tvOS")
        }
    }
}

extension TVColors {
    static func searchField(_ scheme: ColorScheme) -> RGBA { scheme == .dark ? RGBA(1, 1, 1, 0.12) : RGBA(0, 0, 0, 0.07) }
}

extension SearchFieldNode {
    func layoutTV(size: CGSize, _ ctx: PlaceContext) {
        if !tvGlassKeys.isEmpty { layoutGlassTV(size: size, ctx); return }
        let leadingInset: CGFloat = 96
        let width = max(0, size.width - leadingInset - 30)
        let s = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        label.place(at: CGPoint(x: leadingInset, y: (size.height - s.height) / 2), size: CGSize(width: min(width, s.width), height: s.height), ctx)
    }

    private func layoutGlassTV(size: CGSize, _ ctx: PlaceContext) {
        let rowH: CGFloat = 70
        let s = label.sizeThatFits(.unspecified)
        label.place(at: CGPoint(x: TVMetrics.glassPromptX, y: (rowH - s.height) / 2), size: s, ctx)
        // Hint, right-aligned on the prompt row.
        let hintSizes = tvGlassHint.map { $0.sizeThatFits(.unspecified) }
        var hx = size.width - hintSizes.reduce(0) { $0 + $1.width } - CGFloat(max(0, hintSizes.count - 1)) * 10
        for (node, hs) in zip(tvGlassHint, hintSizes) {
            node.place(at: CGPoint(x: hx, y: rowH / 2 - hs.height / 2), size: hs, ctx)
            hx += hs.width + 10
        }
        // Keys: 123 and SPACE badges, the letters, delete.
        let midY = TVMetrics.glassKeyRowTop + TVMetrics.glassKeyHeight / 2
        let cells: [CGFloat] = [37, 126] + (0..<26).map { TVMetrics.glassFirstLetterX + CGFloat($0) * TVMetrics.glassKeyPitch } + [1649]
        let widths: [CGFloat] = [89, 119] + Array(repeating: TVMetrics.glassKeyPitch, count: 26) + [74]
        tvGlassKeyCells = []
        for (i, key) in tvGlassKeys.enumerated() where i < cells.count {
            let cell = CGRect(x: cells[i], y: TVMetrics.glassKeyRowTop, width: widths[i], height: TVMetrics.glassKeyHeight)
            tvGlassKeyCells.append(cell)
            let ks = key.sizeThatFits(.unspecified)
            key.place(at: CGPoint(x: cell.midX - ks.width / 2, y: midY - ks.height / 2), size: ks, ctx)
        }
    }

    private func drawGlassTV(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let dim = TVColors.dimmedTitle(tvScheme)
        // Magnifying glass, 52 pt wide, before the prompt.
        let r: CGFloat = 21, c = CGPoint(x: 50, y: 30)
        var lens = Path()
        lens.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        p.stroke(lens, with: .color(dim), style: StrokeStyle(lineWidth: 6), in: bounds)
        var handle = Path()
        let d = r / 2.squareRoot()
        handle.move(to: CGPoint(x: c.x + d, y: c.y + d))
        handle.addLine(to: CGPoint(x: c.x + d + 15, y: c.y + d + 15))
        p.stroke(handle, with: .color(dim), style: StrokeStyle(lineWidth: 6, lineCap: .round), in: bounds)
        label.draw(p)
        for node in tvGlassHint { node.draw(p) }
        // The 123 and SPACE badges.
        for i in 0..<min(2, tvGlassKeyCells.count) {
            let key = tvGlassKeys[i].frame.insetBy(dx: -12, dy: -6)
            p.fill(Path(roundedRect: key, cornerRadius: 6, style: .continuous), with: .color(TVColors.glassKeyBadge(tvScheme)), in: key)
        }
        // The focused key ("a" while the keyboard has focus): white, 70 x 80.
        if tvFocused, tvGlassKeyCells.count > 2 {
            let cell = tvGlassKeyCells[2]
            let key = CGRect(x: cell.midX - 35, y: cell.midY - 40, width: 70, height: 80)
            p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, 0.2), radius: 12, x: 0, y: 6, scale: p.scale)))
            p.fill(Path(roundedRect: key, cornerRadius: 14, style: .continuous), with: .color(TVColors.focusedPlatter), in: key)
            p.restore()
        }
        for key in tvGlassKeys { key.draw(p) }
        // Hairline between the keyboard and the results.
        let line = CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)
        p.fill(Path(line), with: .color(tvScheme == .dark ? RGBA(1, 1, 1, 0.2) : RGBA(0, 0, 0, 0.2)), in: line)
    }

    func drawTV(_ p: Painter) {
        if !tvGlassKeys.isEmpty { drawGlassTV(p); return }
        let bounds = CGRect(origin: .zero, size: frame.size)
        let scheme = tvScheme
        let path = Path(roundedRect: bounds, cornerRadius: bounds.height / 2, style: .circular)
        p.save()
        if tvFocused {
            let s = TVMetrics.rowLiftScale
            p.translate(bounds.midX, bounds.midY); p.scale(s, s); p.translate(-bounds.midX, -bounds.midY)
            p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, 0.3), radius: 24, x: 0, y: 12, scale: p.scale)))
            p.fill(path, with: .color(TVColors.focusedPlatter), in: bounds)
            p.restore()
        } else {
            p.fill(path, with: .color(TVColors.searchField(scheme)), in: bounds)
        }
        // Magnifying glass.
        let r: CGFloat = 15, c = CGPoint(x: 50, y: bounds.midY - 3)
        let tint: _Paint = tvFocused ? .color(RGBA(0, 0, 0, 0.5)) : glass
        var lens = Path()
        lens.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        p.stroke(lens, with: tint, style: StrokeStyle(lineWidth: 4.5), in: bounds)
        var handle = Path()
        let d = r / 2.squareRoot()
        handle.move(to: CGPoint(x: c.x + d, y: c.y + d))
        handle.addLine(to: CGPoint(x: c.x + d + 11, y: c.y + d + 11))
        p.stroke(handle, with: tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round), in: bounds)
        label.draw(p)
        p.restore()
    }
}
