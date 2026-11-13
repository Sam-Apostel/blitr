// Grid / GridRow: a table whose column widths and row heights come from the cells.

enum GridCellColumnsKey: TraitKey { typealias Value = Int }
enum GridCellAnchorKey: TraitKey { typealias Value = UnitPoint }
enum GridColumnAlignmentKey: TraitKey { typealias Value = HorizontalAlignment }
enum GridCellUnsizedAxesKey: TraitKey { typealias Value = Axis.Set }

extension View {
    public func gridCellColumns(_ count: Int) -> some View { trait(GridCellColumnsKey.self, max(1, count)) }
    public func gridCellAnchor(_ anchor: UnitPoint) -> some View { trait(GridCellAnchorKey.self, anchor) }
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View { trait(GridColumnAlignmentKey.self, guide) }
    public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View { trait(GridCellUnsizedAxesKey.self, axes) }
}

/// A GridRow: a transparent container whose cells are positioned by the enclosing grid.
final class GridRowNode: Node {
    let rowAlignment: VerticalAlignment?
    struct CellPlan { var rect: CGRect; var anchor: Alignment?; var unitAnchor: UnitPoint?; var proposal: ProposedViewSize }
    var plan: [CellPlan] = []
    var baselineLine: CGFloat?

    init(alignment: VerticalAlignment?, children: [Node]) {
        self.rowAlignment = alignment
        super.init(children: children)
    }
    override func layout(size: CGSize, _ ctx: PlaceContext) {
        for (child, cell) in zip(children, plan) {
            let childSize = child.sizeThatFits(cell.proposal)
            let c = cell.rect
            var x = c.minX, y = c.minY
            if let u = cell.unitAnchor {
                x += (c.width - childSize.width) * u.x
                y += (c.height - childSize.height) * u.y
            } else if let a = cell.anchor {
                let dims = ViewDimensions(node: nil, size: c.size)
                x += a.horizontal.key.id.defaultValue(in: dims) - child.alignmentValue(a.horizontal.key, size: childSize)
                if let line = baselineLine, Self.isBaseline(a.vertical) {
                    y = line - child.alignmentValue(a.vertical.key, size: childSize)
                } else {
                    y += a.vertical.key.id.defaultValue(in: dims) - child.alignmentValue(a.vertical.key, size: childSize)
                }
            }
            child.place(at: CGPoint(x: x, y: y), size: childSize, ctx)
        }
    }
    static func isBaseline(_ v: VerticalAlignment) -> Bool {
        let id = ObjectIdentifier(v.key.id)
        return id != ObjectIdentifier(VerticalAlignment.Top.self) && id != ObjectIdentifier(VerticalAlignment.Center.self)
            && id != ObjectIdentifier(VerticalAlignment.Bottom.self)
    }
}

final class GridNode: Node {
    let alignment: Alignment
    let hSpacing: CGFloat
    let vSpacing: CGFloat

    struct Cell {
        var node: Node
        var column: Int
        var span: Int
        var unsized: Axis.Set
    }
    struct Row {
        var node: Node
        var isRow: Bool
        var cells: [Cell]
    }
    struct Result {
        var columnWidths: [CGFloat] = []
        var columnX: [CGFloat] = []
        var rowHeights: [CGFloat] = []
        var rowY: [CGFloat] = []
        var size: CGSize = .zero
    }
    private var rows: [Row] = []
    private var columnCount = 0
    private var columnAlignments: [HorizontalAlignment?] = []
    private var cache: [ProposedViewSize: Result] = [:]

    init(alignment: Alignment, horizontalSpacing: CGFloat?, verticalSpacing: CGFloat?, children: [Node]) {
        self.alignment = alignment
        self.hSpacing = horizontalSpacing ?? defaultStackSpacing
        self.vSpacing = verticalSpacing ?? defaultStackSpacing
        super.init(children: children)
        buildTable()
    }

    private func buildTable() {
        var count = 0
        for child in children {
            if let row = child as? GridRowNode {
                var column = 0
                var cells: [Cell] = []
                for cell in row.children {
                    let span = cell.traits[GridCellColumnsKey.self] ?? 1
                    cells.append(Cell(node: cell, column: column, span: span, unsized: cell.traits[GridCellUnsizedAxesKey.self] ?? []))
                    column += span
                }
                count = max(count, column)
                rows.append(Row(node: row, isRow: true, cells: cells))
            } else {
                rows.append(Row(node: child, isRow: false, cells: [Cell(node: child, column: 0, span: 1, unsized: child.traits[GridCellUnsizedAxesKey.self] ?? [])]))
            }
        }
        columnCount = max(1, count)
        // Spanning cells of free-standing views cover every column.
        for r in rows.indices where !rows[r].isRow { rows[r].cells[0].span = columnCount }
        columnAlignments = [HorizontalAlignment?](repeating: nil, count: columnCount)
        for row in rows {
            for cell in row.cells where cell.span == 1 {
                if let a = cell.node.traits[GridColumnAlignmentKey.self], columnAlignments[cell.column] == nil { columnAlignments[cell.column] = a }
            }
        }
    }

    private func compute(_ proposal: ProposedViewSize) -> Result {
        if let cached = cache[proposal] { return cached }
        var r = Result()
        let n = columnCount
        let hGaps = CGFloat(max(0, n - 1)) * hSpacing

        // Column widths: minimum / ideal / maximum contributions of the cells in each column.
        func columnExtent(spans: Bool = true, _ width: (Cell) -> CGFloat) -> [CGFloat] {
            var out = [CGFloat](repeating: 0, count: n)
            for row in rows {
                for cell in row.cells where cell.span == 1 && !cell.unsized.contains(.horizontal) {
                    out[cell.column] = max(out[cell.column], width(cell))
                }
            }
            for row in rows where spans {
                for cell in row.cells where cell.span > 1 && !cell.unsized.contains(.horizontal) {
                    let range = cell.column..<(cell.column + cell.span)
                    let have = range.reduce(CGFloat(0)) { $0 + out[$1] } + CGFloat(cell.span - 1) * hSpacing
                    let need = width(cell)
                    if need > have {
                        for c in range { out[c] += (need - have) / CGFloat(cell.span) }
                    }
                }
            }
            return out
        }
        let ideal = columnExtent { $0.node.sizeThatFits(.unspecified).width }
        let minimum = columnExtent { min($0.node.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width, $0.node.sizeThatFits(.unspecified).width) }
        let maximum = columnExtent(spans: false) { $0.node.sizeThatFits(ProposedViewSize(width: .infinity, height: nil)).width }

        var widths = ideal
        if let available = proposal.width, available.isFinite {
            let room = available - hGaps
            let total = widths.reduce(0, +)
            if total > room {
                // Shrink the columns that can give (text that wraps), proportionally to their slack.
                let slack = zip(ideal, minimum).map { max(0, $0 - $1) }
                let totalSlack = slack.reduce(0, +)
                if totalSlack > 0 {
                    let cut = min(total - room, totalSlack)
                    for i in 0..<n { widths[i] -= cut * slack[i] / totalSlack }
                }
            } else if total < room {
                // Grow the flexible columns equally, up to their maximum.
                var remaining = room - total
                var open = (0..<n).filter { maximum[$0] > widths[$0] + 0.001 }
                while remaining > 0.001, !open.isEmpty {
                    let share = remaining / CGFloat(open.count)
                    for i in open {
                        let grow = min(share, maximum[i] - widths[i])
                        widths[i] += grow; remaining -= grow
                    }
                    open.removeAll { maximum[$0] - widths[$0] <= 0.001 }
                }
            }
        }
        r.columnWidths = widths
        var x: CGFloat = 0
        for w in widths { r.columnX.append(x); x += w + hSpacing }
        let totalWidth = widths.reduce(0, +) + hGaps

        // Row heights, with the cells proposed their column width.
        func cellWidth(_ cell: Cell) -> CGFloat {
            (cell.column..<(cell.column + cell.span)).reduce(CGFloat(0)) { $0 + widths[$1] } + CGFloat(cell.span - 1) * hSpacing
        }
        func rowExtent(_ row: Row, _ height: ProposedViewSize.Mode) -> CGFloat {
            var out: CGFloat = 0
            for cell in row.cells where !cell.unsized.contains(.vertical) {
                let w: CGFloat? = cell.unsized.contains(.horizontal) ? cellWidth(cell) : cellWidth(cell)
                let h: CGFloat?
                switch height { case .ideal: h = nil; case .minimum: h = 0; case .maximum: h = .infinity }
                out = max(out, cell.node.sizeThatFits(ProposedViewSize(width: w, height: h)).height)
            }
            return out
        }
        var heights = rows.map { rowExtent($0, .ideal) }
        if let available = proposal.height, available.isFinite, !rows.isEmpty {
            let room = available - CGFloat(max(0, rows.count - 1)) * vSpacing
            let total = heights.reduce(0, +)
            if total < room {
                let maxima = rows.map { rowExtent($0, .maximum) }
                var remaining = room - total
                var open = rows.indices.filter { maxima[$0] > heights[$0] + 0.001 && maxima[$0].isFinite }
                // Rows whose cells are unbounded (Color, Spacer-like) take the rest.
                let unbounded = rows.indices.filter { !maxima[$0].isFinite || maxima[$0] > 1e8 }
                if !unbounded.isEmpty { open = Array(Set(open + unbounded)).sorted() }
                while remaining > 0.001, !open.isEmpty {
                    let share = remaining / CGFloat(open.count)
                    for i in open {
                        let cap = maxima[i] > 1e8 ? CGFloat.infinity : maxima[i]
                        let grow = min(share, cap - heights[i])
                        heights[i] += grow; remaining -= grow
                    }
                    open.removeAll { (maxima[$0] > 1e8 ? CGFloat.infinity : maxima[$0]) - heights[$0] <= 0.001 }
                }
            }
        }
        r.rowHeights = heights
        var y: CGFloat = 0
        for h in heights { r.rowY.append(y); y += h + vSpacing }
        let totalHeight = rows.isEmpty ? 0 : heights.reduce(0, +) + CGFloat(rows.count - 1) * vSpacing
        r.size = CGSize(width: totalWidth, height: totalHeight)
        cache[proposal] = r
        return r
    }

    override func measure(_ proposal: ProposedViewSize) -> CGSize { compute(proposal).size }

    override func layout(size: CGSize, _ ctx: PlaceContext) {
        let r = compute(ProposedViewSize(size))
        // Leftover room (a grid with no flexible cells in a bigger frame) is shared by alignment.
        for (i, row) in rows.enumerated() {
            let rowRect = CGRect(x: 0, y: r.rowY[i], width: r.size.width, height: r.rowHeights[i])
            if let rowNode = row.node as? GridRowNode {
                let rowAlign = rowNode.rowAlignment
                var plans: [GridRowNode.CellPlan] = []
                var lineBaseline: CGFloat?
                for cell in row.cells {
                    let x0 = r.columnX[cell.column]
                    let w = (cell.column..<(cell.column + cell.span)).reduce(CGFloat(0)) { $0 + r.columnWidths[$1] } + CGFloat(cell.span - 1) * hSpacing
                    let hAlign = cell.node.traits[GridColumnAlignmentKey.self] ?? columnAlignments[cell.column] ?? alignment.horizontal
                    let vAlign = rowAlign ?? alignment.vertical
                    plans.append(GridRowNode.CellPlan(
                        rect: CGRect(x: x0, y: 0, width: w, height: rowRect.height),
                        anchor: Alignment(horizontal: hAlign, vertical: vAlign),
                        unitAnchor: cell.node.traits[GridCellAnchorKey.self],
                        proposal: ProposedViewSize(width: w, height: rowRect.height)))
                }
                // Baseline alignment across the row: the tallest ascent sets the line.
                let v = rowAlign ?? alignment.vertical
                if GridRowNode.isBaseline(v) {
                    var above: CGFloat = 0
                    for (cell, plan) in zip(row.cells, plans) {
                        let s = cell.node.sizeThatFits(plan.proposal)
                        above = max(above, cell.node.alignmentValue(v.key, size: s))
                    }
                    lineBaseline = above
                }
                rowNode.plan = plans
                rowNode.baselineLine = lineBaseline
                rowNode.place(at: rowRect.origin, size: rowRect.size, ctx)
            } else {
                // A free-standing view spans the whole grid.
                let node = row.node
                let w = r.size.width
                let s = node.sizeThatFits(ProposedViewSize(width: w, height: rowRect.height))
                let a = node.traits[GridCellAnchorKey.self]
                let x = a.map { (w - s.width) * $0.x } ?? (w - s.width) * 0.5
                let y = a.map { (rowRect.height - s.height) * $0.y } ?? (rowRect.height - s.height) * 0.5
                node.place(at: CGPoint(x: x, y: rowRect.minY + y), size: s, ctx)
            }
        }
    }
}

extension ProposedViewSize {
    enum Mode { case ideal, minimum, maximum }
}

public struct Grid<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = nil })
        out.append(GridNode(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing, children: children))
    }
}

public struct GridRow<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment?
    let content: Content
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let children = resolveNodes(content, ctx.with { $0.stackAxis = nil })
        out.append(GridRowNode(alignment: alignment, children: children))
    }
}
