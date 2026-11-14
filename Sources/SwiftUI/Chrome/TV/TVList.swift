// tvOS List / Form: full-width rows with no card background and no separators. A row holding one
// focusable control is that control (as the focus engine already treats it); while it has focus the row
// is a raised white platter with dark content (HIG Lists and tables, tvOS: "each row highlights and
// slightly increases in size when it becomes focused. A focused row's corners can also become rounded").
// Sizes are estimates (TVMetrics). Lists take the full width they are given: tvOS Settings-style
// half-width layouts are an app's own layout, not a List default.

extension ListNode {
    static func markTVFocus(_ rows: [ListRowNode], glass: Bool) {
        let focused = Runtime.current?.focus.focusedPath
        for row in rows {
            row.tvRow = true
            row.tvGlass = glass
            let elements = row.containsFocusElements()
            guard elements.count == 1, let element = elements.first else { continue }
            row.tvSingleElement = true
            row.tvFocused = element.path == focused && element.isEnabled && !element.effectDisabled
        }
    }

    func layoutTV(size: CGSize, _ ctx: PlaceContext) {
        var inner = ctx
        let unbounded = CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
        inner.container = unbounded
        inner.safeRect = unbounded
        let scrollOffset = scrollIdentity.flatMap { Runtime.current?.focus.scrollOffsets[$0]?.y } ?? 0
        let x0 = max(0, ctx.safeRect.minX - ctx.origin.x)
        let x1 = min(size.width, ctx.safeRect.maxX - ctx.origin.x)
        let width = max(0, x1 - x0)
        let textInset = design.rowInsetHorizontal
        var y = max(0, ctx.safeRect.minY - ctx.origin.y) - scrollOffset
        for (index, section) in sections.enumerated() {
            if index > 0 { y += section.spacing?.value ?? listSectionSpacing.value ?? TVMetrics.sectionSpacing }
            if let header = section.header {
                let h = header.sizeThatFits(ProposedViewSize(width: width - textInset * 2, height: nil))
                header.place(at: CGPoint(x: x0 + textInset, y: y), size: h, inner)
                y += h.height + design.headerBaselineToCard
            }
            for (i, row) in section.rows.enumerated() {
                if i > 0 { y += rowSpacing ?? TVMetrics.rowSpacing }
                let s = row.sizeThatFits(ProposedViewSize(width: width, height: nil))
                row.place(at: CGPoint(x: x0, y: y), size: s, inner)
                y += s.height
            }
            if let footer = section.footer {
                y += 12
                let f = footer.sizeThatFits(ProposedViewSize(width: width - textInset * 2, height: nil))
                footer.place(at: CGPoint(x: x0 + textInset, y: y), size: f, inner)
                y += f.height
            }
        }
        contentHeight = y + scrollOffset + TVMetrics.sectionSpacing + max(0, ctx.origin.y + size.height - ctx.safeRect.maxY)
    }
}

extension ListRowNode {
    func drawTV(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let radius = tvGlass ? 22 : TVMetrics.rowCornerRadius
        p.save()
        if tvFocused {
            let s = TVMetrics.rowLiftScale
            p.translate(bounds.midX, bounds.midY); p.scale(s, s); p.translate(-bounds.midX, -bounds.midY)
            let path = Path(roundedRect: bounds, cornerRadius: radius, style: .continuous)
            p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, TVMetrics.liftShadowOpacity * 0.8),
                                                                radius: 24, x: 0, y: 12, scale: p.scale)))
            p.fill(path, with: .color(TVColors.focusedPlatter), in: bounds)
            p.restore()
        }
        drawChildren(p)
        if hasChevron {
            let w = TVMetrics.chevronSize.width, h = TVMetrics.chevronSize.height
            let right = frame.width - insets.trailing
            var path = Path()
            path.move(to: CGPoint(x: right - w, y: bounds.midY - h / 2))
            path.addLine(to: CGPoint(x: right, y: bounds.midY))
            path.addLine(to: CGPoint(x: right - w, y: bounds.midY + h / 2))
            p.stroke(path, with: tvFocused ? .color(RGBA(0, 0, 0, 0.45)) : chevronPaint,
                     style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round), in: bounds)
        }
        p.restore()
    }
}
