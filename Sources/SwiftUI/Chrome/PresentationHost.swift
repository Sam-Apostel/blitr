internal import CSkia

// Draws presented sheets, covers, alerts and confirmation dialogs above the root view.
// `Renderer` wraps the resolved root with `PresentationHostNode.wrap(_:_:)`.

enum SheetMetrics {
    /// Large detent: sheet top = top safe-area inset + this.
    static let largeTopOffset: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    /// Pushed-back presenter behind a large sheet.
    static let presenterScale: CGFloat = 0.92
    /// Presenter top edge sits this far above the sheet's top edge.
    static let presenterGapAboveSheet: CGFloat = 10
    static let presenterCornerRadius: CGFloat = 10
    static let presenterDimLight: Double = 0.12
    static let presenterDimDark: Double = 0.25
    /// Dim behind a sheet at a smaller detent.
    static let partialDimLight: Double = 0.2
    static let partialDimDark: Double = 0.4
    static let grabberSize = CGSize(width: 36, height: 5)
    static let grabberTop: CGFloat = 5
    static let elevatedDarkBackground = SystemColor.secondaryBackground   // 1C1C1E
    /// iPad (regular width): a centred form sheet over a dimmed presenter.
    static let formSheetSize = CGSize(width: 540, height: 620)
    static let formSheetCornerRadius: CGFloat = 10
}

enum AlertMetrics {
    static let width: CGFloat = 270
    static let cornerRadius: CGFloat = 14
    static let paddingTop: CGFloat = 19
    static let paddingSide: CGFloat = 16
    static let paddingBottom: CGFloat = 15
    static let titleMessageSpacing: CGFloat = 2
    static let titleFontSize: CGFloat = 17
    static let messageFontSize: CGFloat = 13
    static let actionHeight: CGFloat = 44
    static let actionFontSize: CGFloat = 17
    static let actionTextPadding: CGFloat = 8
    static let dimLight: Double = 0.2
    static let dimDark: Double = 0.48
    static let backgroundLight = RGBA(hex: 0xF2F2F2, alpha: 0.8)
    static let backgroundDark = RGBA(hex: 0x252525, alpha: 0.82)
    static let blurRadius: CGFloat = 30
}

enum DialogMetrics {
    static let sideMargin: CGFloat = 8
    static let bottomMargin: CGFloat = 8
    static let cornerRadius: CGFloat = 13
    static let cancelGap: CGFloat = 8
    static let rowHeight: CGFloat = 57
    static let actionFontSize: CGFloat = 20
    static let headerFontSize: CGFloat = 13
    static let headerPaddingTop: CGFloat = 14
    static let headerPaddingBottom: CGFloat = 14
    static let headerPaddingSide: CGFloat = 16
    static let titleMessageSpacing: CGFloat = 2
    static let cancelBackground = DynamicColor(0xFFFFFF, 0x2C2C2E)
}

// MARK: - Host

final class PresentationHostNode: Node {
    let base: Node
    let layers: [PresentationLayerNode]
    private var containerLocal = CGRect.zero

    init(base: Node, layers: [PresentationLayerNode]) {
        self.base = base
        self.layers = layers
        super.init(children: [base] + layers)
        traits = base.traits
    }

    /// Wraps `root` when anything in it is presented; otherwise returns it unchanged.
    static func wrap(_ root: Node, _ ctx: ResolveContext) -> Node {
        let records = root.preferences[PresentationsKey.self]
        guard !records.isEmpty else { return root }
        var layers: [PresentationLayerNode] = []
        func add(_ record: PresentationRecord) {
            let layer = makeLayer(record)
            layers.append(layer)
            // A presentation's own presentations go above it.
            for nested in layer.nestedRecords { add(nested) }
        }
        for record in records { add(record) }
        return PresentationHostNode(base: root, layers: layers)
    }

    static func makeLayer(_ record: PresentationRecord) -> PresentationLayerNode {
        switch record.style {
        case .sheet:
            let ctx = record.ctx.child("sheet").with { $0.isElevatedPresentation = true }
            return SheetLayerNode(content: resolveContent(record, ctx), env: ctx.env)
        case .fullScreenCover:
            let ctx = record.ctx.child("cover")
            return CoverLayerNode(content: resolveContent(record, ctx), env: ctx.env)
        case .alert(let spec):
            return DimmedCardLayerNode(card: AlertCardNode(spec: spec, ctx: record.ctx.child("alert")), env: record.ctx.env, atBottom: false)
        case .confirmationDialog(let spec):
            return DimmedCardLayerNode(card: DialogCardNode(spec: spec, ctx: record.ctx.child("dialog")), env: record.ctx.env, atBottom: true)
        }
    }

    private static func resolveContent(_ record: PresentationRecord, _ ctx: ResolveContext) -> Node {
        let nodes = record.content?(ctx) ?? []
        if nodes.count == 1 { return nodes[0] }
        return StackNode(axis: .vertical, alignment: .center, spacing: nil, children: nodes)
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { base.sizeThatFits(proposal) }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        base.place(at: .zero, size: size, ctx)
        containerLocal = ctx.container.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        let deviceInsets = EdgeInsets(top: ctx.safeRect.minY - ctx.container.minY, leading: ctx.safeRect.minX - ctx.container.minX,
                                      bottom: ctx.container.maxY - ctx.safeRect.maxY, trailing: ctx.container.maxX - ctx.safeRect.maxX)
        for layer in layers {
            layer.deviceInsets = deviceInsets
            layer.place(at: containerLocal.origin, size: containerLocal.size, ctx)
        }
        // The status bar sits on black above a pushed-back presenter.
        if let top = layers.last(where: { !($0 is DimmedCardLayerNode) }) as? SheetLayerNode, case .pushBack = top.backdrop {
            preferences.set(StatusBarSchemeKey.self, .dark)
        }
    }

    override func drawContent(_ p: Painter) { drawLayer(layers.count - 1, p) }

    private func drawBelow(_ index: Int, _ p: Painter) {
        if index == 0 { base.draw(p) } else { drawLayer(index - 1, p) }
    }

    private func drawLayer(_ index: Int, _ p: Painter) {
        guard index >= 0 else { base.draw(p); return }
        let layer = layers[index]
        let rect = containerLocal
        switch layer.backdrop {
        case .none:
            break
        case .dim(let amount):
            drawBelow(index, p)
            if amount > 0 { p.fill(Path(rect), with: .color(RGBA(0, 0, 0, amount)), in: rect) }
        case .pushBack(let presenterTop, let dim):
            p.fill(Path(rect), with: .color(.black), in: rect)
            let s = SheetMetrics.presenterScale
            p.save()
            p.translate(rect.minX + rect.width * (1 - s) / 2, rect.minY + presenterTop)
            p.scale(s, s)
            p.translate(-rect.minX, -rect.minY)
            let clip = Path(roundedRect: rect, cornerRadius: SheetMetrics.presenterCornerRadius / s, style: .continuous)
            p.clip(clip)
            drawBelow(index, p)
            p.fill(Path(rect), with: .color(RGBA(0, 0, 0, dim)), in: rect)
            p.restore()
        }
        layer.draw(p)
    }
}

/// One presented thing, laid out over the full container.
class PresentationLayerNode: Node {
    enum Backdrop {
        case none
        case dim(Double)
        /// The presenter is scaled back with its top at `presenterTop` (container coordinates).
        case pushBack(presenterTop: CGFloat, dim: Double)
    }
    var backdrop: Backdrop = .none
    var deviceInsets = EdgeInsets()
    var nestedRecords: [PresentationRecord] { [] }
}

// MARK: - Sheet

final class SheetLayerNode: PresentationLayerNode {
    let content: Node
    let options: PresentationOptions
    let env: EnvironmentValues
    private(set) var cardRect = CGRect.zero
    private var showsGrabber = false
    private var isFormSheet = false

    init(content: Node, env: EnvironmentValues) {
        self.content = content
        self.env = env
        self.options = content.preferences[PresentationOptionsKey.self]
        var kids: [Node] = []
        if let bg = options.backgroundNode { kids.append(bg) }
        kids.append(content)
        super.init(children: kids)
    }

    override var nestedRecords: [PresentationRecord] { content.preferences[PresentationsKey.self] }

    private func top(for detent: PresentationDetent, size: CGSize) -> CGFloat {
        let largeTop = deviceInsets.top + SheetMetrics.largeTopOffset
        let maxHeight = size.height - largeTop - deviceInsets.bottom
        let top: CGFloat
        switch detent.kind {
        case .large: top = largeTop
        case .medium: top = size.height / 2
        case .fraction(let f): top = size.height - f * (size.height - largeTop)
        case .height(let h): top = size.height - deviceInsets.bottom - h
        case .custom:
            let context = PresentationDetent.Context(maxDetentValue: maxHeight, environment: env)
            let h = detent.customHeight?(context) ?? maxHeight
            top = size.height - deviceInsets.bottom - h
        }
        return min(max(top, largeTop), size.height)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        isFormSheet = _currentConfiguration().device.idiom == .pad && env.horizontalSizeClass == .regular
        if isFormSheet { layoutFormSheet(size: size, ctx); return }
        let largeTop = deviceInsets.top + SheetMetrics.largeTopOffset
        let detents = options.detents ?? [.large]
        let tops = detents.map { top(for: $0, size: size) }
        var cardTop = tops.max() ?? largeTop  // the smallest detent
        if let selection = options.selection, detents.contains(selection) { cardTop = top(for: selection, size: size) }
        let isLarge = cardTop <= largeTop + 0.5
        showsGrabber = options.dragIndicator == .visible || (options.dragIndicator != .hidden && detents.count > 1)

        let dark = env.colorScheme == .dark
        if isLarge {
            backdrop = .pushBack(presenterTop: cardTop - SheetMetrics.presenterGapAboveSheet,
                                 dim: dark ? SheetMetrics.presenterDimDark : SheetMetrics.presenterDimLight)
        } else {
            var interactive = false
            if case .enabled(let upThrough)? = options.backgroundInteraction?.kind {
                interactive = upThrough.map { cardTop >= top(for: $0, size: size) - 0.5 } ?? true
            }
            backdrop = .dim(interactive ? 0 : (dark ? SheetMetrics.partialDimDark : SheetMetrics.partialDimLight))
        }

        cardRect = CGRect(x: 0, y: cardTop, width: size.width, height: size.height - cardTop)
        let absCard = cardRect.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
        var inner = ctx
        inner.container = absCard
        inner.safeRect = absCard.inset(by: EdgeInsets(top: 0, leading: deviceInsets.leading, bottom: deviceInsets.bottom, trailing: deviceInsets.trailing))
        options.backgroundNode?.place(at: cardRect.origin, size: cardRect.size, inner)
        let safeLocal = inner.safeRect.offsetBy(dx: -ctx.origin.x, dy: -ctx.origin.y)
        let c = content.sizeThatFits(ProposedViewSize(safeLocal.size))
        content.place(at: CGPoint(x: safeLocal.midX - c.width / 2, y: safeLocal.midY - c.height / 2), size: c, inner)
    }

    /// iPad: a form sheet, 540x620 centred, never taller than the screen minus the status bar; detents do not apply.
    private func layoutFormSheet(size: CGSize, _ ctx: PlaceContext) {
        showsGrabber = false
        backdrop = .dim(env.colorScheme == .dark ? SheetMetrics.partialDimDark : SheetMetrics.partialDimLight)
        let fit = CGSize(width: min(SheetMetrics.formSheetSize.width, size.width - 40),
                         height: min(SheetMetrics.formSheetSize.height, size.height - deviceInsets.top - deviceInsets.bottom - 40))
        cardRect = CGRect(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2, width: fit.width, height: fit.height)
        let absCard = cardRect.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
        var inner = ctx
        inner.container = absCard
        inner.safeRect = absCard
        options.backgroundNode?.place(at: cardRect.origin, size: cardRect.size, inner)
        let c = content.sizeThatFits(ProposedViewSize(cardRect.size))
        content.place(at: CGPoint(x: cardRect.midX - c.width / 2, y: cardRect.midY - c.height / 2), size: c, inner)
    }

    override func drawContent(_ p: Painter) {
        let radius = options.cornerRadius ?? (isFormSheet ? SheetMetrics.formSheetCornerRadius : SheetMetrics.cornerRadius)
        let shape = isFormSheet ? Path(roundedRect: cardRect, cornerRadius: radius, style: .continuous)
            : Path(roundedRect: cardRect, cornerRadii: RectangleCornerRadii(topLeading: radius, topTrailing: radius), style: .continuous)
        p.save()
        p.clip(shape)
        if let bg = options.backgroundNode {
            bg.draw(p)
        } else {
            let paint = options.backgroundPaint ?? .color(env.colorScheme == .dark
                ? SheetMetrics.elevatedDarkBackground.resolve(.dark) : SystemColor.background.resolve(.light))
            p.fill(shape, with: paint, in: cardRect)
        }
        content.draw(p)
        p.restore()
        if showsGrabber {
            let g = SheetMetrics.grabberSize
            let r = CGRect(x: cardRect.midX - g.width / 2, y: cardRect.minY + SheetMetrics.grabberTop, width: g.width, height: g.height)
            p.fill(Path(roundedRect: r, cornerRadius: g.height / 2, style: .circular),
                   with: .color(SystemColor.tertiaryLabel.resolve(env.colorScheme)), in: r)
        }
    }
}

// MARK: - Full-screen cover

final class CoverLayerNode: PresentationLayerNode {
    let content: Node
    let background: RGBA
    init(content: Node, env: EnvironmentValues) {
        self.content = content
        background = SystemColor.background.resolve(env.colorScheme)
        super.init(children: [content])
        backdrop = .none
    }
    override var nestedRecords: [PresentationRecord] { content.preferences[PresentationsKey.self] }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let safe = CGRect(origin: .zero, size: size).inset(by: deviceInsets)
        var inner = ctx
        inner.container = CGRect(origin: ctx.origin, size: size)
        inner.safeRect = safe.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
        let c = content.sizeThatFits(ProposedViewSize(safe.size))
        content.place(at: CGPoint(x: safe.midX - c.width / 2, y: safe.midY - c.height / 2), size: c, inner)
    }
    override func drawContent(_ p: Painter) {
        let rect = CGRect(origin: .zero, size: frame.size)
        p.fill(Path(rect), with: .color(background), in: rect)
        content.draw(p)
    }
}

// MARK: - Alert and confirmation dialog

/// Dims what is below and shows a card centred (alert) or at the bottom (dialog).
final class DimmedCardLayerNode: PresentationLayerNode {
    let card: Node
    let atBottom: Bool
    init(card: Node, env: EnvironmentValues, atBottom: Bool) {
        self.card = card
        self.atBottom = atBottom
        super.init(children: [card])
        backdrop = .dim(env.colorScheme == .dark ? AlertMetrics.dimDark : AlertMetrics.dimLight)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let width = atBottom ? size.width - deviceInsets.leading - deviceInsets.trailing - DialogMetrics.sideMargin * 2 : AlertMetrics.width
        let c = card.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let x = atBottom ? deviceInsets.leading + DialogMetrics.sideMargin : (size.width - c.width) / 2
        let y = atBottom ? size.height - deviceInsets.bottom - DialogMetrics.bottomMargin - c.height : (size.height - c.height) / 2
        card.place(at: CGPoint(x: x, y: y), size: c, ctx)
    }
}

/// Fills `path` with a blurred, saturated copy of what is behind it plus a tint.
@MainActor
func drawPresentationMaterial(_ p: Painter, _ path: Path, tint: RGBA) {
    p.save()
    p.clip(path)
    let sigma = Float(AlertMetrics.blurRadius / 2 * p.scale)
    let blur = sk_imagefilter_new_blur(sigma, sigma, CLAMP_SK_SHADER_TILEMODE, nil, nil)
    let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(1.8))
    let backdrop = sk_imagefilter_new_color_filter(saturate, blur, nil)
    sk_colorfilter_unref(saturate)
    sk_imagefilter_unref(blur)
    p.saveLayer(Painter.LayerOptions(backdropFilter: backdrop, bounds: path.boundingRect))
    let bounds = path.boundingRect
    p.fill(Path(bounds), with: .color(tint), in: bounds)
    p.restore()
    p.restore()
}

/// Turns a dialog's actions into titles + roles.
@MainActor
func presentationActions(_ spec: DialogSpec, _ ctx: ResolveContext) -> [PresentationAction] {
    if let fixed = spec.fixedActions { return fixed }
    guard let resolver = spec.actions else { return [] }
    func role(_ node: Node) -> PresentationActionRole? {
        if let r = node.traits[PresentationActionRoleTraitKey.self] { return r }
        for child in node.children { if let r = role(child) { return r } }
        return nil
    }
    return resolver(ctx.child("actions")).compactMap { node in
        guard let text = node.firstDescendant(TextNode.self) else { return nil }
        return PresentationAction(title: text.runs.map(\.text).joined(), role: role(node))
    }
}

@MainActor
private func textNode(_ string: String, size: CGFloat, weight: Font.Weight, color: RGBA, env: EnvironmentValues) -> TextNode {
    var e = env
    e.multilineTextAlignment = .center
    e.textCase = nil
    return Text(verbatim: string).font(.system(size: size, weight: weight)).foregroundColor(Color(color)).makeNode(e)
}

@MainActor
private func resolveDialogText(_ resolver: NodeResolver?, _ ctx: ResolveContext, size: CGFloat, weight: Font.Weight, color: RGBA) -> Node? {
    guard let resolver else { return nil }
    let nodes = resolver(ctx.with {
        $0.font = .system(size: size, weight: weight)
        $0.multilineTextAlignment = .center
        $0.foregroundStyle = AnyShapeStyle(Color(color))
        $0.foregroundStyleLevels = nil
        $0.textCase = nil
        $0.stackAxis = nil
    })
    if nodes.isEmpty { return nil }
    return nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: .center, spacing: AlertMetrics.titleMessageSpacing, children: nodes)
}

final class AlertCardNode: Node {
    let title: Node?
    let message: Node?
    let actions: [TextNode]
    let separatorColor: RGBA
    let background: RGBA
    private var horizontalActions = false
    private var hairlines: [CGRect] = []
    /// The cancel action is stored last (its place when stacked).
    private var cancelIsLast = false

    init(spec: DialogSpec, ctx: ResolveContext) {
        let env = ctx.env
        let scheme = env.colorScheme
        let label = SystemColor.label.resolve(scheme)
        title = spec.title.map { t in
            resolveDialogText(nodeResolver(t), ctx.child("title"), size: AlertMetrics.titleFontSize, weight: .semibold, color: label)
        } ?? nil
        message = resolveDialogText(spec.message, ctx.child("message"), size: AlertMetrics.messageFontSize, weight: .regular, color: label)
        var list = presentationActions(spec, ctx)
        if list.isEmpty { list = [PresentationAction(title: "OK", role: nil)] }
        // UIKit puts the cancel action leftmost when side by side, last when stacked.
        if let cancel = list.firstIndex(where: { $0.role == .cancel }) {
            list.append(list.remove(at: cancel))
            cancelIsLast = true
        }
        let accent = Color.accentColor.rgba(in: env)
        actions = list.map { action in
            textNode(action.title, size: AlertMetrics.actionFontSize, weight: action.role == .cancel ? .semibold : .regular,
                     color: action.role == .destructive ? SystemColor.red.resolve(scheme) : accent, env: env)
        }
        separatorColor = SystemColor.separator.resolve(scheme)
        background = scheme == .dark ? AlertMetrics.backgroundDark : AlertMetrics.backgroundLight
        super.init(children: [title, message].compactMap { $0 } + actions)
    }

    private var textWidth: CGFloat { AlertMetrics.width - AlertMetrics.paddingSide * 2 }

    private func headerHeight() -> CGFloat {
        var h = AlertMetrics.paddingTop + AlertMetrics.paddingBottom
        if let title { h += title.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height }
        if let message {
            if title != nil { h += AlertMetrics.titleMessageSpacing }
            h += message.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height
        }
        return h
    }

    private func fitsSideBySide() -> Bool {
        guard actions.count == 2 else { return false }
        let half = AlertMetrics.width / 2 - AlertMetrics.actionTextPadding * 2
        return actions.allSatisfy { $0.sizeThatFits(.unspecified).width <= half }
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let rows = fitsSideBySide() ? 1 : actions.count
        return CGSize(width: AlertMetrics.width, height: headerHeight() + CGFloat(rows) * AlertMetrics.actionHeight)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        var y = AlertMetrics.paddingTop
        if let title {
            let s = title.sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            title.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        if let message {
            if title != nil { y += AlertMetrics.titleMessageSpacing }
            let s = message.sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            message.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        y += AlertMetrics.paddingBottom
        let t = ChromeMetrics.hairline
        hairlines = [CGRect(x: 0, y: y, width: size.width, height: t)]
        horizontalActions = fitsSideBySide()
        let h = AlertMetrics.actionHeight
        for (i, action) in actions.enumerated() {
            let cell: CGRect
            if horizontalActions {
                // Side by side, UIKit puts the cancel action on the leading side.
                let column = cancelIsLast ? 1 - i : i
                cell = CGRect(x: CGFloat(column) * size.width / 2, y: y, width: size.width / 2, height: h)
                if i == 1 { hairlines.append(CGRect(x: size.width / 2 - t / 2, y: y, width: t, height: h)) }
            } else {
                cell = CGRect(x: 0, y: y + CGFloat(i) * h, width: size.width, height: h)
                if i > 0 { hairlines.append(CGRect(x: 0, y: cell.minY, width: size.width, height: t)) }
            }
            let maxWidth = cell.width - AlertMetrics.actionTextPadding * 2
            let s = action.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            action.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
        }
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        drawPresentationMaterial(p, Path(roundedRect: bounds, cornerRadius: AlertMetrics.cornerRadius, style: .continuous), tint: background)
        for line in hairlines { p.fill(Path(line), with: .color(separatorColor), in: line) }
        drawChildren(p)
    }
}

final class DialogCardNode: Node {
    let title: Node?
    let message: Node?
    let actions: [TextNode]
    let cancel: TextNode
    let separatorColor: RGBA
    let background: RGBA
    let cancelBackground: RGBA
    private var groupRect = CGRect.zero
    private var cancelRect = CGRect.zero
    private var hairlines: [CGRect] = []

    init(spec: DialogSpec, ctx: ResolveContext) {
        let env = ctx.env
        let scheme = env.colorScheme
        let secondary = SystemColor.secondaryLabel.resolve(scheme)
        title = spec.title.map { t in
            resolveDialogText(nodeResolver(t), ctx.child("title"), size: DialogMetrics.headerFontSize, weight: .semibold, color: secondary)
        } ?? nil
        message = resolveDialogText(spec.message, ctx.child("message"), size: DialogMetrics.headerFontSize, weight: .regular, color: secondary)
        let list = presentationActions(spec, ctx)
        let accent = Color.accentColor.rgba(in: env)
        actions = list.filter { $0.role != .cancel }.map { action in
            textNode(action.title, size: DialogMetrics.actionFontSize, weight: .regular,
                     color: action.role == .destructive ? SystemColor.red.resolve(scheme) : accent, env: env)
        }
        cancel = textNode(list.first(where: { $0.role == .cancel })?.title ?? "Cancel", size: DialogMetrics.actionFontSize,
                          weight: .semibold, color: accent, env: env)
        separatorColor = SystemColor.separator.resolve(scheme)
        background = scheme == .dark ? AlertMetrics.backgroundDark : AlertMetrics.backgroundLight
        cancelBackground = DialogMetrics.cancelBackground.resolve(scheme)
        super.init(children: [title, message].compactMap { $0 } + actions + [cancel])
    }

    private var hasHeader: Bool { title != nil || message != nil }

    private func headerHeight(_ width: CGFloat) -> CGFloat {
        guard hasHeader else { return 0 }
        let w = width - DialogMetrics.headerPaddingSide * 2
        var h = DialogMetrics.headerPaddingTop + DialogMetrics.headerPaddingBottom
        if let title { h += title.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
        if let message {
            if title != nil { h += DialogMetrics.titleMessageSpacing }
            h += message.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        }
        return h
    }

    private func groupHeight(_ width: CGFloat) -> CGFloat {
        headerHeight(width) + CGFloat(actions.count) * DialogMetrics.rowHeight
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width ?? 377
        let group = groupHeight(width)
        return CGSize(width: width, height: (group > 0 ? group + DialogMetrics.cancelGap : 0) + DialogMetrics.rowHeight)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let w = size.width - DialogMetrics.headerPaddingSide * 2
        let group = groupHeight(size.width)
        groupRect = CGRect(x: 0, y: 0, width: size.width, height: group)
        var y = DialogMetrics.headerPaddingTop
        hairlines = []
        if let title {
            let s = title.sizeThatFits(ProposedViewSize(width: w, height: nil))
            title.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        if let message {
            if title != nil { y += DialogMetrics.titleMessageSpacing }
            let s = message.sizeThatFits(ProposedViewSize(width: w, height: nil))
            message.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        y = headerHeight(size.width)
        for (i, action) in actions.enumerated() {
            if i > 0 || hasHeader { hairlines.append(CGRect(x: 0, y: y, width: size.width, height: ChromeMetrics.hairline)) }
            let s = action.sizeThatFits(ProposedViewSize(width: w, height: nil))
            action.place(at: CGPoint(x: (size.width - s.width) / 2, y: y + (DialogMetrics.rowHeight - s.height) / 2), size: s, ctx)
            y += DialogMetrics.rowHeight
        }
        cancelRect = CGRect(x: 0, y: size.height - DialogMetrics.rowHeight, width: size.width, height: DialogMetrics.rowHeight)
        let s = cancel.sizeThatFits(ProposedViewSize(width: w, height: nil))
        cancel.place(at: CGPoint(x: cancelRect.midX - s.width / 2, y: cancelRect.midY - s.height / 2), size: s, ctx)
    }

    override func drawContent(_ p: Painter) {
        if groupRect.height > 0 {
            drawPresentationMaterial(p, Path(roundedRect: groupRect, cornerRadius: DialogMetrics.cornerRadius, style: .continuous), tint: background)
            for line in hairlines { p.fill(Path(line), with: .color(separatorColor), in: line) }
        }
        p.fill(Path(roundedRect: cancelRect, cornerRadius: DialogMetrics.cornerRadius, style: .continuous), with: .color(cancelBackground), in: cancelRect)
        drawChildren(p)
    }
}
