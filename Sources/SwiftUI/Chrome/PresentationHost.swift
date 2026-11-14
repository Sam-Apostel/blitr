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

    /// Liquid Glass sheets (iOS 26+). Values marked (est.) are estimates kept here for calibration.
    struct Glass {
        /// Below the large detent the sheet floats: inset from the screen's sides and bottom.
        var floatingInset: CGFloat = 8              // (est.)
        /// Floating corners are concentric with the display corners, but never tighter than this.
        var floatingMinCornerRadius: CGFloat = 34   // (est.)
        /// Large detent (attached, opaque) and iPad form sheet.
        var largeCornerRadius: CGFloat = 38         // (est.)
        var formSheetCornerRadius: CGFloat = 38     // (est.)
        /// The floating sheet's glass is more opaque than a bar's, so content stays legible.
        var tintLight = RGBA(1, 1, 1, 0.72)         // (est.)
        var tintDark = RGBA(0.11, 0.11, 0.12, 0.72) // (est.)

        /// Radius of a floating card: the display radius less the inset.
        func floatingCornerRadius() -> CGFloat {
            max(floatingMinCornerRadius, _currentConfiguration().device.cornerRadius - floatingInset)
        }
        func appearance(_ scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
            var a = GlassAppearance.system(.regular, scheme: scheme, design: design)
            a.tint = scheme == .dark ? tintDark : tintLight
            return a
        }
    }
    static func forDesign(_ design: DesignLanguage) -> Glass { Glass() }
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

    /// Liquid Glass alert (iOS 26+). Values marked (est.) are estimates kept here for calibration.
    struct Glass {
        var width: CGFloat = 300                    // (est.)
        var cornerRadius: CGFloat = 34              // (est.)
        /// Padding around the title and message.
        var textPadding: CGFloat = 24               // (est.)
        var titleMessageSpacing: CGFloat = 6        // (est.)
        var titleFontSize: CGFloat = 17
        var messageFontSize: CGFloat = 15
        /// Space between the text and the buttons.
        var textToButtons: CGFloat = 20             // (est.)
        /// Buttons: inset from the card edges so the capsules sit concentric in the corners.
        var buttonInset: CGFloat = 14               // (est.; brief said ~24 for all padding)
        var buttonHeight: CGFloat = 48              // (est.)
        var buttonGap: CGFloat = 8                  // (est.)
        var buttonFontSize: CGFloat = 17
        var buttonTextPadding: CGFloat = 10
        var buttonFill = SystemColor.fill
        var tintLight = RGBA(1, 1, 1, 0.7)          // (est.)
        var tintDark = RGBA(0.13, 0.13, 0.14, 0.7)  // (est.)

        func appearance(_ scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
            var a = GlassAppearance.system(.regular, scheme: scheme, design: design)
            a.tint = scheme == .dark ? tintDark : tintLight
            return a
        }
    }
    static func forDesign(_ design: DesignLanguage) -> Glass { Glass() }
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

    /// Liquid Glass confirmation dialog (iOS 26+): one glass card at the bottom. (est.) throughout.
    struct Glass {
        /// Inset from the screen's sides and bottom, as a floating sheet.
        var inset: CGFloat = 8
        var headerFontSize: CGFloat = 13
        var headerPaddingTop: CGFloat = 18
        var headerPaddingBottom: CGFloat = 14
        var headerPaddingSide: CGFloat = 24
        var titleMessageSpacing: CGFloat = 3
        var rowHeight: CGFloat = 56
        var actionFontSize: CGFloat = 17
        /// Hairlines between rows are inset this far from the card's sides.
        var separatorInset: CGFloat = 20
        /// How far the last row may reach into the bottom safe area (the home indicator stays below its label).
        var homeIndicatorOverlap: CGFloat = 14
        var cornerRadius: CGFloat { SheetMetrics.forDesign(.liquidGlass26).floatingCornerRadius() }
    }
    static func forDesign(_ design: DesignLanguage) -> Glass { Glass() }
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
        let layer = makeLayerNode(record)
        layer.dismiss = record.dismiss
        return layer
    }

    private static func makeLayerNode(_ record: PresentationRecord) -> PresentationLayerNode {
        if record.ctx.env.renderPlatform == .tvOS { return makeTVLayerNode(record) }
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
    /// Ends this presentation (remote Menu, alert buttons).
    var dismiss: (@MainActor () -> Void)?
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
    /// Glass, below the large detent: a card inset from the screen edges with glass behind the content.
    private(set) var isFloating = false
    private var isLarge = false

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
        self.isLarge = isLarge
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

        isFloating = env.designLanguage.isGlass && !isLarge
        var safeInsets = EdgeInsets(top: 0, leading: deviceInsets.leading, bottom: deviceInsets.bottom, trailing: deviceInsets.trailing)
        if isFloating {
            let inset = SheetMetrics.forDesign(env.designLanguage).floatingInset
            cardRect = CGRect(x: inset, y: cardTop, width: size.width - inset * 2, height: max(0, size.height - inset - cardTop))
            // The device's insets, measured from the card's edges instead of the screen's.
            safeInsets = EdgeInsets(top: 0, leading: max(0, deviceInsets.leading - inset), bottom: max(0, deviceInsets.bottom - inset),
                                    trailing: max(0, deviceInsets.trailing - inset))
        } else {
            cardRect = CGRect(x: 0, y: cardTop, width: size.width, height: size.height - cardTop)
        }
        let absCard = cardRect.offsetBy(dx: ctx.origin.x, dy: ctx.origin.y)
        var inner = ctx
        inner.container = absCard
        inner.safeRect = absCard.inset(by: safeInsets)
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
        let design = env.designLanguage
        let glass = SheetMetrics.forDesign(design)
        let defaultRadius: CGFloat
        if !design.isGlass {
            defaultRadius = isFormSheet ? SheetMetrics.formSheetCornerRadius : SheetMetrics.cornerRadius
        } else if isFormSheet {
            defaultRadius = glass.formSheetCornerRadius
        } else {
            defaultRadius = isFloating ? glass.floatingCornerRadius() : glass.largeCornerRadius
        }
        let radius = options.cornerRadius ?? defaultRadius
        let allCorners = isFormSheet || isFloating
        let shape = allCorners ? Path(roundedRect: cardRect, cornerRadius: radius, style: .continuous)
            : Path(roundedRect: cardRect, cornerRadii: RectangleCornerRadii(topLeading: radius, topTrailing: radius), style: .continuous)
        let glassBackground = isFloating && options.backgroundNode == nil && options.backgroundPaint == nil
        if glassBackground {
            // The dimmed presenter has been drawn: the glass refracts it.
            p.fillGlass(.roundedRect(cardRect, radius: min(radius, min(cardRect.width, cardRect.height) / 2)),
                        appearance: glass.appearance(env.colorScheme, design: design))
        }
        p.save()
        p.clip(shape)
        if let bg = options.backgroundNode {
            bg.draw(p)
        } else if glassBackground {
            // drawn above
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
    /// tvOS `.sheet`: drawn over a blurred, dimmed copy of the presenter instead of an opaque background.
    var tvSheet = false
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
        if tvSheet {
            drawPresentationMaterial(p, Path(rect), tint: background.opacity(0.72))
        } else {
            p.fill(Path(rect), with: .color(background), in: rect)
        }
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
        if card is TVAlertCardNode { card.place(at: .zero, size: size, ctx); return }
        if atBottom, let dialog = card as? DialogCardNode, dialog.design.isGlass {
            // Glass: inset from the screen edges like a floating sheet.
            let inset = DialogMetrics.forDesign(dialog.design).inset
            let left = max(inset, deviceInsets.leading), right = max(inset, deviceInsets.trailing)
            dialog.bottomPadding = max(0, deviceInsets.bottom - inset - DialogMetrics.forDesign(dialog.design).homeIndicatorOverlap)
            let c = card.sizeThatFits(ProposedViewSize(width: size.width - left - right, height: nil))
            card.place(at: CGPoint(x: left, y: size.height - inset - c.height), size: c, ctx)
            return
        }
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
        @MainActor func activation(_ node: Node) -> (@MainActor () -> Void)? {
            if let a = node.ax?.info.activate { return a }
            for child in node.children { if let a = activation(child) { return a } }
            return nil
        }
        return PresentationAction(title: text.runs.map(\.text).joined(), role: role(node), activate: activation(node))
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
private func resolveDialogText(_ resolver: NodeResolver?, _ ctx: ResolveContext, size: CGFloat, weight: Font.Weight, color: RGBA,
                               alignment: TextAlignment = .center, spacing: CGFloat = AlertMetrics.titleMessageSpacing) -> Node? {
    guard let resolver else { return nil }
    let nodes = resolver(ctx.with {
        $0.font = .system(size: size, weight: weight)
        $0.multilineTextAlignment = alignment
        $0.foregroundStyle = AnyShapeStyle(Color(color))
        $0.foregroundStyleLevels = nil
        $0.textCase = nil
        $0.stackAxis = nil
    })
    if nodes.isEmpty { return nil }
    let stackAlignment: HorizontalAlignment = alignment == .leading ? .leading : .center
    return nodes.count == 1 ? nodes[0] : StackNode(axis: .vertical, alignment: stackAlignment.key, spacing: spacing, children: nodes)
}

final class AlertCardNode: Node {
    let title: Node?
    let message: Node?
    let actions: [TextNode]
    /// Each action's closure, in the order of `actions` (remote `select`).
    let actionHandlers: [(@MainActor () -> Void)?]
    let separatorColor: RGBA
    let background: RGBA
    let design: DesignLanguage
    private let scheme: ColorScheme
    private var horizontalActions = false
    private var hairlines: [CGRect] = []
    /// The cancel action is stored last (its place when stacked).
    private var cancelIsLast = false
    /// Glass only: each action's capsule (local coordinates, same order as `actions`). Nil for the flat alert.
    private(set) var glassActionCells: [CGRect]?

    init(spec: DialogSpec, ctx: ResolveContext) {
        let env = ctx.env
        let scheme = env.colorScheme
        self.scheme = scheme
        let design = env.designLanguage
        self.design = design
        let label = SystemColor.label.resolve(scheme)
        if design.isGlass {
            let g = AlertMetrics.forDesign(design)
            title = spec.title.map { t in
                resolveDialogText(nodeResolver(t), ctx.child("title"), size: g.titleFontSize, weight: .semibold, color: label, alignment: .leading)
            } ?? nil
            message = resolveDialogText(spec.message, ctx.child("message"), size: g.messageFontSize, weight: .regular,
                                        color: SystemColor.secondaryLabel.resolve(scheme), alignment: .leading)
        } else {
            title = spec.title.map { t in
                resolveDialogText(nodeResolver(t), ctx.child("title"), size: AlertMetrics.titleFontSize, weight: .semibold, color: label)
            } ?? nil
            message = resolveDialogText(spec.message, ctx.child("message"), size: AlertMetrics.messageFontSize, weight: .regular, color: label)
        }
        var list = presentationActions(spec, ctx)
        if list.isEmpty { list = [PresentationAction(title: "OK", role: nil)] }
        // UIKit puts the cancel action leftmost when side by side, last when stacked.
        if let cancel = list.firstIndex(where: { $0.role == .cancel }) {
            list.append(list.remove(at: cancel))
            cancelIsLast = true
        }
        let accent = Color.accentColor.rgba(in: env)
        let fontSize = design.isGlass ? AlertMetrics.forDesign(design).buttonFontSize : AlertMetrics.actionFontSize
        actionHandlers = list.map(\.activate)
        actions = list.map { action in
            textNode(action.title, size: fontSize, weight: action.role == .cancel ? .semibold : .regular,
                     color: action.role == .destructive ? SystemColor.red.resolve(scheme) : accent, env: env)
        }
        separatorColor = SystemColor.separator.resolve(scheme)
        background = scheme == .dark ? AlertMetrics.backgroundDark : AlertMetrics.backgroundLight
        super.init(children: [title, message].compactMap { $0 } + actions)
    }

    private var width: CGFloat { design.isGlass ? AlertMetrics.forDesign(design).width : AlertMetrics.width }
    private var textWidth: CGFloat {
        design.isGlass ? width - AlertMetrics.forDesign(design).textPadding * 2 : AlertMetrics.width - AlertMetrics.paddingSide * 2
    }

    private func textHeight() -> CGFloat {
        let spacing = design.isGlass ? AlertMetrics.forDesign(design).titleMessageSpacing : AlertMetrics.titleMessageSpacing
        var h: CGFloat = 0
        if let title { h += title.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height }
        if let message {
            if title != nil { h += spacing }
            h += message.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height
        }
        return h
    }

    private func headerHeight() -> CGFloat {
        if design.isGlass {
            let g = AlertMetrics.forDesign(design)
            return g.textPadding + textHeight() + g.textToButtons
        }
        return AlertMetrics.paddingTop + AlertMetrics.paddingBottom + textHeight()
    }

    private func fitsSideBySide() -> Bool {
        guard actions.count == 2 else { return false }
        let half: CGFloat
        if design.isGlass {
            let g = AlertMetrics.forDesign(design)
            half = (width - g.buttonInset * 2 - g.buttonGap) / 2 - g.buttonTextPadding * 2
        } else {
            half = AlertMetrics.width / 2 - AlertMetrics.actionTextPadding * 2
        }
        return actions.allSatisfy { $0.sizeThatFits(.unspecified).width <= half }
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let rows = CGFloat(fitsSideBySide() ? 1 : actions.count)
        if design.isGlass {
            let g = AlertMetrics.forDesign(design)
            return CGSize(width: width, height: headerHeight() + rows * g.buttonHeight + (rows - 1) * g.buttonGap + g.buttonInset)
        }
        return CGSize(width: AlertMetrics.width, height: headerHeight() + rows * AlertMetrics.actionHeight)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        if design.isGlass { layoutGlass(size: size, ctx); return }
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

    /// Glass: leading-aligned text, then capsule buttons side by side (two) or stacked.
    private func layoutGlass(size: CGSize, _ ctx: PlaceContext) {
        let g = AlertMetrics.forDesign(design)
        var y = g.textPadding
        if let title {
            let s = title.sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            title.place(at: CGPoint(x: g.textPadding, y: y), size: s, ctx)
            y += s.height
        }
        if let message {
            if title != nil { y += g.titleMessageSpacing }
            let s = message.sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            message.place(at: CGPoint(x: g.textPadding, y: y), size: s, ctx)
            y += s.height
        }
        y = headerHeight()
        horizontalActions = fitsSideBySide()
        let inner = size.width - g.buttonInset * 2
        var cells: [CGRect] = []
        for (i, action) in actions.enumerated() {
            let cell: CGRect
            if horizontalActions {
                let column = cancelIsLast ? 1 - i : i
                let w = (inner - g.buttonGap) / 2
                cell = CGRect(x: g.buttonInset + CGFloat(column) * (w + g.buttonGap), y: y, width: w, height: g.buttonHeight)
            } else {
                cell = CGRect(x: g.buttonInset, y: y + CGFloat(i) * (g.buttonHeight + g.buttonGap), width: inner, height: g.buttonHeight)
            }
            cells.append(cell)
            let s = action.sizeThatFits(ProposedViewSize(width: cell.width - g.buttonTextPadding * 2, height: nil))
            action.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
        }
        glassActionCells = cells
    }

    override func drawContent(_ p: Painter) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        if design.isGlass, let cells = glassActionCells {
            let g = AlertMetrics.forDesign(design)
            p.fillGlass(.roundedRect(bounds, radius: g.cornerRadius), appearance: g.appearance(scheme, design: design))
            let fill = _Paint.color(g.buttonFill.resolve(scheme))
            for cell in cells { p.fill(Path(roundedRect: cell, cornerRadius: cell.height / 2, style: .circular), with: fill, in: cell) }
            drawChildren(p)
            return
        }
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
    /// Each action's closure, in the order `actions + [cancel]` (remote `select`).
    let actionHandlers: [(@MainActor () -> Void)?]
    let separatorColor: RGBA
    let background: RGBA
    let cancelBackground: RGBA
    let design: DesignLanguage
    private let scheme: ColorScheme
    private var groupRect = CGRect.zero
    private var cancelRect = CGRect.zero
    private var hairlines: [CGRect] = []
    /// Glass only: room kept below the last row so it clears the home indicator.
    var bottomPadding: CGFloat = 0
    /// Glass only: each row (local coordinates), in the order `actions + [cancel]`. Nil for the flat dialog.
    private(set) var glassActionCells: [CGRect]?

    init(spec: DialogSpec, ctx: ResolveContext) {
        let env = ctx.env
        let scheme = env.colorScheme
        self.scheme = scheme
        let design = env.designLanguage
        self.design = design
        let glass = DialogMetrics.forDesign(design)
        let secondary = SystemColor.secondaryLabel.resolve(scheme)
        let headerSize = design.isGlass ? glass.headerFontSize : DialogMetrics.headerFontSize
        let actionSize = design.isGlass ? glass.actionFontSize : DialogMetrics.actionFontSize
        title = spec.title.map { t in
            resolveDialogText(nodeResolver(t), ctx.child("title"), size: headerSize, weight: .semibold, color: secondary)
        } ?? nil
        message = resolveDialogText(spec.message, ctx.child("message"), size: headerSize, weight: .regular, color: secondary)
        let list = presentationActions(spec, ctx)
        let accent = Color.accentColor.rgba(in: env)
        actionHandlers = list.filter { $0.role != .cancel }.map(\.activate) + [list.first(where: { $0.role == .cancel })?.activate]
        actions = list.filter { $0.role != .cancel }.map { action in
            textNode(action.title, size: actionSize, weight: .regular,
                     color: action.role == .destructive ? SystemColor.red.resolve(scheme) : accent, env: env)
        }
        cancel = textNode(list.first(where: { $0.role == .cancel })?.title ?? "Cancel", size: actionSize,
                          weight: .semibold, color: accent, env: env)
        separatorColor = SystemColor.separator.resolve(scheme)
        background = scheme == .dark ? AlertMetrics.backgroundDark : AlertMetrics.backgroundLight
        cancelBackground = DialogMetrics.cancelBackground.resolve(scheme)
        super.init(children: [title, message].compactMap { $0 } + actions + [cancel])
    }

    private var hasHeader: Bool { title != nil || message != nil }

    private func headerHeight(_ width: CGFloat) -> CGFloat {
        guard hasHeader else { return 0 }
        let glass = DialogMetrics.forDesign(design)
        let side = design.isGlass ? glass.headerPaddingSide : DialogMetrics.headerPaddingSide
        let w = width - side * 2
        var h = design.isGlass ? glass.headerPaddingTop + glass.headerPaddingBottom : DialogMetrics.headerPaddingTop + DialogMetrics.headerPaddingBottom
        if let title { h += title.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
        if let message {
            if title != nil { h += design.isGlass ? glass.titleMessageSpacing : DialogMetrics.titleMessageSpacing }
            h += message.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        }
        return h
    }

    private func groupHeight(_ width: CGFloat) -> CGFloat {
        headerHeight(width) + CGFloat(actions.count) * DialogMetrics.rowHeight
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width ?? 377
        if design.isGlass {
            return CGSize(width: width, height: headerHeight(width) + CGFloat(actions.count + 1) * DialogMetrics.forDesign(design).rowHeight + bottomPadding)
        }
        let group = groupHeight(width)
        return CGSize(width: width, height: (group > 0 ? group + DialogMetrics.cancelGap : 0) + DialogMetrics.rowHeight)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        if design.isGlass { layoutGlass(size: size, ctx); return }
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

    /// Glass: one card; the header, then a row per action with the cancel action as the last row.
    private func layoutGlass(size: CGSize, _ ctx: PlaceContext) {
        let g = DialogMetrics.forDesign(design)
        let w = size.width - g.headerPaddingSide * 2
        var y = g.headerPaddingTop
        hairlines = []
        if let title {
            let s = title.sizeThatFits(ProposedViewSize(width: w, height: nil))
            title.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        if let message {
            if title != nil { y += g.titleMessageSpacing }
            let s = message.sizeThatFits(ProposedViewSize(width: w, height: nil))
            message.place(at: CGPoint(x: (size.width - s.width) / 2, y: y), size: s, ctx)
            y += s.height
        }
        y = headerHeight(size.width)
        var cells: [CGRect] = []
        for (i, action) in (actions + [cancel]).enumerated() {
            if i > 0 || hasHeader {
                hairlines.append(CGRect(x: g.separatorInset, y: y, width: size.width - g.separatorInset * 2, height: ChromeMetrics.hairline))
            }
            let cell = CGRect(x: 0, y: y, width: size.width, height: g.rowHeight)
            cells.append(cell)
            let s = action.sizeThatFits(ProposedViewSize(width: w, height: nil))
            action.place(at: CGPoint(x: cell.midX - s.width / 2, y: cell.midY - s.height / 2), size: s, ctx)
            y += g.rowHeight
        }
        glassActionCells = cells
    }

    override func drawContent(_ p: Painter) {
        if design.isGlass {
            let g = DialogMetrics.forDesign(design)
            let bounds = CGRect(origin: .zero, size: frame.size)
            p.fillGlass(.roundedRect(bounds, radius: g.cornerRadius),
                        appearance: AlertMetrics.forDesign(design).appearance(scheme, design: design))
            for line in hairlines { p.fill(Path(line), with: .color(separatorColor), in: line) }
            drawChildren(p)
            return
        }
        if groupRect.height > 0 {
            drawPresentationMaterial(p, Path(roundedRect: groupRect, cornerRadius: DialogMetrics.cornerRadius, style: .continuous), tint: background)
            for line in hairlines { p.fill(Path(line), with: .color(separatorColor), in: line) }
        }
        p.fill(Path(roundedRect: cancelRect, cornerRadius: DialogMetrics.cornerRadius, style: .continuous), with: .color(cancelBackground), in: cancelRect)
        drawChildren(p)
    }
}
