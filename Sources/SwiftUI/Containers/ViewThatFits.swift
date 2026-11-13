// ViewThatFits: shows the first child whose ideal size fits the proposal along the checked axes.

final class ViewThatFitsNode: Node {
    let axes: Axis.Set
    private var lastChoice = 0

    init(axes: Axis.Set, children: [Node]) {
        self.axes = axes
        super.init(children: children)
    }

    private func choose(_ proposal: ProposedViewSize) -> Int {
        guard children.count > 1 else { return 0 }
        let ideal = ProposedViewSize(width: axes.contains(.horizontal) ? nil : proposal.width,
                                     height: axes.contains(.vertical) ? nil : proposal.height)
        let slack: CGFloat = 0.01
        for (i, child) in children.enumerated() {
            let size = child.sizeThatFits(ideal)
            if axes.contains(.horizontal), let w = proposal.width, w.isFinite, size.width > w + slack { continue }
            if axes.contains(.vertical), let h = proposal.height, h.isFinite, size.height > h + slack { continue }
            return i
        }
        return children.count - 1
    }

    private var chosen: Node? { children.indices.contains(lastChoice) ? children[lastChoice] : nil }

    override func measure(_ proposal: ProposedViewSize) -> CGSize {
        guard !children.isEmpty else { return .zero }
        let i = choose(proposal)
        lastChoice = i
        return children[i].sizeThatFits(proposal)
    }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        guard !children.isEmpty else { return }
        let i = choose(ProposedViewSize(size))
        lastChoice = i
        let child = children[i]
        child.place(at: .zero, size: child.sizeThatFits(ProposedViewSize(size)), ctx)
    }

    override func drawContent(_ p: Painter) { chosen?.draw(p) }
    override func spacing(_ edge: Edge) -> CGFloat? { chosen?.spacing(edge) }
    override func explicitAlignment(_ key: AlignmentKey, size: CGSize) -> CGFloat? {
        guard !children.isEmpty else { return nil }
        let child = children[choose(ProposedViewSize(size))]
        return child.explicitAlignment(key, size: child.sizeThatFits(ProposedViewSize(size)))
    }
}

public struct ViewThatFits<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let axes: Axis.Set
    let content: Content
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        // Each top-level view of the builder is one alternative.
        let children = resolveNodes(content, ctx)
        out.append(ViewThatFitsNode(axes: axes, children: children))
    }
}
