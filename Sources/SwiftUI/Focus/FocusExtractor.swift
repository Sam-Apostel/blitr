// Builds the focusable set of a laid-out tree: elements with global frames, focus sections, the
// scroll views around each element, and the records (bindings, command handlers) above it.
//
//  - Elements come from `FocusRecord.element` (controls, `.focusable()`), plus system chrome made
//    here: tab bar items, alert / confirmation-dialog buttons and the search field.
//  - Disabled elements, `.focusable(false)` subtrees and zero-size elements are left out.
//  - Only the topmost presentation (sheet, cover, alert, dialog) is read: it owns focus.
//  - Elements scrolled out of view stay focusable (`visible: false`).
//  - A list row holding exactly one element makes the whole row that element (as on tvOS).
//  - Implicit sections: the tab bar (entered at the selected tab) and every List / Form.
//  - Reading order is document order, with the tab bar first (it is at the top on tvOS).

@MainActor
final class FocusExtractor {
    struct Ctx {
        var visible: CGRect
        var sections: [Int] = []
        var chain: [FocusRecord] = []
        var scrolls: [ScrollRef] = []
    }

    let screen: CGRect
    let engine: FocusEngine
    private let snap = FocusSnapshot()
    private var elementByRecord: [ObjectIdentifier: Int] = [:]
    private var sectionByRecord: [ObjectIdentifier: Int] = [:]
    private var synthCounter: [String: Int] = [:]

    init(screen: CGRect, engine: FocusEngine) {
        self.screen = screen
        self.engine = engine
    }

    func extract(_ root: Node) -> FocusSnapshot {
        snap.screen = screen
        visit(root, Ctx(visible: screen))
        finish()
        return snap
    }

    // MARK: Helpers

    private func rect(_ node: Node) -> CGRect { CGRect(origin: node.absoluteOrigin, size: node.frame.size) }

    private func intersect(_ a: CGRect, _ b: CGRect) -> CGRect {
        let x0 = max(a.minX, b.minX), y0 = max(a.minY, b.minY)
        let x1 = min(a.maxX, b.maxX), y1 = min(a.maxY, b.maxY)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) > max(a.minX, b.minX) && min(a.maxY, b.maxY) > max(a.minY, b.minY)
    }

    private func synthPath(_ kind: String) -> IdentityPath {
        let n = synthCounter[kind, default: 0]
        synthCounter[kind] = n + 1
        return IdentityPath(components: ["chrome", kind, n])
    }

    private func addSection(kind: String, path: IdentityPath, frame: CGRect, key: ObjectIdentifier?) -> Int {
        snap.sections.append(FocusSection(key: key, path: path, kind: kind, frame: frame))
        return snap.sections.count - 1
    }

    @discardableResult
    private func addElement(path: IdentityPath, role: String, frame: CGRect, label: String, ctx: Ctx,
                            activate: (@MainActor () -> Void)? = nil, synthesized: Bool = true) -> Int? {
        guard frame.width > 0.5, frame.height > 0.5 else { return nil }
        var e = FocusElement(path: path, role: role, frame: frame, visible: overlaps(frame, ctx.visible),
                             sections: ctx.sections, chain: ctx.chain, scrolls: ctx.scrolls)
        e.label = label
        e.activate = activate
        e.synthesized = synthesized
        snap.elements.append(e)
        return snap.elements.count - 1
    }

    // MARK: Visiting

    private func visit(_ node: Node, _ ctx: Ctx) {
        var ctx = ctx
        var element: (FocusRecord, FocusElementInfo)?
        for record in node.focusRecords {
            switch record.kind {
            case .excluded: return
            case .element(let info): if element == nil { element = (record, info) }
            case .section:
                let key = ObjectIdentifier(record)
                if let k = sectionByRecord[key] {
                    let f = snap.sections[k].frame
                    let r = rect(node)
                    snap.sections[k].frame = f.union(r)
                    ctx.sections.append(k)
                } else {
                    let k = addSection(kind: "focusSection", path: record.path, frame: rect(node), key: key)
                    sectionByRecord[key] = k
                    ctx.sections.append(k)
                }
            default:
                ctx.chain.append(record)
            }
        }
        if let (record, info) = element {
            let key = ObjectIdentifier(record)
            let r = rect(node)
            if let i = elementByRecord[key] {
                // Another node of the same element (a label with two top-level views).
                snap.elements[i].frame = snap.elements[i].frame.union(r)
                snap.elements[i].visible = snap.elements[i].visible || overlaps(r, ctx.visible)
                appendLabel(&snap.elements[i], node)
                return
            }
            guard info.isEnabled, r.width > 0.5, r.height > 0.5 else { return }
            var parts: [AXLabelPart] = []
            axLabelParts(node, into: &parts)
            let i = addElement(path: info.path, role: info.role, frame: r, label: parts.map(\.text).joined(separator: ", "),
                               ctx: ctx, activate: nil, synthesized: false)
            if let i { elementByRecord[key] = i }
            return
        }
        structural(node, ctx)
    }

    private func appendLabel(_ e: inout FocusElement, _ node: Node) {
        var parts: [AXLabelPart] = []
        axLabelParts(node, into: &parts)
        let extra = parts.map(\.text).joined(separator: ", ")
        if !extra.isEmpty { e.label = e.label.isEmpty ? extra : e.label + ", " + extra }
    }

    private func visitChildren(_ nodes: [Node], _ ctx: Ctx) { for n in nodes { visit(n, ctx) } }

    private func structural(_ node: Node, _ ctx: Ctx) {
        switch node {
        case let n as ScrollNode:
            var inner = ctx
            let own = rect(n)
            inner.visible = intersect(ctx.visible, n.clipRect.offsetBy(dx: n.absoluteOrigin.x, dy: n.absoluteOrigin.y))
            if let path = n.identity {
                let content = n.content.frame.size
                inner.scrolls.append(ScrollRef(path: path, axes: n.axes, viewport: own,
                                               maxOffset: CGPoint(x: content.width + n.margins.horizontal - own.width,
                                                                  y: content.height + n.margins.vertical - own.height)))
            }
            visitChildren(n.children, inner)
        case let n as ListNode:
            var inner = ctx
            let own = rect(n)
            let bleed = n.bleed
            let clip = CGRect(x: own.minX - bleed.leading, y: own.minY - bleed.top,
                              width: own.width + bleed.leading + bleed.trailing, height: own.height + bleed.top + bleed.bottom)
            inner.visible = intersect(ctx.visible, clip)
            if let path = n.scrollIdentity {
                inner.scrolls.append(ScrollRef(path: path, axes: .vertical, viewport: own,
                                               maxOffset: CGPoint(x: 0, y: n.contentHeight - own.height)))
            }
            let k = addSection(kind: "list", path: n.scrollIdentity ?? synthPath("list"), frame: own, key: nil)
            inner.sections.append(k)
            for section in n.sections {
                if let header = section.header { visit(header, inner) }
                for row in section.rows { listRow(row, inner) }
                if let footer = section.footer { visit(footer, inner) }
            }
        case let n as ListRowNode:
            listRow(n, ctx)
        case let n as PresentationHostNode:
            host(n, ctx)
        case let n as TabViewNode:
            tabView(n, ctx)
        case let n as SearchFieldNode:
            let text = (n.children.first as? TextNode).map(axPlainText) ?? ""
            addElement(path: synthPath("search"), role: "searchField", frame: rect(n), label: n.showsPrompt && !text.isEmpty ? text : "Search", ctx: ctx)
        case let n as NavigationStackNode:
            // Bar items first: they are above the content in reading order.
            visitChildren(n.children.filter { $0 !== n.content }, ctx)
            visit(n.content, ctx)
        case is BackButtonNode, is EllipsisCircleNode:
            // tvOS has no back button (Menu goes back) and no overflow button in the bar.
            return
        default:
            visitChildren(node.children, ctx)
        }
    }

    private func listRow(_ row: ListRowNode, _ ctx: Ctx) {
        let before = snap.elements.count
        visitChildren(row.children, ctx)
        // On tvOS the whole row is the focusable cell.
        if snap.elements.count == before + 1 {
            let r = rect(row)
            snap.elements[before].frame = r
            snap.elements[before].visible = overlaps(r, ctx.visible)
        }
    }

    // MARK: Tab bar

    private func tabView(_ n: TabViewNode, _ ctx: Ctx) {
        visit(n.content, ctx)
        if let accessory = n.accessory { visit(accessory, ctx) }
        guard !n.items.isEmpty, n.barVisible else { return }
        let own = rect(n)
        let width = own.width / CGFloat(n.items.count)
        let top = own.minY + n.barTop
        let barFrame = n.glassBarFrame.map { $0.offsetBy(dx: own.minX, dy: own.minY) }
            ?? CGRect(x: own.minX, y: top, width: own.width, height: TabBarMetrics.height)
        let base = n.focusPath ?? synthPath("tabView")
        // The tab bar spans the screen width as a focus target, as UIKit's does; a tvOS sidebar is its own frame.
        let sectionFrame = n.tv?.isSidebar == true ? barFrame
            : CGRect(x: screen.minX, y: barFrame.minY, width: screen.width, height: barFrame.height)
        let k = addSection(kind: "tabBar", path: base.appending("tabBar"), frame: sectionFrame, key: nil)
        var inner = ctx
        inner.sections.append(k)
        for (i, item) in n.items.enumerated() {
            var parts: [AXLabelPart] = []
            if let title = item.title { axLabelParts(title, into: &parts) }
            if parts.isEmpty, let icon = item.icon { axLabelParts(icon, into: &parts) }
            let frame: CGRect
            if let frames = n.glassItemFrames, frames.indices.contains(i) {
                frame = frames[i].offsetBy(dx: own.minX, dy: own.minY)
            } else {
                frame = CGRect(x: own.minX + width * CGFloat(i), y: top, width: width, height: TabBarMetrics.height)
            }
            let select = n.selectTab
            if let index = addElement(path: base.appending("tab").appending(i), role: "tab", frame: frame,
                                      label: parts.map(\.text).joined(separator: ", "), ctx: inner,
                                      activate: select.map { s in { s(i) } }) {
                snap.elements[index].isTab = true
                if i == n.selectedIndex { snap.sections[k].preferred = index }
            }
        }
    }

    // MARK: Presentations

    private func host(_ n: PresentationHostNode, _ ctx: Ctx) {
        guard let top = n.layers.last else { visitChildren(n.children, ctx); return }
        snap.dismissTop = top.dismiss
        switch top {
        case let sheet as SheetLayerNode:
            snap.modalKind = "sheet"
            var inner = ctx
            inner.visible = intersect(ctx.visible, sheet.cardRect.offsetBy(dx: sheet.absoluteOrigin.x, dy: sheet.absoluteOrigin.y))
            visit(sheet.content, inner)
        case let cover as CoverLayerNode:
            snap.modalKind = cover.tvSheet ? "sheet" : "fullScreenCover"
            visit(cover.content, ctx)
        case let dimmed as DimmedCardLayerNode:
            if let tv = dimmed.card as? TVAlertCardNode {
                snap.modalKind = "alert"
                cardActions(card: rect(tv), texts: tv.actions, cells: tv.actionCells, handlers: tv.actionHandlers,
                            rowHeight: TVMetrics.buttonHeight, sideBySide: false, dismiss: top.dismiss, ctx)
            } else if let alert = dimmed.card as? AlertCardNode {
                snap.modalKind = "alert"
                cardActions(card: rect(alert), texts: alert.actions, cells: alert.glassActionCells, handlers: alert.actionHandlers,
                            rowHeight: AlertMetrics.actionHeight, sideBySide: true, dismiss: top.dismiss, ctx)
            } else if let dialog = dimmed.card as? DialogCardNode {
                snap.modalKind = "confirmationDialog"
                cardActions(card: rect(dialog), texts: dialog.actions + [dialog.cancel], cells: dialog.glassActionCells,
                            handlers: dialog.actionHandlers, rowHeight: DialogMetrics.rowHeight, sideBySide: false, dismiss: top.dismiss, ctx)
            } else {
                visitChildren(top.children, ctx)
            }
        default:
            visitChildren(top.children, ctx)
        }
    }

    private func cardActions(card box: CGRect, texts: [TextNode], cells: [CGRect]?, handlers: [(@MainActor () -> Void)?],
                             rowHeight: CGFloat, sideBySide: Bool, dismiss: (@MainActor () -> Void)?, _ ctx: Ctx) {
        let centers = texts.map { rect($0).midX }
        let twoUp = sideBySide && texts.count == 2 && centers.allSatisfy { abs($0 - box.midX) > 1 }
        for (i, text) in texts.enumerated() {
            let cell: CGRect
            if let cells, cells.count == texts.count {
                cell = cells[i].offsetBy(dx: box.minX, dy: box.minY)
            } else {
                let t = rect(text)
                cell = twoUp
                    ? CGRect(x: t.midX < box.midX ? box.minX : box.midX, y: t.midY - rowHeight / 2, width: box.width / 2, height: rowHeight)
                    : CGRect(x: box.minX, y: t.midY - rowHeight / 2, width: box.width, height: rowHeight)
            }
            let handler = handlers.indices.contains(i) ? handlers[i] : nil
            // Any alert button dismisses the alert after running its action.
            addElement(path: synthPath("alertAction"), role: "alertAction", frame: cell, label: axPlainText(text), ctx: ctx,
                       activate: { handler?(); dismiss?() })
        }
    }

    // MARK: Finishing

    private func finish() {
        // The tab bar is read first: it sits at the top of a tvOS screen.
        let order = snap.elements.indices.filter { snap.elements[$0].isTab } + snap.elements.indices.filter { !snap.elements[$0].isTab }
        var remap = [Int](repeating: 0, count: snap.elements.count)
        for (newIndex, old) in order.enumerated() { remap[old] = newIndex }
        snap.elements = order.map { snap.elements[$0] }
        for k in snap.sections.indices {
            snap.sections[k].preferred = snap.sections[k].preferred.map { remap[$0] }
        }
        var usedIDs: [String: Int] = [:]
        for i in snap.elements.indices {
            snap.elements[i].sections = snap.elements[i].sections
            snap.elements[i].index = i + 1
            var id = "\(snap.elements[i].role)-\(snap.elements[i].path.shortHash)"
            let n = usedIDs[id, default: 0] + 1
            usedIDs[id] = n
            if n > 1 { id += "-\(n)" }
            snap.elements[i].id = id
            snap.byPath[snap.elements[i].path] = i
            for k in snap.elements[i].sections { snap.sections[k].members.append(i) }
        }
        var usedSectionIDs: [String: Int] = [:]
        for k in snap.sections.indices {
            var id = "\(snap.sections[k].kind)-\(snap.sections[k].path.shortHash)"
            let n = usedSectionIDs[id, default: 0] + 1
            usedSectionIDs[id] = n
            if n > 1 { id += "-\(n)" }
            snap.sections[k].id = id
        }
    }
}
