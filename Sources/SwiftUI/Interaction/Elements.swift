// The elements scripted steps can address, and selector resolution.
//
// Elements come from the accessibility tree of the current frame (labels, identifiers, roles, frames,
// hit areas). What a tap does comes from the element's own default action, else from the focus engine's
// element at the same place (`Runtime.activations`: toggles, picker segments, navigation links, tabs,
// alert buttons), else from system chrome the capture knows (the back button).

enum Selector: Equatable, CustomStringConvertible {
    /// `#3`: the third interactive element in reading order.
    case index(Int)
    /// `@120,400`: the topmost interactive element at a point.
    case point(CGPoint)
    /// An accessibility identifier or a label; `nth` picks one of several matches (`"Delete"[2]`).
    case text(String, nth: Int?)
    /// `first` (scroll steps): the first scrollable container.
    case first

    var description: String {
        switch self {
        case .index(let n): return "#\(n)"
        case .point(let p): return "@\(AnimationDefaults.format(Double(p.x))),\(AnimationDefaults.format(Double(p.y)))"
        case .text(let s, let nth): return "\"\(s)\"" + (nth.map { "[\($0)]" } ?? "")
        case .first: return "first"
        }
    }
}

struct InteractionElement {
    var index = 0
    var ax: AXElement
    var label: String { ax.label }
    var role: String { ax.role }
    var frame: CGRect { ax.frame }
    var isInteractive: Bool { ax.interactive }

    var summary: String {
        var s = "#\(index) \(role)"
        if !label.isEmpty { s += " \"\(label)\"" }
        if let id = ax.identifier { s += " id:\(id)" }
        if let v = ax.value, !v.isEmpty { s += " = \(v)" }
        s += " [\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))]"
        return s
    }
}

@MainActor
final class ElementIndex {
    let root: Node
    let runtime: Runtime
    /// Interactive elements in reading order (what `#n` counts).
    private(set) var elements: [InteractionElement] = []
    /// Everything else with a label (static text, images): addressable to find a row to swipe or scroll to.
    private(set) var passive: [InteractionElement] = []
    private var handlerNodes: [(frame: CGRect, handlers: InteractionHandlers, box: ObjectIdentifier)] = []
    private var backButtons: [CGRect] = []

    init(root: Node, screen: CGRect, runtime: Runtime) {
        self.root = root
        self.runtime = runtime
        let extractor = AXExtractor(screen: screen)
        func flatten(_ list: [AXElement]) {
            for e in list {
                if e.interactive {
                    elements.append(InteractionElement(index: elements.count + 1, ax: e))
                } else if !e.label.isEmpty || e.identifier != nil {
                    passive.append(InteractionElement(index: 0, ax: e))
                }
                flatten(e.children)
            }
        }
        flatten(extractor.extract(root))
        collect(root)
    }

    /// `toScreen` maps layout frames to the screen (a scaled floating sheet's content).
    private func collect(_ node: Node, toScreen: (CGRect) -> CGRect = { $0 }) {
        if let box = node.ax, let h = InteractionRegistry.handlers[ObjectIdentifier(box)] {
            handlerNodes.append((toScreen(CGRect(origin: node.absoluteOrigin, size: node.frame.size)), h, ObjectIdentifier(box)))
        }
        if node is BackButtonNode { backButtons.append(toScreen(CGRect(origin: node.absoluteOrigin, size: node.frame.size))) }
        // Only the topmost presentation takes input.
        if let host = node as? PresentationHostNode, let top = host.layers.last {
            collect(top, toScreen: toScreen)
            return
        }
        if let sheet = node as? SheetLayerNode, sheet.contentScale != 1 {
            for child in node.children { collect(child, toScreen: sheet.contentToScreen) }
            return
        }
        for child in node.children { collect(child, toScreen: toScreen) }
    }

    // MARK: Selectors

    func listing(_ list: [InteractionElement]? = nil, limit: Int = 40) -> String {
        let shown = list ?? elements
        var lines = shown.prefix(limit).map { "  " + $0.summary }
        if shown.count > limit { lines.append("  ... and \(shown.count - limit) more") }
        return lines.isEmpty ? "  (no interactive elements on screen)" : lines.joined(separator: "\n")
    }

    /// The element a selector names. `interactiveOnly` is false for steps that only need a place
    /// (scroll-to, swipe on a row found by its text).
    func resolve(_ selector: Selector, step: String, interactiveOnly: Bool = true) throws -> InteractionElement {
        switch selector {
        case .first:
            throw RenderError("\(step): `first` only names a scroll view (scroll first <dy>)")
        case .index(let n):
            guard elements.indices.contains(n - 1) else {
                throw RenderError("\(step): there is no element #\(n); the screen has \(elements.count) interactive elements:\n\(listing())")
            }
            return elements[n - 1]
        case .point(let p):
            let hits = elements.filter { ($0.ax.hitFrame ?? $0.frame).contains(p) && !$0.ax.offscreen }
            // The smallest hit area is the innermost control; later elements are drawn on top.
            guard let best = hits.enumerated().min(by: { a, b in
                let ra = a.element.ax.hitFrame ?? a.element.frame, rb = b.element.ax.hitFrame ?? b.element.frame
                let (sa, sb) = (ra.width * ra.height, rb.width * rb.height)
                return abs(sa - sb) > 0.5 ? sa < sb : a.offset > b.offset
            }) else {
                throw RenderError("\(step): no interactive element at \(selector). Elements:\n\(listing())")
            }
            return best.element
        case .text(let text, let nth):
            let pool = interactiveOnly ? [elements] : [elements, passive]
            var candidates: [InteractionElement] = []
            for list in pool {
                candidates = list.filter { $0.ax.identifier == text }
                if candidates.isEmpty { candidates = list.filter { $0.label == text } }
                if candidates.isEmpty { candidates = list.filter { $0.label.range(of: text, options: .caseInsensitive) != nil } }
                if !candidates.isEmpty { break }
            }
            // An on-screen match wins over ones scrolled out of view.
            let visible = candidates.filter { !$0.ax.offscreen }
            if nth == nil, visible.count == 1 { return visible[0] }
            if let nth {
                guard candidates.indices.contains(nth - 1) else {
                    throw RenderError("\(step): \(selector) asks for match \(nth), but \"\(text)\" matches \(candidates.count):\n\(listing(candidates))")
                }
                return candidates[nth - 1]
            }
            if candidates.count == 1 { return candidates[0] }
            if candidates.isEmpty {
                var message = "\(step): nothing on screen matches \"\(text)\" (by accessibility identifier, label, or part of a label)."
                if interactiveOnly, let hint = passive.first(where: { $0.label.range(of: text, options: .caseInsensitive) != nil }) {
                    message += " There is \(hint.role) \"\(hint.label)\", but it is not interactive."
                }
                throw RenderError(message + " Interactive elements:\n\(listing())")
            }
            throw RenderError("\(step): \"\(text)\" is ambiguous; it matches \(candidates.count) elements. Use #index, an accessibility identifier, or \"\(text)\"[n]:\n\(listing(visible.isEmpty ? candidates : visible))")
        }
    }

    // MARK: Capabilities

    /// Handlers recorded for the element: its own, else those of the innermost control around its centre.
    func handlers(for element: InteractionElement, where has: (InteractionHandlers) -> Bool) -> InteractionHandlers? {
        if let id = element.ax.boxID, let own = handlerNodes.first(where: { $0.box == id && has($0.handlers) }) { return own.handlers }
        let c = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let around = handlerNodes.filter { has($0.handlers) && $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(c) }
        return around.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.handlers
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let w = min(a.maxX, b.maxX) - max(a.minX, b.minX), h = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard w > 0, h > 0 else { return 0 }
        let union = a.width * a.height + b.width * b.height - w * h
        return union > 0 ? w * h / union : 0
    }

    enum TapAction {
        case run(@MainActor () -> Void)
        case back
    }

    /// What tapping the element does, or nil when it has no action the capture can run.
    func tapAction(_ element: InteractionElement) -> TapAction? {
        if let activate = element.ax.activate { return .run(activate) }
        let frame = element.frame, hit = element.ax.rawHitFrame ?? frame
        if backButtons.contains(where: { overlap($0, frame) > 0.5 || overlap($0, hit) > 0.5 }) { return .back }
        // The focus engine's element at the same place knows the control's action.
        let snapshot = runtime.focus.snapshot
        var best: (CGFloat, FocusElement)?
        for f in snapshot.elements {
            let score = max(overlap(f.frame, frame), overlap(f.frame, hit))
            if score > 0.3, best == nil || score > best!.0 { best = (score, f) }
        }
        if best == nil {
            // A control inside a larger accessibility element (or the reverse): take the one at its centre.
            let c = CGPoint(x: frame.midX, y: frame.midY)
            let inside = snapshot.elements.filter { $0.frame.contains(c) || frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            if inside.count == 1 { best = (0, inside[0]) }
        }
        if let f = best?.1, let action = f.activate ?? runtime.activations.action(for: f.path) { return .run(action) }
        return nil
    }

    // MARK: Scroll views

    struct Scrollable {
        var path: IdentityPath
        var viewport: CGRect
        var maxOffset: CGPoint
        var axes: Axis.Set
        var node: Node
    }

    /// Scrollable containers of the topmost presentation, outermost first.
    func scrollables() -> [Scrollable] {
        var found: [Scrollable] = []
        func visit(_ node: Node) {
            if let host = node as? PresentationHostNode, let top = host.layers.last { visit(top); return }
            let own = CGRect(origin: node.absoluteOrigin, size: node.frame.size)
            if let s = node as? ScrollNode, let path = s.identity {
                let content = s.content.frame.size
                found.append(Scrollable(path: path, viewport: own,
                                        maxOffset: CGPoint(x: max(0, content.width + s.margins.horizontal - own.width),
                                                           y: max(0, content.height + s.margins.vertical - own.height)),
                                        axes: s.axes, node: s))
            } else if let l = node as? ListNode, let path = l.scrollIdentity {
                found.append(Scrollable(path: path, viewport: own, maxOffset: CGPoint(x: 0, y: max(0, l.contentHeight - own.height)),
                                        axes: .vertical, node: l))
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        return found
    }

    /// The innermost scrollable around an element's frame.
    func scrollable(around frame: CGRect) -> Scrollable? {
        let c = CGPoint(x: frame.midX, y: frame.midY)
        func contains(_ node: Node) -> Bool {
            var stack = [node]
            while let n = stack.popLast() {
                let r = CGRect(origin: n.absoluteOrigin, size: n.frame.size)
                if n.children.isEmpty, r.insetBy(dx: -0.5, dy: -0.5).contains(c), r.width > 0 { return true }
                stack.append(contentsOf: n.children)
            }
            return false
        }
        return scrollables().last { contains($0.node) }
    }
}
