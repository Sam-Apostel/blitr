// tvOS NavigationStack: no bar chrome and no back button (the remote's Menu button goes back). The title
// is centred at the top of the safe area; leading and trailing toolbar items sit beside it as tvOS
// buttons; `searchable` adds the search field of a tvOS search screen below the title. Sizes are
// estimates (TVMetrics). The on-screen keyboard of a search screen is not drawn.

extension TVMetrics {
    static let navigationTitleFont = Font.system(size: 48, weight: .medium)   // est. (title 3 size)
    static let searchFont = Font.system(size: 38, weight: .medium)            // est. (HIG search screen image)
}

extension NavigationStackNode {
    func layoutTV(size: CGSize, _ ctx: PlaceContext) {
        let safe = ctx.safeRect.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        barTop = max(0, safe.minY)
        let hasTitle = inlineTitle != nil || principal != nil
        let barHeight = hasTitle || !leading.isEmpty || !trailing.isEmpty ? TVMetrics.navigationTitleHeight : 0
        var y = barTop + (barVisible ? barHeight : 0)
        if barVisible, let search {
            search.place(at: CGPoint(x: safe.minX, y: y), size: CGSize(width: safe.width, height: TVMetrics.searchFieldHeight), ctx)
            y += TVMetrics.searchFieldHeight + 24
            Runtime.current?.warn("searchable on tvOS: the search field is drawn, the on-screen keyboard of a tvOS search screen is not")
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
            item.place(at: CGPoint(x: x, y: barTop + (barHeight - s.height) / 2), size: s, ctx)
            x += s.width + TVMetrics.toolbarItemSpacing
        }
        let leadingEnd = x
        let sizes = trailing.map { $0.sizeThatFits(proposal) }
        var tx = safe.maxX - sizes.reduce(0) { $0 + $1.width } - CGFloat(max(0, trailing.count - 1)) * TVMetrics.toolbarItemSpacing
        let trailingStart = tx
        for (item, s) in zip(trailing, sizes) {
            item.place(at: CGPoint(x: tx, y: barTop + (barHeight - s.height) / 2), size: s, ctx)
            tx += s.width + TVMetrics.toolbarItemSpacing
        }
        if let center = principal ?? inlineTitle {
            let maxWidth = max(0, min(size.width / 2 - leadingEnd, trailingStart - size.width / 2) * 2 - 40)
            var s = center.sizeThatFits(ProposedViewSize(width: maxWidth, height: barHeight))
            s.width = min(s.width, maxWidth)
            center.place(at: CGPoint(x: size.width / 2 - s.width / 2, y: barTop + (barHeight - s.height) / 2), size: s, ctx)
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
        let leadingInset: CGFloat = 96
        let width = max(0, size.width - leadingInset - 30)
        let s = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        label.place(at: CGPoint(x: leadingInset, y: (size.height - s.height) / 2), size: CGSize(width: min(width, s.width), height: s.height), ctx)
    }

    func drawTV(_ p: Painter) {
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
