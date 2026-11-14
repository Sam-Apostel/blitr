// Builds the accessibility tree from a laid-out node tree, approximately the way UIKit / VoiceOver
// would see it.
//
// Rules, in short:
//  - Leaf content is an element by itself: `Text` is static text, `Image` is an image (unless decorative).
//  - A node with `AccessibilityInfo.isElement` (controls, `accessibilityElement`, tap gestures) is one element;
//    `.combine` swallows its descendants and joins their labels with ", ", `.ignore` drops them,
//    `.contain` keeps them as children.
//  - Other nodes are transparent. Label / hint / identifier / traits set on them are pushed down to the
//    elements inside.
//  - Hidden subtrees and zero-size leaves are dropped. Elements outside the visible area (screen, scroll
//    view clip) are kept and flagged `offscreen`.
//  - Chrome (navigation bar, tab bar, list headers, alerts, sheets) is read from its node types.

// MARK: - Element

struct AXLabelPart {
    enum Source { case text, symbol, asset, explicit }
    var text: String
    var source: Source
}

struct AXElement {
    var role = "group"
    var roleIsDerived = true
    var label = ""
    var value: String?
    var hint: String?
    var identifier: String?
    var traits: AXTrait = []
    var enabled = true
    var frame: CGRect = .zero
    /// Where a touch activates the element (interactive elements only).
    var hitFrame: CGRect?
    /// The hit area before the platform's minimum-size expansion (used for overlap checks).
    var rawHitFrame: CGRect?
    var actions: [String] = []
    var inputLabels: [String] = []
    var children: [AXElement] = []
    var offscreen = false
    var interactive = false
    var sortPriority = 0.0
    var labelSources: [AXLabelPart.Source] = []
    var truncated = false
    /// The default action (internal; a later feature simulates taps with it).
    var activate: (@MainActor () -> Void)?
    var boxID: ObjectIdentifier?

    var labelOnlyFromAssetName: Bool { !labelSources.isEmpty && labelSources.allSatisfy { $0 == .asset } }

    static func role(for traits: AXTrait, fallback: String) -> String {
        if traits.contains(.tabBar) { return "tabBar" }
        if traits.contains(.searchField) { return "searchField" }
        if traits.contains(.toggle) { return "switch" }
        if traits.contains(.adjustable) { return "adjustable" }
        if traits.contains(.link) { return "link" }
        if traits.contains(.button) { return "button" }
        if traits.contains(.header) { return "header" }
        if traits.contains(.image) { return "image" }
        if traits.contains(.staticText) { return "staticText" }
        return fallback
    }
    mutating func refreshRole() { if roleIsDerived { role = AXElement.role(for: traits, fallback: role) } }
}

// MARK: - Labels

@MainActor
func axPlainText(_ node: TextNode) -> String {
    node.runs.map(\.text).joined().replacingOccurrences(of: "\u{FFFC}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
func axImageLabel(_ node: ImageNode) -> AXLabelPart? {
    if node.isDecorative { return nil }
    if let label = node.accessibilityLabelText { return label.isEmpty ? nil : AXLabelPart(text: label, source: .explicit) }
    switch node.imageSource {
    case .system(let name)?: return AXLabelPart(text: AXTrait.humanized(symbol: name), source: .symbol)
    case .named(let name)?: return AXLabelPart(text: name, source: .asset)
    case .file(let path)?: return AXLabelPart(text: (path as NSString).lastPathComponent, source: .asset)
    case nil: return nil
    }
}

/// The label parts a subtree contributes when its container combines it (document order).
@MainActor
func axLabelParts(_ node: Node, into parts: inout [AXLabelPart], geometry: Bool = true) {
    if let info = node.ax?.info {
        if info.hidden == true { return }
        if let label = info.label {
            if !label.isEmpty { parts.append(AXLabelPart(text: label, source: .explicit)) }
            return
        }
        if info.isElement && info.children == .ignore { return }
        if let representation = info.representation {
            for n in representation { axLabelParts(n, into: &parts, geometry: false) }
            return
        }
    }
    switch node {
    case let t as TextNode:
        if geometry && (t.frame.width <= 0.01 || t.frame.height <= 0.01) { return }
        let s = axPlainText(t)
        if !s.isEmpty { parts.append(AXLabelPart(text: s, source: .text)) }
    case let i as ImageNode:
        if geometry && (i.frame.width <= 0.01 || i.frame.height <= 0.01) { return }
        if let part = axImageLabel(i) { parts.append(part) }
    case is SearchFieldNode, is ShapeNode, is CanvasNode, is SpacerNode:
        return
    default:
        for child in node.children { axLabelParts(child, into: &parts, geometry: geometry) }
    }
}

/// Plain text of unplaced, freshly resolved nodes (labels of controls), joined with ", ".
@MainActor
func axText(_ nodes: [Node]) -> String {
    var parts: [AXLabelPart] = []
    for node in nodes { axLabelParts(node, into: &parts, geometry: false) }
    return parts.map(\.text).joined(separator: ", ")
}

extension AccessibilityInfo {
    /// TextField / SecureField / TextEditor: the placeholder is the label, the text the value.
    @MainActor
    static func textInput(role: String, text: String, placeholder: AnyView?, _ ctx: ResolveContext) -> AccessibilityInfo {
        let prompt = placeholder.map { axText(resolveNodes($0, ctx.child("axPlaceholder"))) } ?? ""
        return AccessibilityInfo {
            $0.isElement = true
            $0.role = role
            $0.children = .ignore
            $0.label = prompt.isEmpty ? nil : prompt
            if !text.isEmpty { $0.value = role == "secureTextField" ? String(repeating: "\u{2022}", count: text.count) : text }
            $0.isTapTarget = true
            $0.isEnabled = ctx.env.isEnabled
        }
    }
}

// MARK: - Extractor

@MainActor
final class AXExtractor {
    struct Ctx {
        var visible: CGRect
        var inBar = false
    }
    struct Truncation { var frame: CGRect; var text: String }

    let screen: CGRect
    /// False when reading unplaced nodes (`accessibilityRepresentation`).
    var geometry = true
    var truncations: [Truncation] = []
    /// Elements behind a modal presentation (not reported).
    var obscuredCount = 0
    var modalKind: String?

    init(screen: CGRect) { self.screen = screen }

    func extract(_ root: Node) -> [AXElement] {
        visit(root, Ctx(visible: screen))
    }

    // MARK: Helpers

    private func rect(_ node: Node) -> CGRect { CGRect(origin: node.absoluteOrigin, size: node.frame.size) }

    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) > max(a.minX, b.minX) && min(a.maxY, b.maxY) > max(a.minY, b.minY)
    }

    private func intersect(_ a: CGRect, _ b: CGRect) -> CGRect {
        let x0 = max(a.minX, b.minX), y0 = max(a.minY, b.minY)
        let x1 = min(a.maxX, b.maxX), y1 = min(a.maxY, b.maxY)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func expand(_ r: CGRect, toAtLeast side: CGFloat = 44) -> CGRect {
        let w = max(r.width, side), h = max(r.height, side)
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    private func union(_ a: CGRect, _ b: CGRect) -> CGRect {
        let x0 = min(a.minX, b.minX), y0 = min(a.minY, b.minY)
        return CGRect(x: x0, y: y0, width: max(a.maxX, b.maxX) - x0, height: max(a.maxY, b.maxY) - y0)
    }

    private func flatten(_ elements: [AXElement]) -> [AXElement] {
        elements.flatMap { [$0] + flatten($0.children) }
    }

    // MARK: Visiting

    func visit(_ node: Node, _ ctx: Ctx) -> [AXElement] {
        let info = node.ax?.info
        if info?.hidden == true { return [] }
        let r = rect(node)
        if geometry && node.children.isEmpty && (r.width <= 0.01 || r.height <= 0.01) { return [] }
        if let info, let representation = info.representation {
            return representationElements(node, info, representation, r, ctx)
        }
        let own = structural(node, ctx)
        guard let info else { return own }
        return apply(info, to: own, node: node, rect: r, ctx)
    }

    func visitChildren(_ nodes: [Node], _ ctx: Ctx) -> [AXElement] {
        var result: [AXElement] = []
        var byBox: [ObjectIdentifier: Int] = [:]
        for child in nodes {
            let elements = visit(child, ctx)
            if let box = child.ax, box.info.isElement, elements.count == 1 {
                let id = ObjectIdentifier(box)
                if let index = byBox[id] {
                    merge(&result[index], elements[0])
                    continue
                }
                byBox[id] = result.count
            }
            result += elements
        }
        if result.contains(where: { $0.sortPriority != 0 }) {
            result = result.enumerated().sorted {
                ($0.element.sortPriority, -$0.offset) > ($1.element.sortPriority, -$1.offset)
            }.map(\.element)
        }
        return result
    }

    /// Two nodes of one view (a label with an icon and a title) become one element.
    private func merge(_ a: inout AXElement, _ b: AXElement) {
        a.frame = union(a.frame, b.frame)
        a.rawHitFrame = a.rawHitFrame.map { r in b.rawHitFrame.map { union(r, $0) } ?? r }
        a.hitFrame = a.hitFrame.map { r in b.hitFrame.map { union(r, $0) } ?? r }
        if a.label.isEmpty { a.label = b.label } else if !b.label.isEmpty { a.label += ", " + b.label }
        a.labelSources += b.labelSources
        a.children += b.children
        a.truncated = a.truncated || b.truncated
        a.offscreen = a.offscreen && b.offscreen
    }

    private func structural(_ node: Node, _ ctx: Ctx) -> [AXElement] {
        switch node {
        case let n as TextNode: return textElements(n, ctx)
        case let n as ImageNode: return imageElements(n, ctx)
        case let n as PresentationHostNode: return host(n, ctx)
        case let n as NavigationStackNode: return navigationStack(n, ctx)
        case let n as TabViewNode: return tabView(n, ctx)
        case let n as ListNode: return list(n, ctx)
        case let n as SearchFieldNode: return searchField(n, ctx)
        case let n as BackButtonNode: return backButton(n, ctx)
        case let n as EllipsisCircleNode: return moreButton(n, ctx)
        case let n as ToolbarGlassGroupNode where n.appearance != nil && n.cellRects.count == n.items.count:
            // Liquid Glass bar items: a button's frame is its cell on the glass, not just its glyph.
            var result: [AXElement] = []
            for (item, cell) in zip(n.items, n.cellRects) {
                var elements = visitChildren([item], ctx)
                if elements.count == 1, elements[0].interactive, geometry {
                    elements[0].frame = cell
                    elements[0].rawHitFrame = cell
                    elements[0].hitFrame = expand(cell)
                }
                result += elements
            }
            return result
        case let n as ScrollNode:
            var inner = ctx
            inner.visible = intersect(ctx.visible, n.clipRect.offsetBy(dx: n.absoluteOrigin.x, dy: n.absoluteOrigin.y))
            return visitChildren(n.children, inner)
        case is SpacerNode, is EmptyNode, is ShapeNode, is DividerNode, is CanvasNode:
            return []
        default:
            return visitChildren(node.children, ctx)
        }
    }

    // MARK: Leaves

    private func textElements(_ node: TextNode, _ ctx: Ctx) -> [AXElement] {
        let text = axPlainText(node)
        guard !text.isEmpty else { return [] }
        var e = AXElement()
        e.role = "staticText"
        e.label = text
        e.labelSources = [.text]
        e.traits = [.staticText]
        e.frame = rect(node)
        e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
        if geometry, node.textLayout(width: node.frame.width).isTruncated {
            e.truncated = true
            truncations.append(Truncation(frame: e.frame, text: text))
        }
        return [e]
    }

    private func imageElements(_ node: ImageNode, _ ctx: Ctx) -> [AXElement] {
        guard let part = axImageLabel(node) else { return [] }
        var e = AXElement()
        e.role = "image"
        e.label = part.text
        e.labelSources = [part.source]
        e.traits = [.image]
        e.frame = rect(node)
        e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
        return [e]
    }

    // MARK: Info on a node

    private func apply(_ info: AccessibilityInfo, to own: [AXElement], node: Node, rect r: CGRect, _ ctx: Ctx) -> [AXElement] {
        guard info.isElement else {
            var elements = own
            overlay(info, onto: &elements)
            // A label set on a container names the whole container, not the one leaf inside it.
            if elements.count == 1, info.label != nil || info.value != nil, elements[0].children.isEmpty {
                elements[0].frame = r
                if elements[0].interactive { elements[0].rawHitFrame = r; elements[0].hitFrame = r }
            }
            return elements
        }
        var e = AXElement()
        e.frame = r
        e.boxID = node.ax.map(ObjectIdentifier.init)
        let hasInteractiveInside = flatten(own).contains { $0.interactive }
        let behavior = info.children ?? (info.isTapTarget && hasInteractiveInside ? .contain : .combine)
        switch behavior {
        case .combine:
            var parts: [AXLabelPart] = []
            axLabelParts(node, into: &parts, geometry: geometry)
            // The node's own info label is handled below; its descendants contribute here.
            if node.ax?.info.label == nil { fillLabel(&e, from: parts) }
        case .ignore: break
        case .contain: e.children = own
        }
        if let label = info.label { e.label = label; e.labelSources = [.explicit] }
        e.value = info.value
        e.hint = info.hint
        e.identifier = info.identifier
        e.actions = info.actions
        e.inputLabels = info.inputLabels
        e.sortPriority = info.sortPriority ?? 0
        e.activate = info.activate
        var traits = info.addTraits.subtracting(info.removeTraits)
        e.enabled = info.isEnabled ?? true
        if !e.enabled { traits.insert(.notEnabled) }
        // A combined single leaf keeps its nature (a Text with a tap gesture is still static text).
        if behavior == .combine, own.count == 1, traits.isDisjoint(with: [.button, .link, .toggle, .adjustable, .searchField]) {
            traits.formUnion(own[0].traits.intersection([.staticText, .image, .header]))
        }
        // Combined text-only content (a Label, a tappable row of texts) reads as static text.
        if behavior == .combine, traits.isEmpty, !e.label.isEmpty, e.labelSources.allSatisfy({ $0 == .text || $0 == .explicit }) {
            traits.insert(.staticText)
        }
        e.traits = traits
        if let role = info.role { e.role = role; e.roleIsDerived = false }
        e.refreshRole()
        e.interactive = e.enabled && (info.isTapTarget || !traits.isDisjoint(with: [.button, .link, .toggle, .adjustable, .searchField]))
        e.offscreen = geometry && !overlaps(r, ctx.visible)
        if e.interactive {
            e.rawHitFrame = r
            e.hitFrame = (info.systemHitSlop || ctx.inBar) ? expand(r) : r
        }
        return [e]
    }

    private func fillLabel(_ e: inout AXElement, from parts: [AXLabelPart]) {
        e.label = parts.map(\.text).joined(separator: ", ")
        e.labelSources = parts.map(\.source)
    }

    /// A node that is not an element still passes what it says down to the elements inside it.
    private func overlay(_ info: AccessibilityInfo, onto elements: inout [AXElement]) {
        guard !elements.isEmpty else { return }
        let single = elements.count == 1
        for i in elements.indices {
            if single, let label = info.label { elements[i].label = label; elements[i].labelSources = [.explicit] }
            if single, let value = info.value { elements[i].value = value }
            if elements[i].hint == nil, let hint = info.hint { elements[i].hint = hint }
            if elements[i].identifier == nil, let id = info.identifier { elements[i].identifier = id }
            elements[i].traits = elements[i].traits.subtracting(info.removeTraits).union(info.addTraits)
            for a in info.actions where !elements[i].actions.contains(a) { elements[i].actions.append(a) }
            if !info.inputLabels.isEmpty { elements[i].inputLabels = info.inputLabels }
            if let p = info.sortPriority { elements[i].sortPriority = p }
            if info.isEnabled == false {
                elements[i].enabled = false
                elements[i].traits.insert(.notEnabled)
                elements[i].interactive = false
            }
            elements[i].refreshRole()
        }
    }

    private func representationElements(_ node: Node, _ info: AccessibilityInfo, _ representation: [Node], _ r: CGRect, _ ctx: Ctx) -> [AXElement] {
        let sub = AXExtractor(screen: screen)
        sub.geometry = false
        var elements = sub.visitChildren(representation, Ctx(visible: screen))
        func place(_ e: inout AXElement) {
            e.frame = r
            e.offscreen = geometry && !overlaps(r, ctx.visible)
            if e.interactive { e.rawHitFrame = r; e.hitFrame = r }
            for i in e.children.indices { place(&e.children[i]) }
        }
        for i in elements.indices { place(&elements[i]) }
        var plain = info
        plain.label = info.label; plain.isElement = false; plain.representation = nil
        overlay(plain, onto: &elements)
        return elements
    }

    // MARK: Chrome

    private func backButton(_ node: BackButtonNode, _ ctx: Ctx) -> [AXElement] {
        var e = AXElement()
        var parts: [AXLabelPart] = []
        if let title = node.title { axLabelParts(title, into: &parts, geometry: geometry) }
        e.label = parts.isEmpty ? "Back" : parts.map(\.text).joined(separator: ", ")
        e.labelSources = [.text]
        e.traits = [.button]
        e.frame = rect(node)
        e.interactive = true
        e.rawHitFrame = e.frame
        e.hitFrame = expand(e.frame)
        e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
        e.refreshRole()
        return [e]
    }

    private func moreButton(_ node: EllipsisCircleNode, _ ctx: Ctx) -> [AXElement] {
        var e = AXElement()
        e.label = "More"
        e.labelSources = [.text]
        e.traits = [.button, .hasPopup]
        e.frame = rect(node)
        e.interactive = true
        e.rawHitFrame = e.frame
        e.hitFrame = expand(e.frame)
        e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
        e.refreshRole()
        return [e]
    }

    private func searchField(_ node: SearchFieldNode, _ ctx: Ctx) -> [AXElement] {
        var e = AXElement()
        let text = (node.children.first as? TextNode).map(axPlainText) ?? ""
        if node.showsPrompt {
            e.label = text.isEmpty ? "Search" : text
        } else {
            e.label = "Search"
            e.value = text
        }
        e.labelSources = [.text]
        e.traits = [.searchField]
        e.role = "searchField"
        e.roleIsDerived = false
        e.frame = rect(node)
        e.interactive = true
        e.rawHitFrame = e.frame
        e.hitFrame = expand(e.frame, toAtLeast: 44)
        e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
        return [e]
    }

    private func promoteToHeader(_ elements: [AXElement]) -> [AXElement] {
        elements.map { e in
            var e = e
            if e.role == "staticText" || e.role == "group" { e.traits.insert(.header); e.refreshRole() }
            return e
        }
    }

    private func navigationStack(_ n: NavigationStackNode, _ ctx: Ctx) -> [AXElement] {
        var barCtx = ctx
        barCtx.inBar = true
        var bar: [AXElement] = []
        bar += visitChildren(n.leading, barCtx)
        if let principal = n.principal { bar += visitChildren([principal], barCtx) }
        if let inline = n.inlineTitle { bar += promoteToHeader(visit(inline, ctx)) }
        if let large = n.largeTitle { bar += promoteToHeader(visit(large, ctx)) }
        if let subtitle = n.subtitle { bar += visit(subtitle, ctx) }
        bar += visitChildren(n.trailing, barCtx)
        // A Liquid Glass search field at the bottom of the screen is not part of the navigation bar.
        let searchAtBottom = n.search.map { $0.glassStyle == .bottom || $0.glassStyle == .minimized } ?? false
        if let search = n.search, !searchAtBottom { bar += visit(search, ctx) }

        var result: [AXElement] = []
        if !bar.isEmpty {
            let own = rect(n)
            let box = bar.dropFirst().reduce(bar[0].frame) { union($0, $1.frame) }
            var container = AXElement()
            container.role = "navigationBar"
            container.roleIsDerived = false
            container.frame = CGRect(x: own.minX, y: box.minY, width: own.width, height: box.height)
            container.children = bar
            container.offscreen = geometry && !overlaps(container.frame, ctx.visible)
            result.append(container)
        }
        result += visit(n.content, ctx)
        if let status = n.statusItem { result += visitChildren([status], barCtx) }
        if let bottom = n.bottomItems { result += visitChildren([bottom], barCtx) }
        if let search = n.search, searchAtBottom { result += visit(search, ctx) }
        return result
    }

    private func tabView(_ n: TabViewNode, _ ctx: Ctx) -> [AXElement] {
        var result = visit(n.content, ctx)
        if let accessory = n.accessory { result += visit(accessory, ctx) }
        guard !n.items.isEmpty else { return result }
        let own = rect(n)
        let width = own.width / CGFloat(n.items.count)
        let top = own.minY + n.barTop
        var tabs: [AXElement] = []
        for (i, item) in n.items.enumerated() {
            var parts: [AXLabelPart] = []
            if let title = item.title { axLabelParts(title, into: &parts, geometry: geometry) }
            if parts.isEmpty, let icon = item.icon { axLabelParts(icon, into: &parts, geometry: geometry) }
            var e = AXElement()
            e.label = parts.map(\.text).joined(separator: ", ")
            e.labelSources = parts.map(\.source)
            e.traits = i == n.selectedIndex ? [.button, .selected] : [.button]
            e.role = "tab"
            e.roleIsDerived = false
            if let badge = item.badge {
                var badgeParts: [AXLabelPart] = []
                axLabelParts(badge, into: &badgeParts, geometry: geometry)
                if !badgeParts.isEmpty { e.value = badgeParts.map(\.text).joined(separator: ", ") }
            }
            if let frames = n.glassItemFrames, frames.indices.contains(i) {
                e.frame = frames[i].offsetBy(dx: own.minX, dy: own.minY)
            } else {
                e.frame = CGRect(x: own.minX + width * CGFloat(i), y: top, width: width, height: TabBarMetrics.height)
            }
            e.interactive = true
            e.rawHitFrame = e.frame
            e.hitFrame = e.frame
            e.offscreen = geometry && !overlaps(e.frame, ctx.visible)
            tabs.append(e)
        }
        var bar = AXElement()
        bar.role = "tabBar"
        bar.roleIsDerived = false
        bar.traits = [.tabBar]
        bar.frame = n.glassBarFrame.map { $0.offsetBy(dx: own.minX, dy: own.minY) }
            ?? CGRect(x: own.minX, y: top, width: own.width, height: TabBarMetrics.height)
        bar.children = tabs
        bar.offscreen = geometry && !overlaps(bar.frame, ctx.visible)
        result.append(bar)
        return result
    }

    private func list(_ n: ListNode, _ ctx: Ctx) -> [AXElement] {
        var inner = ctx
        let own = CGRect(origin: n.absoluteOrigin, size: n.frame.size)
        let bleed = n.bleed
        let clip = CGRect(x: own.minX - bleed.leading, y: own.minY - bleed.top,
                          width: own.width + bleed.leading + bleed.trailing, height: own.height + bleed.top + bleed.bottom)
        inner.visible = intersect(ctx.visible, clip)
        var result: [AXElement] = []
        for section in n.sections {
            if let header = section.header { result += promoteToHeader(visit(header, inner)) }
            for row in section.rows { result += listRow(row, inner) }
            if let footer = section.footer { result += visit(footer, inner) }
        }
        return result
    }

    private func listRow(_ row: ListRowNode, _ ctx: Ctx) -> [AXElement] {
        if let info = row.ax?.info, info.hidden == true { return [] }
        let rowRect = rect(row)
        var elements = visit(row.content, ctx)
        if let badge = row.badge {
            let badgeElements = visit(badge, ctx)
            if elements.count == 1, elements[0].value == nil, let b = badgeElements.first { elements[0].value = b.label }
            else { elements += badgeElements }
        }
        // A single interactive element in a row is activated by touching anywhere in the row.
        let interactive = elements.indices.filter { elements[$0].interactive }
        if interactive.count == 1 && elements.count == 1 {
            let i = interactive[0]
            elements[i].hitFrame = rowRect
            elements[i].rawHitFrame = rowRect
            if elements[i].children.isEmpty { elements[i].frame = rowRect }
        }
        return elements
    }

    // MARK: Presentations

    private func host(_ n: PresentationHostNode, _ ctx: Ctx) -> [AXElement] {
        guard let top = n.layers.last else { return visitChildren(n.children, ctx) }
        // Everything under the topmost presentation is not reachable (VoiceOver treats it as modal).
        let saved = truncations
        obscuredCount += flatten(visitChildren([n.base] + n.layers.dropLast(), ctx)).count
        truncations = saved
        return layer(top, ctx)
    }

    private func layer(_ layer: PresentationLayerNode, _ ctx: Ctx) -> [AXElement] {
        switch layer {
        case let sheet as SheetLayerNode:
            modalKind = "sheet"
            let card = sheet.cardRect.offsetBy(dx: sheet.absoluteOrigin.x, dy: sheet.absoluteOrigin.y)
            var inner = ctx
            inner.visible = intersect(ctx.visible, card)
            return [modal(role: "sheet", frame: card, children: visit(sheet.content, inner), ctx)]
        case let cover as CoverLayerNode:
            modalKind = "fullScreenCover"
            return [modal(role: "sheet", frame: rect(cover), children: visit(cover.content, ctx), ctx)]
        case let dimmed as DimmedCardLayerNode:
            if let alert = dimmed.card as? AlertCardNode {
                modalKind = "alert"
                return [alertElement(alert, ctx)]
            }
            if let dialog = dimmed.card as? DialogCardNode {
                modalKind = "confirmationDialog"
                return [dialogElement(dialog, ctx)]
            }
            return visitChildren(layer.children, ctx)
        default:
            return visitChildren(layer.children, ctx)
        }
    }

    private func modal(role: String, frame: CGRect, children: [AXElement], _ ctx: Ctx) -> AXElement {
        var e = AXElement()
        e.role = role
        e.roleIsDerived = false
        e.traits = [.modal]
        e.frame = frame
        e.children = children
        e.offscreen = geometry && !overlaps(frame, ctx.visible)
        return e
    }

    private func actionButton(_ node: TextNode, cell: CGRect, _ ctx: Ctx) -> AXElement {
        var e = AXElement()
        e.label = axPlainText(node)
        e.labelSources = [.text]
        e.traits = [.button]
        e.frame = cell
        e.interactive = true
        e.rawHitFrame = cell
        e.hitFrame = cell
        e.offscreen = geometry && !overlaps(cell, ctx.visible)
        e.refreshRole()
        return e
    }

    private func alertElement(_ card: AlertCardNode, _ ctx: Ctx) -> AXElement {
        let box = rect(card)
        var kids: [AXElement] = []
        if let title = card.title { kids += promoteToHeader(visit(title, ctx)) }
        if let message = card.message { kids += visit(message, ctx) }
        let centers = card.actions.map { rect($0).midX }
        let sideBySide = card.actions.count == 2 && centers.allSatisfy { abs($0 - box.midX) > 1 }
        if let cells = card.glassActionCells, cells.count == card.actions.count {
            for (action, cell) in zip(card.actions, cells) {
                kids.append(actionButton(action, cell: cell.offsetBy(dx: box.minX, dy: box.minY), ctx))
            }
            return modal(role: "alert", frame: box, children: kids, ctx)
        }
        for action in card.actions {
            let t = rect(action)
            let h = AlertMetrics.actionHeight
            let cell = sideBySide
                ? CGRect(x: t.midX < box.midX ? box.minX : box.midX, y: t.midY - h / 2, width: box.width / 2, height: h)
                : CGRect(x: box.minX, y: t.midY - h / 2, width: box.width, height: h)
            kids.append(actionButton(action, cell: cell, ctx))
        }
        return modal(role: "alert", frame: box, children: kids, ctx)
    }

    private func dialogElement(_ card: DialogCardNode, _ ctx: Ctx) -> AXElement {
        let box = rect(card)
        var kids: [AXElement] = []
        if let title = card.title { kids += visit(title, ctx) }
        if let message = card.message { kids += visit(message, ctx) }
        if let cells = card.glassActionCells, cells.count == card.actions.count + 1 {
            for (action, cell) in zip(card.actions + [card.cancel], cells) {
                kids.append(actionButton(action, cell: cell.offsetBy(dx: box.minX, dy: box.minY), ctx))
            }
            return modal(role: "dialog", frame: box, children: kids, ctx)
        }
        for action in card.actions + [card.cancel] {
            let t = rect(action)
            let h = DialogMetrics.rowHeight
            kids.append(actionButton(action, cell: CGRect(x: box.minX, y: t.midY - h / 2, width: box.width, height: h), ctx))
        }
        return modal(role: "dialog", frame: box, children: kids, ctx)
    }
}
