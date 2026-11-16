// tvOS List / Form: full-width rows with no card background and no separators. A row holding one
// focusable control is that control (as the focus engine already treats it); while it has focus the row
// is a raised white platter with dark content (HIG Lists and tables, tvOS: "each row highlights and
// slightly increases in size when it becomes focused. A focused row's corners can also become rounded").
// tvOS 26 rows are capsules with a light film, measured on the tvOS 26.5 simulator (TVMetrics). Lists take the
// full width they are given: tvOS Settings-style
// half-width layouts are an app's own layout, not a List default.

extension ListNode {
    static func markTVFocus(_ rows: [ListRowNode], glass: Bool, scheme: ColorScheme) {
        let focused = Runtime.current?.focus.focusedPath
        for row in rows {
            row.tvRow = true
            row.tvGlass = glass
            row.tvScheme = scheme
            let elements = row.containsFocusElements()
            guard elements.count == 1, let element = elements.first else { continue }
            row.tvSingleElement = true
            row.tvFocused = element.path == focused && element.isEnabled && !element.effectDisabled
            if glass && row.tvFocused {
                // tvOS 26: the content keeps its inset from the grown platter, so the label moves 4 pt out to the
                // leading side and the value and chevron 4 pt to the trailing side (measured: tvOS 26.5 simulator,
                // "Account" focused starts at 96.5 against 100.5 unfocused, its chevron 4 pt further right).
                row.insets.leading -= TVMetrics.glassFocusGrowth
                row.insets.trailing -= TVMetrics.glassFocusGrowth
            }
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
                y += TVMetrics.footerTopGap
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
        let radius = tvGlass ? bounds.height / 2 : TVMetrics.rowCornerRadius
        p.save()
        if tvGlass {
            // tvOS 26 (measured: tvOS 26.5): every row is a capsule with a light film; the focused one is white,
            // 4 pt larger on every side, with the focus shadow. The content does not scale.
            let g = tvFocused ? TVMetrics.glassFocusGrowth : 0
            let plate = bounds.insetBy(dx: -g, dy: -g)
            let path = Path(roundedRect: plate, cornerRadius: plate.height / 2, style: .circular)
            if tvFocused {
                let shadow = plate.insetBy(dx: TVMetrics.glassShadowInset, dy: 0).offsetBy(dx: 0, dy: TVMetrics.glassShadowY)
                p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: TVMetrics.glassShadowRadius, scale: p.scale)))
                p.fill(Path(roundedRect: shadow, cornerRadius: shadow.height / 2, style: .circular),
                       with: .color(RGBA(0, 0, 0, TVMetrics.glassShadowOpacity)), in: shadow)
                p.restore()
                p.fill(path, with: .color(TVColors.focusedPlatter), in: plate)
            } else if !tvBare {
                // A plain List's rows have no film (measured: tvOS 26.5 simulator, NavigationLink and Toggle rows
                // of a List show the backdrop until focused).
                p.fill(path, with: .color(TVColors.glassRow(tvScheme)), in: plate)
            }
        } else if tvFocused {
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
            let right = frame.width - insets.trailing - (tvGlass ? TVMetrics.glassChevronInset : 0)
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
