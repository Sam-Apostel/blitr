// tvOS alerts and confirmation dialogs.
//
// tvOS 18 and earlier: the whole screen is covered by a dimmed, blurred backdrop; the title and message
// are centred and the actions are full-width platters stacked below them, cancel last (est. sizes).
// tvOS 26/27: a Liquid Glass card in the centre over the screen dimmed by 45% black (measured: tvOS 26.5
// simulator, TVMetrics.glassAlert*): title and message centred, two alert actions side by side with cancel first,
// dialog actions stacked with cancel last. tvOS 18 sizes are estimates.
//
// The focused action is a white, lifted platter; the others are translucent platters.

final class TVAlertCardNode: Node {
    let title: Node?
    let message: Node?
    /// Action titles in focus order (cancel last), their handlers, and their frames after layout.
    let actions: [TextNode]
    let actionHandlers: [(@MainActor () -> Void)?]
    let isDestructive: [Bool]
    private(set) var actionCells: [CGRect] = []
    let focusedIndex: Int?
    let glass: Bool
    let isDialog: Bool
    let scheme: ColorScheme
    let design: DesignLanguage
    private var cardRect = CGRect.zero
    private var sideBySide = false

    init(spec: DialogSpec, ctx: ResolveContext, isDialog: Bool) {
        let env = ctx.env
        scheme = env.colorScheme
        design = env.designLanguage
        let isGlass = env.designLanguage.isGlass
        glass = isGlass
        self.isDialog = isDialog
        var list = presentationActions(spec, ctx)
        if list.isEmpty { list = [PresentationAction(title: "OK", role: nil)] }
        if let cancel = list.firstIndex(where: { $0.role == .cancel }) { list.append(list.remove(at: cancel)) }
        else if isDialog { list.append(PresentationAction(title: "Cancel", role: .cancel)) }
        // tvOS 26: an alert's two actions sit side by side with cancel first, which also has the initial
        // focus (measured: tvOS 26.5).
        if isGlass && !isDialog && list.count == 2, list[1].role == .cancel { list.reverse() }
        let focused = list.indices.first { ctx.runtime.focus.focusedPath == IdentityPath(components: ["chrome", "alertAction", $0]) }
        focusedIndex = focused
        let scheme = env.colorScheme
        func text(_ string: String, font: Font, color: RGBA, align: TextAlignment, onPlatter: Bool = false) -> TextNode {
            var e = env
            e.multilineTextAlignment = align
            e.textCase = nil
            if onPlatter { e.colorScheme = .light }
            return Text(verbatim: string).font(font).foregroundColor(Color(color)).makeNode(e)
        }
        func resolved(_ resolver: NodeResolver?, _ key: String, font: Font, color: RGBA, align: TextAlignment) -> Node? {
            guard let resolver else { return nil }
            let nodes = resolver(ctx.child(key).with {
                $0.font = font
                $0.multilineTextAlignment = align
                $0.foregroundStyle = AnyShapeStyle(Color(color))
                $0.foregroundStyleLevels = nil
                $0.textCase = nil
                $0.stackAxis = nil
            })
            if nodes.isEmpty { return nil }
            return nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: (align == .leading ? HorizontalAlignment.leading : .center).key, spacing: 8, children: nodes)
        }
        let align: TextAlignment = .center
        let label = SystemColor.label.resolve(scheme), secondary = SystemColor.secondaryLabel.resolve(scheme)
        title = spec.title.flatMap { resolved(nodeResolver($0), "title", font: isGlass ? .system(size: 31, weight: .bold) : .system(size: 48, weight: .medium), color: label, align: align) }
        message = resolved(spec.message, "message", font: isGlass ? .system(size: 25) : .system(size: 29), color: isGlass ? label : secondary, align: align)
        actionHandlers = list.map(\.activate)
        isDestructive = list.map { $0.role == .destructive }
        actions = list.enumerated().map { i, action in
            let isFocused = i == focused
            let color: RGBA = action.role == .destructive ? SystemColor.red.resolve(scheme) : (isFocused ? TVColors.focusedLabel : label)
            return text(action.title, font: isGlass ? .body : .system(size: 29, weight: .medium), color: color, align: .center, onPlatter: isFocused)
        }
        super.init(children: [title, message].compactMap { $0 } + actions)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        glass ? layoutCard(size: size, ctx) : layoutFullScreen(size: size, ctx)
    }

    private func layoutFullScreen(size: CGSize, _ ctx: PlaceContext) {
        let textWidth = min(1100, size.width - 320)
        let t = title?.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
        let m = message?.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
        let h = TVMetrics.buttonHeight, gap = TVMetrics.alertButtonSpacing
        let buttonsHeight = CGFloat(actions.count) * h + CGFloat(max(0, actions.count - 1)) * gap
        let textHeight = t.height + (title != nil && message != nil ? 24 : 0) + m.height
        let total = textHeight + 60 + buttonsHeight
        var y = (size.height - total) / 2
        title?.place(at: CGPoint(x: (size.width - t.width) / 2, y: y), size: t, ctx)
        y += t.height + (title != nil && message != nil ? 24 : 0)
        message?.place(at: CGPoint(x: (size.width - m.width) / 2, y: y), size: m, ctx)
        y += m.height + 60
        let w = TVMetrics.alertButtonWidth
        actionCells = []
        for action in actions {
            let cell = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
            actionCells.append(cell)
            let s = action.sizeThatFits(ProposedViewSize(width: w - 40, height: nil))
            action.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
            y += h + gap
        }
        cardRect = CGRect(origin: .zero, size: size)
    }

    private func layoutCard(size: CGSize, _ ctx: PlaceContext) {
        // measured: tvOS 26.5 (TVMetrics.glassAlert*).
        let width = isDialog ? TVMetrics.glassDialogWidth : TVMetrics.glassAlertWidth, pad = TVMetrics.glassAlertPadding
        let inset = TVMetrics.glassAlertButtonInset, h = TVMetrics.glassAlertButtonHeight
        let textWidth = width - inset * 2
        let t = title?.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
        let m = message?.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
        let half = (width - inset * 2 - TVMetrics.glassAlertButtonGap) / 2
        sideBySide = !isDialog && actions.count == 2 && actions.allSatisfy { $0.sizeThatFits(.unspecified).width <= half - 32 }
        let gap = sideBySide ? TVMetrics.glassAlertButtonGap : TVMetrics.glassDialogButtonGap
        let rows = sideBySide ? 1 : actions.count
        let titleGap = title != nil && message != nil ? TVMetrics.glassAlertTitleGap : 0
        let textGap = message == nil && isDialog ? TVMetrics.glassDialogTitleGap : TVMetrics.glassAlertMessageGap
        let textHeight = t.height + titleGap + m.height
        let height = pad + textHeight + textGap + CGFloat(rows) * h + CGFloat(max(0, rows - 1)) * gap + inset
        cardRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        var y = cardRect.minY + pad
        title?.place(at: CGPoint(x: cardRect.midX - t.width / 2, y: y), size: t, ctx)
        y += t.height + titleGap
        message?.place(at: CGPoint(x: cardRect.midX - m.width / 2, y: y), size: m, ctx)
        y += m.height + textGap
        actionCells = []
        for (i, action) in actions.enumerated() {
            let cell: CGRect
            if sideBySide {
                cell = CGRect(x: cardRect.minX + inset + CGFloat(i) * (half + gap), y: y, width: half, height: h)
            } else {
                cell = CGRect(x: cardRect.minX + inset, y: y + CGFloat(i) * (h + gap), width: width - inset * 2, height: h)
            }
            actionCells.append(cell)
            let s = action.sizeThatFits(ProposedViewSize(width: cell.width - 24, height: nil))
            action.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
        }
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        if glass {
            p.fill(Path(bounds), with: .color(RGBA(0, 0, 0, TVMetrics.glassAlertDim)), in: bounds)
            p.fillGlass(.roundedRect(cardRect, radius: TVMetrics.glassAlertCornerRadius), appearance: TVColors.glassCard(scheme, design: design))
        } else {
            // Full-screen backdrop: what is behind, blurred and dimmed.
            drawPresentationMaterial(p, Path(bounds), tint: TVColors.dim(scheme))
        }
        title?.draw(p)
        message?.draw(p)
        for (i, cell) in actionCells.enumerated() {
            let focused = i == focusedIndex
            let radius: CGFloat = glass ? cell.height / 2 : TVMetrics.buttonCornerRadius
            let path = Path(roundedRect: cell, cornerRadius: radius, style: glass ? .circular : .continuous)
            p.save()
            if glass {
                // tvOS 26 (measured): unfocused actions are a dark film (destructive ones red), the focused one
                // white and 4 pt larger with the focus shadow.
                if focused {
                    let g = TVMetrics.glassFocusGrowth
                    let plate = cell.insetBy(dx: -g, dy: -g)
                    let shadow = plate.insetBy(dx: TVMetrics.glassShadowInset, dy: 0).offsetBy(dx: 0, dy: TVMetrics.glassShadowY)
                    p.saveLayer(.init(imageFilter: Painter.blurFilter(radius: TVMetrics.glassShadowRadius, scale: p.scale)))
                    p.fill(Path(roundedRect: shadow, cornerRadius: shadow.height / 2, style: .circular),
                           with: .color(RGBA(0, 0, 0, TVMetrics.glassShadowOpacity)), in: shadow)
                    p.restore()
                    p.fill(Path(roundedRect: plate, cornerRadius: plate.height / 2, style: .circular), with: .color(TVColors.focusedPlatter), in: plate)
                } else {
                    let destructive = isDestructive[i]
                    p.fill(path, with: .color(destructive ? TVColors.glassDestructiveAction : TVColors.glassAction(scheme)), in: cell)
                }
            } else if focused {
                let s = TVMetrics.liftScale
                p.translate(cell.midX, cell.midY); p.scale(s, s); p.translate(-cell.midX, -cell.midY)
                p.saveLayer(.init(imageFilter: Painter.shadowFilter(color: RGBA(0, 0, 0, TVMetrics.liftShadowOpacity), radius: TVMetrics.liftShadowRadius,
                                                                    x: 0, y: TVMetrics.liftShadowY, scale: p.scale)))
                p.fill(path, with: .color(TVColors.focusedPlatter), in: cell)
                p.restore()
            } else {
                p.fill(path, with: .color(TVColors.platter(scheme)), in: cell)
            }
            actions[i].draw(p)
            p.restore()
        }
    }
}

extension PresentationHostNode {
    /// tvOS presentations: alerts and dialogs as above; `.sheet` over a blurred, dimmed presenter (est.:
    /// tvOS sheets are modal and cover the screen); `.fullScreenCover` as on iOS.
    static func makeTVLayerNode(_ record: PresentationRecord) -> PresentationLayerNode {
        func content(_ ctx: ResolveContext) -> Node {
            let nodes = record.content?(ctx) ?? []
            return nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: .center, spacing: nil, children: nodes)
        }
        switch record.style {
        case .sheet:
            let ctx = record.ctx.child("sheet")
            let layer = CoverLayerNode(content: content(ctx), env: ctx.env)
            layer.tvSheet = true
            layer.tvGlassSheet = ctx.env.designLanguage.isGlass
            layer.backdrop = .dim(0)
            return layer
        case .fullScreenCover:
            let ctx = record.ctx.child("cover")
            return CoverLayerNode(content: content(ctx), env: ctx.env)
        case .alert(let spec):
            let layer = DimmedCardLayerNode(card: TVAlertCardNode(spec: spec, ctx: record.ctx.child("alert"), isDialog: false), env: record.ctx.env, atBottom: false)
            layer.backdrop = .dim(0)
            return layer
        case .confirmationDialog(let spec):
            let layer = DimmedCardLayerNode(card: TVAlertCardNode(spec: spec, ctx: record.ctx.child("dialog"), isDialog: true), env: record.ctx.env, atBottom: false)
            layer.backdrop = .dim(0)
            return layer
        }
    }
}
