// NavigationSplitView at regular width (iPad): columns side by side, each with its own navigation stack.

enum SplitViewMetrics {
    /// Sidebar and content column width (iPadOS: about 320pt for the sidebar; the middle column of a
    /// three-column split is estimated at the same width).
    static let columnWidth: CGFloat = 320
}

final class SplitViewNode: Node {
    let widths: [CGFloat?]   // nil = takes the remaining width
    private var separatorXs: [CGFloat] = []
    private let separator: _Paint

    init(columns: [Node], widths: [CGFloat?], scheme: ColorScheme) {
        self.widths = widths
        separator = .color(SystemColor.separator.resolve(scheme))
        super.init(children: columns)
        traits = columns.last?.traits ?? Traits()
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let fixed = widths.compactMap { $0 }.reduce(0, +)
        let flexible = max(0, size.width - fixed)
        var x: CGFloat = 0
        separatorXs = []
        for (child, width) in zip(children, widths) {
            let w = width ?? flexible
            let paneAbs = CGRect(x: ctx.origin.x + x, y: ctx.container.minY, width: w, height: ctx.container.height)
            var inner = ctx
            inner.container = paneAbs
            inner.safeRect = CGRect(x: ctx.origin.x + x, y: ctx.safeRect.minY, width: w, height: ctx.safeRect.height)
            child.place(at: CGPoint(x: x, y: 0), size: CGSize(width: w, height: size.height), inner)
            x += w
            if child !== children.last { separatorXs.append(x) }
        }
    }

    override func drawContent(_ p: Painter) {
        drawChildren(p)
        for x in separatorXs {
            let line = CGRect(x: x - ChromeMetrics.hairline / 2, y: 0, width: ChromeMetrics.hairline, height: frame.height)
            p.fill(Path(line), with: separator, in: line)
        }
    }
}

extension NavigationSplitView {
    /// Columns for a regular-width iPad: sidebar + detail, or sidebar + content + detail in landscape
    /// (portrait shows content + detail and keeps the sidebar hidden, as iPadOS does).
    @MainActor
    func resolveColumns(_ ctx: ResolveContext) -> Node {
        let (sidebar, content, detail) = (self.sidebar, self.content, self.detail)
        func stack<V: View>(_ view: V, _ key: String) -> Node {
            makeNavigationStack(ctx.child(key), path: []) { resolveSingle(view, $0.child("root")) }
        }
        let landscape = _currentConfiguration().device.orientation.isLandscape
        let column = SplitViewMetrics.columnWidth
        if let content {
            if landscape {
                return SplitViewNode(columns: [stack(sidebar, "sidebar"), stack(content, "content"), stack(detail, "detail")],
                                     widths: [column, column, nil], scheme: ctx.env.colorScheme)
            }
            return SplitViewNode(columns: [stack(content, "content"), stack(detail, "detail")], widths: [column, nil], scheme: ctx.env.colorScheme)
        }
        return SplitViewNode(columns: [stack(sidebar, "sidebar"), stack(detail, "detail")], widths: [column, nil], scheme: ctx.env.colorScheme)
    }
}
