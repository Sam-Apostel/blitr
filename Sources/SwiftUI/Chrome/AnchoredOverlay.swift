// A view drawn next to another without taking part in layout, kept inside the screen: what a popover
// that does not adapt to a sheet looks like (TipKit's `popoverTip`). Shim modules build on it.

/// `content`, with `overlay` placed against `edge` of it (below for `.bottom`), centred on it and moved
/// back inside the screen. The overlay is proposed `width` (or its ideal width) and its ideal height.
package struct _AnchoredOverlay<Content: View, Overlay: View>: View, PrimitiveView {
    package typealias Body = Never
    let content: Content
    let overlay: Overlay
    let edge: Edge
    let width: CGFloat?
    let gap: CGFloat
    let margin: CGFloat
    let arrow: AnyShapeStyle?

    /// `arrow`: the fill of a small arrow drawn in the gap, pointing from the overlay at the content's centre.
    package init(content: Content, overlay: Overlay, edge: Edge, width: CGFloat?, gap: CGFloat = 0, margin: CGFloat = 16,
                 arrow: AnyShapeStyle? = nil) {
        self.arrow = arrow
        self.content = content
        self.overlay = overlay
        self.edge = edge
        self.width = width
        self.gap = gap
        self.margin = margin
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let anchor = resolveSingle(content, ctx.child("content"))
        let attached = resolveSingle(overlay, ctx.child("overlay"))
        let node = AnchoredOverlayNode(anchor: anchor, overlay: attached, edge: edge, width: width, gap: gap, margin: margin)
        node.arrowPaint = arrow?._paint(in: ctx.env)
        out.append(node)
    }
}

final class AnchoredOverlayNode: WrapperNode {
    let edge: Edge
    let width: CGFloat?
    let gap: CGFloat
    let margin: CGFloat
    var arrowPaint: _Paint?
    private var arrowPath: Path?

    init(anchor: Node, overlay: Node, edge: Edge, width: CGFloat?, gap: CGFloat, margin: CGFloat) {
        self.edge = edge
        self.width = width
        self.gap = gap
        self.margin = margin
        super.init(child: anchor)
        children.append(overlay)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        child.place(at: .zero, size: size, ctx)
        let overlay = children[1]
        let available = ctx.container.width - 2 * margin
        let proposedWidth = min(width ?? overlay.sizeThatFits(.unspecified).width, available)
        let s = overlay.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
        // Absolute frame of the anchor, to keep the overlay on screen.
        let anchorX = ctx.origin.x
        var x: CGFloat, y: CGFloat
        switch edge {
        case .bottom, .top:
            x = (size.width - s.width) / 2
            y = edge == .bottom ? size.height + gap : -s.height - gap
            let minX = ctx.container.minX + margin - anchorX, maxX = ctx.container.maxX - margin - s.width - anchorX
            x = min(max(x, minX), max(minX, maxX))
        case .leading, .trailing:
            x = edge == .trailing ? size.width + gap : -s.width - gap
            y = (size.height - s.height) / 2
        }
        overlay.place(at: CGPoint(x: x, y: y), size: s, ctx)
        arrowPath = nil
        guard arrowPaint != nil, gap > 0 else { return }
        var p = Path()
        let half = gap
        switch edge {
        case .bottom:
            p.move(to: CGPoint(x: size.width / 2 - half, y: y + 1)); p.addLine(to: CGPoint(x: size.width / 2, y: y - gap + 1))
            p.addLine(to: CGPoint(x: size.width / 2 + half, y: y + 1))
        case .top:
            let b = y + s.height
            p.move(to: CGPoint(x: size.width / 2 - half, y: b - 1)); p.addLine(to: CGPoint(x: size.width / 2, y: b + gap - 1))
            p.addLine(to: CGPoint(x: size.width / 2 + half, y: b - 1))
        case .trailing:
            p.move(to: CGPoint(x: x + 1, y: size.height / 2 - half)); p.addLine(to: CGPoint(x: x - gap + 1, y: size.height / 2))
            p.addLine(to: CGPoint(x: x + 1, y: size.height / 2 + half))
        case .leading:
            let r = x + s.width
            p.move(to: CGPoint(x: r - 1, y: size.height / 2 - half)); p.addLine(to: CGPoint(x: r + gap - 1, y: size.height / 2))
            p.addLine(to: CGPoint(x: r - 1, y: size.height / 2 + half))
        }
        p.closeSubpath()
        arrowPath = p
    }

    override func drawContent(_ p: Painter) {
        drawChildren(p)
        if let arrowPath, let arrowPaint { p.fill(arrowPath, with: arrowPaint, in: arrowPath.boundingRect) }
    }
}
