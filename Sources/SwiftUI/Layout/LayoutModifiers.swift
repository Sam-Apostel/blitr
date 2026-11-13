// frame, padding, overlay/background, fixedSize, aspectRatio, offset, position.

// MARK: - Fixed frame

final class FrameNode: WrapperNode {
    let width: CGFloat?, height: CGFloat?
    let alignment: Alignment
    init(child: Node, width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width.map { max(0, $0) }
        self.height = height.map { max(0, $0) }
        self.alignment = alignment
        super.init(child: child)
    }
    private func childProposal(_ p: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: width ?? p.width, height: height ?? p.height)
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        if let width, let height { return CGSize(width: width, height: height) }
        let c = child.sizeThatFits(childProposal(proposal))
        return CGSize(width: width ?? c.width, height: height ?? c.height)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = child.sizeThatFits(ProposedViewSize(size))
        placeAligned(child, childSize: c, in: size, alignment: alignment, ctx)
    }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        alignmentThroughFrame(key, size: size, alignment: alignment)
    }
}

extension WrapperNode {
    /// A child's explicit guide, translated through a frame that aligns the child inside `size`.
    func alignmentThroughFrame(_ key: AlignmentKey, size: CGSize, alignment: Alignment) -> CGFloat? {
        let c = child.sizeThatFits(ProposedViewSize(size))
        guard let v = child.explicitAlignment(key, size: c) else { return nil }
        let parent = ViewDimensions(node: nil, size: size)
        if key.axis == .horizontal {
            return v + alignment.horizontal.key.id.defaultValue(in: parent) - child.alignmentValue(alignment.horizontal.key, size: c)
        }
        return v + alignment.vertical.key.id.defaultValue(in: parent) - child.alignmentValue(alignment.vertical.key, size: c)
    }
}

// MARK: - Flexible frame

final class FlexFrameNode: WrapperNode {
    let minW: CGFloat?, idealW: CGFloat?, maxW: CGFloat?, minH: CGFloat?, idealH: CGFloat?, maxH: CGFloat?
    let alignment: Alignment
    init(child: Node, minW: CGFloat?, idealW: CGFloat?, maxW: CGFloat?, minH: CGFloat?, idealH: CGFloat?, maxH: CGFloat?, alignment: Alignment) {
        self.minW = minW; self.idealW = idealW; self.maxW = maxW
        self.minH = minH; self.idealH = idealH; self.maxH = maxH
        self.alignment = alignment
        super.init(child: child)
    }
    private static func clampProposal(_ p: CGFloat?, _ lo: CGFloat?, _ hi: CGFloat?) -> CGFloat? {
        guard var v = p else { return nil }
        if let lo, v < lo { v = lo }
        if let hi, v > hi { v = hi }
        return v
    }
    private static func result(_ childValue: CGFloat, _ proposed: CGFloat?, _ lo: CGFloat?, _ hi: CGFloat?) -> CGFloat {
        var r = childValue
        if let lo { r = max(lo, min(r, proposed ?? r)) }
        if let hi { r = min(hi, max(r, proposed ?? r)) }
        return r
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let pw = FlexFrameNode.clampProposal(proposal.width ?? idealW, minW, maxW)
        let ph = FlexFrameNode.clampProposal(proposal.height ?? idealH, minH, maxH)
        let c = child.sizeThatFits(ProposedViewSize(width: pw, height: ph))
        return CGSize(width: FlexFrameNode.result(c.width, pw, minW, maxW),
                      height: FlexFrameNode.result(c.height, ph, minH, maxH))
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = child.sizeThatFits(ProposedViewSize(size))
        placeAligned(child, childSize: c, in: size, alignment: alignment, ctx)
    }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        alignmentThroughFrame(key, size: size, alignment: alignment)
    }
}

struct FrameModifier: ViewModifier, NodeModifier {
    let width: CGFloat?, height: CGFloat?, alignment: Alignment
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        FrameNode(child: child, width: width, height: height, alignment: alignment)
    }
}

struct FlexFrameModifier: ViewModifier, NodeModifier {
    let minW: CGFloat?, idealW: CGFloat?, maxW: CGFloat?, minH: CGFloat?, idealH: CGFloat?, maxH: CGFloat?, alignment: Alignment
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        FlexFrameNode(child: child, minW: minW, idealW: idealW, maxW: maxW, minH: minH, idealH: idealH, maxH: maxH, alignment: alignment)
    }
}

extension View {
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        modifier(FrameModifier(width: width, height: height, alignment: alignment))
    }
    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> some View { self }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        modifier(FlexFrameModifier(minW: minWidth, idealW: idealWidth, maxW: maxWidth,
                                   minH: minHeight, idealH: idealHeight, maxH: maxHeight, alignment: alignment))
    }
}

// MARK: - Padding

final class PaddingNode: WrapperNode {
    let insets: EdgeInsets
    init(child: Node, insets: EdgeInsets) {
        self.insets = insets
        super.init(child: child)
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        let c = child.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.horizontal) },
                                                    height: proposal.height.map { max(0, $0 - insets.vertical) }))
        return CGSize(width: c.width + insets.horizontal, height: c.height + insets.vertical)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        child.place(at: CGPoint(x: insets.leading, y: insets.top),
                    size: CGSize(width: max(0, size.width - insets.horizontal), height: max(0, size.height - insets.vertical)), ctx)
    }
    override func spacing(_ edge: Edge) -> CGFloat? {
        let amount: CGFloat
        switch edge {
        case .top: amount = insets.top
        case .bottom: amount = insets.bottom
        case .leading: amount = insets.leading
        case .trailing: amount = insets.trailing
        }
        return amount != 0 ? nil : child.spacing(edge)
    }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        let inner = CGSize(width: max(0, size.width - insets.horizontal), height: max(0, size.height - insets.vertical))
        guard let v = child.explicitAlignment(key, size: inner) else { return nil }
        return v + (key.axis == .horizontal ? insets.leading : insets.top)
    }
}

struct PaddingModifier: ViewModifier, NodeModifier {
    var insets: EdgeInsets
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { PaddingNode(child: child, insets: insets) }
}

let defaultPadding: CGFloat = 16

extension View {
    public func padding(_ insets: EdgeInsets) -> some View { modifier(PaddingModifier(insets: insets)) }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        modifier(PaddingModifier(insets: EdgeInsets(edges, length ?? defaultPadding)))
    }
    public func padding(_ length: CGFloat) -> some View { modifier(PaddingModifier(insets: EdgeInsets(all: length))) }
}

// MARK: - Overlay / background

/// A primary child that determines the size, plus a secondary child that is proposed that size.
final class SecondaryNode: Node {
    let alignment: Alignment
    let secondaryInFront: Bool
    var primary: Node { children[0] }
    var secondary: Node { children[1] }
    init(primary: Node, secondary: Node, alignment: Alignment, inFront: Bool) {
        self.alignment = alignment
        self.secondaryInFront = inFront
        super.init(children: [primary, secondary])
        traits = primary.traits
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { primary.sizeThatFits(proposal) }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        primary.place(at: .zero, size: size, ctx)
        let s = secondary.sizeThatFits(ProposedViewSize(size))
        let parent = ViewDimensions(node: primary, size: size)
        let x = parent[alignment.horizontal] - secondary.alignmentValue(alignment.horizontal.key, size: s)
        let y = parent[alignment.vertical] - secondary.alignmentValue(alignment.vertical.key, size: s)
        secondary.place(at: CGPoint(x: x, y: y), size: s, ctx)
    }
    override func spacing(_ edge: Edge) -> CGFloat? { primary.spacing(edge) }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? { primary.explicitAlignment(key, size: size) }
    override func drawContent(_ p: Painter) {
        if secondaryInFront { primary.draw(p); secondary.draw(p) } else { secondary.draw(p); primary.draw(p) }
    }
}

struct SecondaryModifier<Secondary: View>: ViewModifier, PrimitiveModifier {
    let secondary: Secondary
    let alignment: Alignment
    let inFront: Bool
    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        for (i, primary) in content.nodes(ctx).enumerated() {
            let secondaryContext = ctx.child(inFront ? "overlay\(i)" : "background\(i)").with { $0.stackAxis = nil }
            let nodes = resolveNodes(secondary, secondaryContext)
            let node = nodes.count == 1 ? nodes[0] : ZStackNode(alignment: alignment, children: nodes)
            out.append(SecondaryNode(primary: primary, secondary: node, alignment: alignment, inFront: inFront))
        }
    }
}

extension View {
    @_disfavoredOverload
    public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
        modifier(SecondaryModifier(secondary: overlay, alignment: alignment, inFront: true))
    }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        modifier(SecondaryModifier(secondary: content(), alignment: alignment, inFront: true))
    }
    @_disfavoredOverload
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
        modifier(SecondaryModifier(secondary: background, alignment: alignment, inFront: false))
    }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        modifier(SecondaryModifier(secondary: content(), alignment: alignment, inFront: false))
    }
}

// MARK: - fixedSize

final class FixedSizeNode: WrapperNode {
    let horizontal: Bool, vertical: Bool
    init(child: Node, horizontal: Bool, vertical: Bool) {
        self.horizontal = horizontal
        self.vertical = vertical
        super.init(child: child)
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        child.sizeThatFits(ProposedViewSize(width: horizontal ? nil : proposal.width, height: vertical ? nil : proposal.height))
    }
}

struct FixedSizeModifier: ViewModifier, NodeModifier {
    var horizontal: Bool, vertical: Bool
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node {
        FixedSizeNode(child: child, horizontal: horizontal, vertical: vertical)
    }
}

extension View {
    public func fixedSize() -> some View { modifier(FixedSizeModifier(horizontal: true, vertical: true)) }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        modifier(FixedSizeModifier(horizontal: horizontal, vertical: vertical))
    }
}

// MARK: - aspectRatio

final class AspectRatioNode: WrapperNode {
    let ratio: CGFloat?
    let mode: ContentMode
    init(child: Node, ratio: CGFloat?, mode: ContentMode) {
        self.ratio = ratio
        self.mode = mode
        super.init(child: child)
    }
    private func fitted(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let ratio: CGFloat
        if let r = self.ratio { ratio = r } else {
            let ideal = child.sizeThatFits(.unspecified)
            guard ideal.height > 0, ideal.width > 0 else { return proposal }
            ratio = ideal.width / ideal.height
        }
        guard ratio > 0, ratio.isFinite else { return proposal }
        switch (proposal.width, proposal.height) {
        case let (w?, h?):
            guard w.isFinite || h.isFinite else { return proposal }
            let byWidth = CGSize(width: w, height: w / ratio), byHeight = CGSize(width: h * ratio, height: h)
            if !w.isFinite { return ProposedViewSize(byHeight) }
            if !h.isFinite { return ProposedViewSize(byWidth) }
            let useWidth = mode == .fit ? byWidth.height <= h : byWidth.height >= h
            return ProposedViewSize(useWidth ? byWidth : byHeight)
        case let (w?, nil): return ProposedViewSize(width: w, height: w / ratio)
        case let (nil, h?): return ProposedViewSize(width: h * ratio, height: h)
        default:
            let ideal = child.sizeThatFits(.unspecified)
            return ProposedViewSize(width: ideal.width, height: ideal.width / ratio)
        }
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { child.sizeThatFits(fitted(proposal)) }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = child.sizeThatFits(fitted(ProposedViewSize(size)))
        child.place(at: CGPoint(x: (size.width - c.width) / 2, y: (size.height - c.height) / 2), size: c, ctx)
    }
}

struct AspectRatioModifier: ViewModifier, NodeModifier {
    let ratio: CGFloat?, mode: ContentMode
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { AspectRatioNode(child: child, ratio: ratio, mode: mode) }
}

extension View {
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        modifier(AspectRatioModifier(ratio: aspectRatio, mode: contentMode))
    }
    public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        modifier(AspectRatioModifier(ratio: aspectRatio.height == 0 ? nil : aspectRatio.width / aspectRatio.height, mode: contentMode))
    }
    public func scaledToFit() -> some View { aspectRatio(contentMode: .fit) }
    public func scaledToFill() -> some View { aspectRatio(contentMode: .fill) }
}

// MARK: - offset / position

final class OffsetNode: WrapperNode {
    let offset: CGSize
    init(child: Node, offset: CGSize) {
        self.offset = offset
        super.init(child: child)
    }
    override func drawContent(_ p: Painter) {
        p.save()
        p.translate(offset.width, offset.height)
        drawChildren(p)
        p.restore()
    }
}

struct OffsetModifier: ViewModifier, NodeModifier {
    var offset: CGSize
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { OffsetNode(child: child, offset: offset) }
}

final class PositionNode: WrapperNode {
    let position: CGPoint
    init(child: Node, position: CGPoint) {
        self.position = position
        super.init(child: child)
    }
    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let c = child.sizeThatFits(ProposedViewSize(size))
        child.place(at: CGPoint(x: position.x - c.width / 2, y: position.y - c.height / 2), size: c, ctx)
    }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? { nil }
}

struct PositionModifier: ViewModifier, NodeModifier {
    var position: CGPoint
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { PositionNode(child: child, position: position) }
}

extension View {
    public func offset(_ offset: CGSize) -> some View { modifier(OffsetModifier(offset: offset)) }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { modifier(OffsetModifier(offset: CGSize(width: x, height: y))) }
    public func position(_ position: CGPoint) -> some View { modifier(PositionModifier(position: position)) }
    public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { modifier(PositionModifier(position: CGPoint(x: x, y: y))) }
}

// MARK: - alignmentGuide

final class AlignmentGuideNode: WrapperNode {
    let key: AlignmentKey
    let compute: (ViewDimensions) -> CGFloat
    init(child: Node, key: AlignmentKey, compute: @escaping (ViewDimensions) -> CGFloat) {
        self.key = key
        self.compute = compute
        super.init(child: child)
    }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        // The closure sees the child's own dimensions, so `d[.leading]` inside it means the default guide.
        key == self.key ? compute(ViewDimensions(node: child, size: size)) : child.explicitAlignment(key, size: size)
    }
}

struct AlignmentGuideModifier: ViewModifier, NodeModifier {
    let key: AlignmentKey
    let compute: (ViewDimensions) -> CGFloat
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { AlignmentGuideNode(child: child, key: key, compute: compute) }
}

extension View {
    public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        modifier(AlignmentGuideModifier(key: g.key, compute: computeValue))
    }
    public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        modifier(AlignmentGuideModifier(key: g.key, compute: computeValue))
    }
}
