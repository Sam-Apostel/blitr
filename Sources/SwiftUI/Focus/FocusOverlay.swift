// `--focus-overlay`: the frame dimmed, every focusable element outlined and numbered, the focused one
// highlighted, and an arrow for every move. A two-way move is one double-headed arrow; a one-way move
// is a dashed orange arrow with one head. Unreachable elements are red. A move to an element outside
// the screen runs to the screen edge and ends in a tag with the target's number.

@MainActor
enum FocusOverlay {
    static let reachable = RGBA(0.25, 0.78, 1.0, 1)
    static let focusedColor = RGBA(1, 1, 1, 1)
    static let unreachableColor = RGBA(1.0, 0.27, 0.23, 1)
    static let twoWay = RGBA(0.35, 0.95, 0.55, 1)
    static let oneWay = RGBA(1.0, 0.66, 0.15, 1)
    static let sectionColor = RGBA(0.75, 0.55, 1.0, 1)

    @MainActor struct Labeler {
        let env: EnvironmentValues
        let ctx: PlaceContext
        let p: Painter
        /// Draws `text` in a pill whose top-left (or centre) is at `point`. Returns the pill.
        @discardableResult
        func pill(_ text: String, at point: CGPoint, size: CGFloat, fill: RGBA, color: RGBA = RGBA(0, 0, 0, 1),
                  centered: Bool = false, within bounds: CGRect) -> CGRect {
            let node = Text(verbatim: text).font(.system(size: size, weight: .bold)).foregroundColor(Color(color)).makeNode(env)
            let s = node.sizeThatFits(.unspecified)
            let w = max(s.width + size * 0.8, s.height + 4), h = s.height + 4
            var r = CGRect(x: centered ? point.x - w / 2 : point.x, y: centered ? point.y - h / 2 : point.y, width: w, height: h)
            r.origin.x = min(max(bounds.minX + 2, r.minX), bounds.maxX - w - 2)
            r.origin.y = min(max(bounds.minY + 2, r.minY), bounds.maxY - h - 2)
            p.fill(Path(roundedRect: r, cornerRadius: h / 2, style: .circular), with: .color(fill), in: r)
            node.place(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2), size: s, ctx)
            node.draw(p)
            return r
        }
    }

    static func draw(_ map: FocusMap, painter p: Painter, canvasSize: CGSize, scale: CGFloat) {
        let snap = map.snap
        let bounds = CGRect(origin: .zero, size: canvasSize)
        p.fill(Path(bounds), with: .color(RGBA(0, 0, 0, 0.55)), in: bounds)
        var env = EnvironmentValues()
        env.colorScheme = .dark
        env.displayScale = scale
        let labeler = Labeler(env: env, ctx: PlaceContext(origin: .zero, container: bounds, safeRect: bounds, scale: scale), p: p)
        // Sizes scale with the screen so a 1920x1080 TV frame and a phone both read well.
        let unit = max(1, min(canvasSize.width, canvasSize.height) / 540)
        let line = 2 * unit

        // Explicit focus sections, dashed.
        for s in snap.sections where s.kind == "focusSection" && !s.members.isEmpty {
            let r = s.frame.insetBy(dx: -3 * unit, dy: -3 * unit)
            p.stroke(Path(roundedRect: r, cornerRadius: 8 * unit, style: .continuous), with: .color(sectionColor),
                     style: StrokeStyle(lineWidth: 1.5 * unit, dash: [6 * unit, 4 * unit]), in: r)
        }

        // Element outlines.
        for (i, e) in snap.elements.enumerated() {
            let unreachable = map.paths[i] == nil
            let color = i == map.focused ? focusedColor : unreachable ? unreachableColor : reachable
            let r = e.frame
            let path = Path(roundedRect: r, cornerRadius: min(8 * unit, min(r.width, r.height) / 4), style: .continuous)
            p.fill(path, with: .color(color.opacity(0.1)), in: r)
            p.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: i == map.focused ? 2 * line : line), in: r)
        }

        // Arrows, from on-screen elements only (a move between two off-screen elements is in the JSON).
        func onScreen(_ i: Int) -> Bool { snap.elements[i].frame.intersects(bounds) }
        for i in snap.elements.indices where onScreen(i) {
            for d in FocusMap.directions {
                guard let t = map.moves[i][d] else { continue }
                let back = map.moves[t][FocusMovement.opposite(d)] == i
                if back && t < i && onScreen(t) { continue } // a two-way pair is drawn once
                let (from, to) = endpoints(snap.elements[i].frame, snap.elements[t].frame, d)
                drawArrow(p, from: from, to: to, twoWay: back, unit: unit, bounds: bounds,
                          offscreenTarget: bounds.insetBy(dx: 2, dy: 2).contains(to) ? nil : "#\(snap.elements[t].index)", labeler: labeler)
            }
        }

        // Numbers (on top of everything), at the visible corner of each element.
        for (i, e) in snap.elements.enumerated() where onScreen(i) {
            let unreachable = map.paths[i] == nil
            let fill = i == map.focused ? focusedColor : unreachable ? unreachableColor : reachable
            var text = "\(e.index)"
            if i == map.initial { text += " start" }
            let corner = e.frame.intersection(bounds)
            labeler.pill(text, at: CGPoint(x: corner.minX - 6 * unit, y: corner.minY - 6 * unit), size: 11 * unit, fill: fill, within: bounds)
        }

        // Legend.
        let unreachable = map.paths.filter { $0 == nil }.count
        var legend = "\(snap.elements.count) focusable · white: focused · blue: reachable · red: unreachable (\(unreachable)) · green ⟷ two-way · orange ⇢ one-way"
        if snap.sections.contains(where: { $0.kind == "focusSection" && !$0.members.isEmpty }) { legend += " · purple dashed: focusSection" }
        if snap.elements.isEmpty { legend = "No focusable elements" }
        labeler.pill(legend, at: CGPoint(x: 8 * unit, y: 6 * unit), size: 10 * unit, fill: RGBA(0, 0, 0, 0.8),
                     color: RGBA(1, 1, 1, 1), within: bounds)
    }

    /// Start and end of the arrow for a move from `a` to `b`: facing edges, at the middle of the
    /// overlap across the move (the beam), or at the centres when they do not overlap.
    static func endpoints(_ a: CGRect, _ b: CGRect, _ d: MoveCommandDirection) -> (CGPoint, CGPoint) {
        switch d {
        case .up, .down:
            let lo = max(a.minX, b.minX), hi = min(a.maxX, b.maxX)
            let x1 = hi > lo ? (lo + hi) / 2 : a.midX, x2 = hi > lo ? (lo + hi) / 2 : b.midX
            return d == .down ? (CGPoint(x: x1, y: a.maxY), CGPoint(x: x2, y: b.minY)) : (CGPoint(x: x1, y: a.minY), CGPoint(x: x2, y: b.maxY))
        case .left, .right:
            let lo = max(a.minY, b.minY), hi = min(a.maxY, b.maxY)
            let y1 = hi > lo ? (lo + hi) / 2 : a.midY, y2 = hi > lo ? (lo + hi) / 2 : b.midY
            return d == .right ? (CGPoint(x: a.maxX, y: y1), CGPoint(x: b.minX, y: y2)) : (CGPoint(x: a.minX, y: y1), CGPoint(x: b.maxX, y: y2))
        }
    }

    static func drawArrow(_ p: Painter, from: CGPoint, to target: CGPoint, twoWay: Bool, unit: CGFloat, bounds: CGRect,
                          offscreenTarget: String?, labeler: Labeler) {
        var to = target
        if offscreenTarget != nil { to = clip(from: from, to: target, in: bounds.insetBy(dx: 2, dy: 2)) }
        var from = from
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        let color = twoWay ? twoWay_ : oneWay
        let head = 7 * unit
        // Touching elements still get a visible arrow: stretch it across the gap.
        if length < head * 2.2 {
            let ux = length > 0.01 ? dx / length : 0, uy = length > 0.01 ? dy / length : 1
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            from = CGPoint(x: mid.x - ux * head * 1.4, y: mid.y - uy * head * 1.4)
            to = CGPoint(x: mid.x + ux * head * 1.4, y: mid.y + uy * head * 1.4)
        }
        let len = hypot(to.x - from.x, to.y - from.y)
        guard len > 0.01 else { return }
        let ux = (to.x - from.x) / len, uy = (to.y - from.y) / len
        let shaftStart = twoWay ? CGPoint(x: from.x + ux * head, y: from.y + uy * head) : from
        let shaftEnd = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        var shaft = Path()
        shaft.move(to: shaftStart)
        shaft.addLine(to: shaftEnd)
        let box = CGRect(x: min(from.x, to.x) - head, y: min(from.y, to.y) - head, width: abs(to.x - from.x) + 2 * head, height: abs(to.y - from.y) + 2 * head)
        // Dark casing first so arrows read on any background.
        p.stroke(shaft, with: .color(RGBA(0, 0, 0, 0.7)), style: StrokeStyle(lineWidth: 4.5 * unit, lineCap: .round), in: box)
        p.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .round,
                                                                dash: twoWay ? [] : [5 * unit, 3.5 * unit]), in: box)
        arrowHead(p, tip: to, ux: ux, uy: uy, size: head, color: color, box: box)
        if twoWay { arrowHead(p, tip: from, ux: -ux, uy: -uy, size: head, color: color, box: box) }
        if let label = offscreenTarget {
            labeler.pill("→ " + label, at: to, size: 10 * unit, fill: color, centered: true, within: bounds)
        }
    }

    private static let twoWay_ = twoWay

    static func arrowHead(_ p: Painter, tip: CGPoint, ux: CGFloat, uy: CGFloat, size: CGFloat, color: RGBA, box: CGRect) {
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        let nx = -uy * size * 0.6, ny = ux * size * 0.6
        var tri = Path()
        tri.move(to: tip)
        tri.addLine(to: CGPoint(x: base.x + nx, y: base.y + ny))
        tri.addLine(to: CGPoint(x: base.x - nx, y: base.y - ny))
        tri.closeSubpath()
        p.stroke(tri, with: .color(RGBA(0, 0, 0, 0.7)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round), in: box)
        p.fill(tri, with: .color(color), in: box)
    }

    /// Where the segment from `a` (inside `r`) towards `b` leaves `r`.
    static func clip(from a: CGPoint, to b: CGPoint, in r: CGRect) -> CGPoint {
        var t: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        if dx > 0, b.x > r.maxX { t = min(t, (r.maxX - a.x) / dx) }
        if dx < 0, b.x < r.minX { t = min(t, (r.minX - a.x) / dx) }
        if dy > 0, b.y > r.maxY { t = min(t, (r.maxY - a.y) / dy) }
        if dy < 0, b.y < r.minY { t = min(t, (r.minY - a.y) / dy) }
        t = max(0, t)
        return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
    }
}
