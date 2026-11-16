// The focus engine: which element has focus, and where each Siri Remote press moves it.
//
// Every resolve/layout pass ends with `FocusEngine.afterLayout`, which
//  1. extracts the focusable elements with global frames from the laid-out tree (`FocusExtractor`),
//  2. reconciles `@FocusState` (code that set a state moves focus; focus moving writes the state),
//  3. on tvOS gives the screen its initial focus (or restores the last focused element after a
//     presentation is dismissed or a screen popped),
//  4. scrolls scroll views / lists so the focused element is visible.
// Any change asks the renderer for another pass, so `isFocused` and the focus effect show up.
//
// Movement (`target(from:_:)`) approximates UIKit's focus engine; see docs/FOCUS.md for the rules.

// MARK: - Snapshot types

struct ScrollRef {
    let path: IdentityPath
    let axes: Axis.Set
    /// The scroll view's frame (absolute): what it shows.
    let viewport: CGRect
    /// Largest offset on each axis.
    let maxOffset: CGPoint
}

struct FocusElement {
    var path: IdentityPath
    var id = ""
    var index = 0
    var label = ""
    var role: String
    var frame: CGRect
    var visible: Bool
    /// Indices into `FocusSnapshot.sections`, outermost first.
    var sections: [Int]
    /// Records on the element and its ancestors, outermost first.
    var chain: [FocusRecord]
    /// Enclosing scroll views / lists, outermost first.
    var scrolls: [ScrollRef]
    var activate: (@MainActor () -> Void)?
    /// System chrome made by the extractor (tab item, alert action, search field): no view-level focus effect.
    var synthesized = false
    var isTab = false
}

struct FocusSection {
    var key: ObjectIdentifier?
    var path: IdentityPath
    var id = ""
    /// "focusSection", "tabBar" or "list".
    var kind: String
    var frame: CGRect
    var members: [Int] = []
    /// Element entered when a move reaches the section (the tab bar: the selected tab).
    var preferred: Int?
}

@MainActor
final class FocusSnapshot {
    var elements: [FocusElement] = []
    var sections: [FocusSection] = []
    var screen: CGRect = .zero
    var modalKind: String?
    var dismissTop: (@MainActor () -> Void)?
    var byPath: [IdentityPath: Int] = [:]
    /// Element index the initial-focus rule picks for this screen.
    var initial: Int?
    private var moveCache: [Int: [MoveCommandDirection: Int?]] = [:]

    func index(of path: IdentityPath?) -> Int? { path.flatMap { byPath[$0] } }

    func moves(_ i: Int) -> [MoveCommandDirection: Int?] {
        if let cached = moveCache[i] { return cached }
        var result: [MoveCommandDirection: Int?] = [:]
        for d in [MoveCommandDirection.up, .down, .left, .right] { result[d] = FocusMovement.target(from: i, d, in: self) }
        moveCache[i] = result
        return result
    }
    func move(_ i: Int, _ d: MoveCommandDirection) -> Int? { moves(i)[d] ?? nil }
}

// MARK: - Movement

@MainActor
enum FocusMovement {
    struct Score: Comparable {
        var distance: CGFloat, overlap: CGFloat, leading: CGFloat, centre: CGFloat
        /// Ties on distance and overlap go to the candidate whose leading (top) edge is nearest the origin's
        /// (measured: tvOS 26.5, down from a full-width row onto three equal segments lands on the first).
        static func < (a: Score, b: Score) -> Bool {
            if abs(a.distance - b.distance) > 0.5 { return a.distance < b.distance }
            if abs(a.overlap - b.overlap) > 0.5 { return a.overlap > b.overlap }
            if abs(a.leading - b.leading) > 0.5 { return a.leading < b.leading }
            return a.centre < b.centre
        }
    }

    /// How `r` scores as a move target from `o` in direction `d`; nil when it is not beyond `o`'s edge
    /// in that direction or not inside the beam `o` sweeps.
    static func score(from o: CGRect, to r: CGRect, _ d: MoveCommandDirection) -> Score? {
        let tolerance: CGFloat = 1
        let distance: CGFloat, overlap: CGFloat
        switch d {
        case .down:
            guard r.minY >= o.maxY - tolerance, r.midY > o.midY else { return nil }
            distance = max(0, r.minY - o.maxY); overlap = min(r.maxX, o.maxX) - max(r.minX, o.minX)
        case .up:
            guard r.maxY <= o.minY + tolerance, r.midY < o.midY else { return nil }
            distance = max(0, o.minY - r.maxY); overlap = min(r.maxX, o.maxX) - max(r.minX, o.minX)
        case .right:
            guard r.minX >= o.maxX - tolerance, r.midX > o.midX else { return nil }
            distance = max(0, r.minX - o.maxX); overlap = min(r.maxY, o.maxY) - max(r.minY, o.minY)
        case .left:
            guard r.maxX <= o.minX + tolerance, r.midX < o.midX else { return nil }
            distance = max(0, o.minX - r.maxX); overlap = min(r.maxY, o.maxY) - max(r.minY, o.minY)
        }
        guard overlap > 0.5 else { return nil }
        let leading = d == .up || d == .down ? abs(r.minX - o.minX) : abs(r.minY - o.minY)
        return Score(distance: distance, overlap: overlap, leading: leading, centre: hypot(r.midX - o.midX, r.midY - o.midY))
    }

    static func target(from i: Int, _ d: MoveCommandDirection, in snap: FocusSnapshot) -> Int? {
        let origin = snap.elements[i].frame
        var best: (Score, Int)?
        for (j, e) in snap.elements.enumerated() where j != i {
            guard let s = score(from: origin, to: e.frame, d) else { continue }
            if best == nil || s < best!.0 { best = (s, j) }
        }
        var bestSection: (Score, Int)?
        for (k, section) in snap.sections.enumerated() where !section.members.contains(i) && !section.members.isEmpty {
            guard let s = score(from: origin, to: section.frame, d) else { continue }
            if bestSection == nil || s < bestSection!.0 { bestSection = (s, k) }
        }
        // A section is a target in its own right: the beam reaching it first takes focus into it.
        // The tab bar also wins a tie with its own items: entering it lands on the selected tab.
        if let (s, k) = bestSection,
           best == nil || s.distance < best!.0.distance - 0.5
            || (snap.sections[k].kind == "tabBar" && s.distance <= best!.0.distance + 0.5) {
            return entry(into: snap.sections[k], from: origin, snap)
        }
        if best == nil, d == .right, let leave = leavingSidebar(from: i, in: snap) { return leave }
        return best?.1
    }

    /// Right from a tab of a `.sidebarAdaptable` sidebar (a tab bar section narrower than the screen) with nothing
    /// in its beam: focus goes into the content, to its element nearest the tab (measured: tvOS 26.5 simulator,
    /// right from the "Home" row lands on the first poster, below the sidebar's row and partly behind it).
    static func leavingSidebar(from i: Int, in snap: FocusSnapshot) -> Int? {
        guard snap.elements[i].isTab,
              snap.sections.contains(where: { $0.kind == "tabBar" && $0.members.contains(i) && $0.frame.width < snap.screen.width - 1 })
        else { return nil }
        let origin = snap.elements[i].frame
        return snap.elements.indices.filter { !snap.elements[$0].isTab && $0 != i }.min { a, b in
            let da = rectDistance(origin, snap.elements[a].frame), db = rectDistance(origin, snap.elements[b].frame)
            if abs(da - db) > 0.5 { return da < db }
            return snap.elements[a].frame.minX < snap.elements[b].frame.minX
        }
    }

    /// The element focus lands on when it enters `section` from `origin` (history-free: the nearest one).
    static func entry(into section: FocusSection, from origin: CGRect, _ snap: FocusSnapshot) -> Int? {
        if let preferred = section.preferred { return preferred }
        return section.members.min { a, b in
            let ra = snap.elements[a].frame, rb = snap.elements[b].frame
            let da = rectDistance(origin, ra), db = rectDistance(origin, rb)
            if abs(da - db) > 0.5 { return da < db }
            return hypot(ra.midX - origin.midX, ra.midY - origin.midY) < hypot(rb.midX - origin.midX, rb.midY - origin.midY)
        }
    }

    static func rectDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX)), dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return hypot(dx, dy)
    }

    static func opposite(_ d: MoveCommandDirection) -> MoveCommandDirection {
        switch d { case .up: .down; case .down: .up; case .left: .right; case .right: .left }
    }
}

// MARK: - Navigation pushes made by `select`

enum NavigationPush {
    case view(AnyView)
    case value(AnyHashable)
}

// MARK: - Engine

@MainActor
final class FocusEngine {
    /// The focused element (nil: nothing has focus).
    private(set) var focusedPath: IdentityPath?
    /// Previously focused elements, most recent last (restored when a presentation goes away).
    private var history: [IdentityPath] = []
    /// A focus change asked for by `--focus` or a press, applied at the next extraction.
    var requestedPath: IdentityPath?
    /// Automatic initial focus (tvOS only, so other platforms render exactly as before).
    var automaticInitialFocus = false
    /// Per scroll view / list: the content offset, keyed by identity.
    var scrollOffsets: [IdentityPath: CGPoint] = [:]
    /// The focused element when code last scrolled (`ScrollViewProxy.scrollTo`): while it keeps focus the
    /// engine does not scroll it back into its margins, as tvOS only scrolls to an element when focus moves.
    var scrolledByCodeAt: IdentityPath?
    /// True while a remote press runs its handlers, so `@Environment(\.dismiss)` acts as it does on a device.
    var handlingPress = false
    /// TabViews without a selection binding: the tab chosen by `select`.
    var tabSelections: [IdentityPath: Int] = [:]
    /// Screens pushed onto a navigation stack by `select` on a NavigationLink.
    var pushes: [IdentityPath: [NavigationPush]] = [:]
    private var lastBindingValues: [ObjectIdentifier: AnyHashable] = [:]
    private(set) var snapshot = FocusSnapshot()
    /// Where focus started on the current screen (the initial-focus rule, a @FocusState set in
    /// onAppear, or `--focus`). The map's press paths start here.
    var initialPath: IdentityPath?
    /// Set once a press moved focus; a @FocusState change after that no longer counts as initial focus.
    var userMoved = false

    /// The frame of the focused element when it is chrome without a focused look of its own. Tab items,
    /// alert buttons and the search field draw their own tvOS focused state (Chrome/TV).
    var focusedChromeFrame: CGRect? {
        guard let i = snapshot.index(of: focusedPath), snapshot.elements[i].synthesized,
              !["tab", "alertAction", "searchField"].contains(snapshot.elements[i].role) else { return nil }
        return snapshot.elements[i].frame
    }

    func setFocus(_ path: IdentityPath?) {
        guard path != focusedPath else { return }
        if let old = focusedPath {
            history.removeAll { $0 == old }
            history.append(old)
            if history.count > 64 { history.removeFirst() }
        }
        focusedPath = path
    }

    /// Runs after each layout. Returns true when another pass is needed.
    func afterLayout(_ root: Node, screen: CGRect, runtime: Runtime) -> Bool {
        let snap = FocusExtractor(screen: screen, engine: self).extract(root)
        for e in snap.elements where e.synthesized { runtime.activations.register(e.path, e.activate) }
        snapshot = snap
        var changed = false
        var next = focusedPath

        // Code that changed a @FocusState moves focus.
        let groups = bindingGroups(snap)
        var bindingRequest: IdentityPath?
        for (storage, regions) in groups {
            let current = regions[0].binding.get()
            let unfocused = regions[0].binding.unfocused
            let changedByCode = lastBindingValues[storage].map { $0 != current } ?? (current != unfocused)
            guard changedByCode else { continue }
            if current == unfocused {
                if let f = snap.index(of: next), regions.contains(where: { $0.members.contains(f) }) {
                    runtime.warn("A @FocusState was set to \(unfocused.map { "\($0.base)" } ?? "nil") while its view had focus; tvOS would move focus to another element, here focus stays where it is")
                }
            } else if let region = regions.first(where: { $0.binding.target == current }), let first = region.members.first {
                bindingRequest = snap.elements[first].path
            } else {
                runtime.warn("A @FocusState was set to \(current.base), but no focusable view on screen is bound to that value with .focused(_:equals:)")
            }
        }
        if let requested = requestedPath {
            requestedPath = nil
            if snap.byPath[requested] != nil { next = requested }
        } else if let bindingRequest {
            next = bindingRequest
            if !userMoved { initialPath = bindingRequest }
        }

        if snap.index(of: next) == nil { next = nil }
        snap.initial = initialFocus(snap, runtime: runtime)
        if next == nil, automaticInitialFocus {
            if let restored = history.reversed().first(where: { snap.byPath[$0] != nil }) {
                next = restored
            } else if let initial = snap.initial {
                next = snap.elements[initial].path
                initialPath = next
                userMoved = false
            }
        }

        // Focus writes the state back.
        let focusedIndex = snap.index(of: next)
        for (storage, regions) in groups {
            let binding = regions[0].binding
            let current = binding.get()
            let inside = focusedIndex.flatMap { f in regions.first { $0.members.contains(f) } }
            let desired = inside?.binding.target ?? binding.unfocused
            if let desired, desired != current {
                binding.set(desired)
                lastBindingValues[storage] = desired
                changed = true
            } else {
                lastBindingValues[storage] = current
            }
        }

        if let f = focusedIndex {
            // tvOS: focus on a tab item selects that tab (the content switches as focus moves along the bar).
            if automaticInitialFocus, snap.elements[f].isTab,
               snap.elements[f].sections.contains(where: { snap.sections[$0].kind == "tabBar" && snap.sections[$0].preferred != f }),
               let select = snap.elements[f].activate {
                select()
                changed = true
            }
        }
        if scrolledByCodeAt != nil, focusedIndex.map({ snap.elements[$0].path }) != scrolledByCodeAt { scrolledByCodeAt = nil }
        if let f = focusedIndex, snap.elements[f].path != scrolledByCodeAt, scrollIntoView(snap.elements[f]) { changed = true }
        if next != focusedPath {
            setFocus(next)
            changed = true
        }
        return changed
    }

    // MARK: @FocusState regions

    struct BindingRegion {
        var binding: FocusBinding
        var members: [Int]
    }

    private func bindingGroups(_ snap: FocusSnapshot) -> [(ObjectIdentifier, [BindingRegion])] {
        var order: [ObjectIdentifier] = []
        var regions: [ObjectIdentifier: [ObjectIdentifier: BindingRegion]] = [:]
        var regionOrder: [ObjectIdentifier: [ObjectIdentifier]] = [:]
        for (i, e) in snap.elements.enumerated() {
            for record in e.chain {
                guard case .binding(let b) = record.kind else { continue }
                let key = ObjectIdentifier(record)
                if regions[b.storage] == nil { order.append(b.storage); regions[b.storage] = [:]; regionOrder[b.storage] = [] }
                if regions[b.storage]![key] == nil {
                    regions[b.storage]![key] = BindingRegion(binding: b, members: [])
                    regionOrder[b.storage]!.append(key)
                }
                regions[b.storage]![key]!.members.append(i)
            }
        }
        return order.map { s in (s, regionOrder[s]!.map { regions[s]![$0]! }) }
    }

    // MARK: Initial focus

    /// `defaultFocus`, then `prefersDefaultFocus(in:)` inside its `focusScope`, then the selected tab
    /// of a tab bar, then the visible element nearest the top-leading corner of the screen (measured:
    /// tvOS 26.5 starts on the first poster below a centred bar of buttons, and on the first list row rather
    /// than a toolbar button beside the navigation title).
    func initialFocus(_ snap: FocusSnapshot, runtime: Runtime) -> Int? {
        guard !snap.elements.isEmpty else { return nil }
        // defaultFocus(binding, value): an element under the modifier bound to that value.
        var seenDefaults: Set<ObjectIdentifier> = []
        for e in snap.elements {
            for record in e.chain {
                guard case .defaultFocus(let storage, let value) = record.kind, seenDefaults.insert(ObjectIdentifier(record)).inserted else { continue }
                let under = snap.elements.indices.filter { snap.elements[$0].chain.contains { $0 === record } }
                func bound(_ i: Int) -> Bool {
                    snap.elements[i].chain.contains { r in
                        if case .binding(let b) = r.kind { return b.storage == storage && b.target == value }
                        return false
                    }
                }
                if let match = under.first(where: bound) ?? snap.elements.indices.first(where: bound) { return match }
                runtime.warn("defaultFocus names a value no focusable view is bound to with .focused(_:equals:)")
            }
        }
        // prefersDefaultFocus(in: ns) inside a focusScope(ns).
        for (i, e) in snap.elements.enumerated() {
            for (k, record) in e.chain.enumerated() {
                guard case .prefersDefault(let ns) = record.kind else { continue }
                let scoped = e.chain[..<k].contains { r in if case .scope(let s) = r.kind { return s == ns }; return false }
                    || e.chain.contains { r in if case .scope(let s) = r.kind { return s == ns }; return false }
                if scoped { return i }
                runtime.warn("prefersDefaultFocus(in:) has no effect without a .focusScope(_:) with the same namespace around it")
            }
        }
        if let tabBar = snap.sections.first(where: { $0.kind == "tabBar" }), let selected = tabBar.preferred { return selected }
        guard automaticInitialFocus else { return 0 }
        let visible = snap.elements.indices.filter { snap.elements[$0].visible }
        return visible.min { a, b in
            let ra = snap.elements[a].frame, rb = snap.elements[b].frame
            let da = hypot(ra.minX - snap.screen.minX, ra.minY - snap.screen.minY)
            let db = hypot(rb.minX - snap.screen.minX, rb.minY - snap.screen.minY)
            return da < db - 0.5
        } ?? 0
    }

    // MARK: Scrolling

    /// Space tvOS leaves around an element it scrolls to (measured: tvOS 26.5). Moving down into a row cut
    /// off by 37 pt scrolls 215 pt, leaving the card's bottom 178 pt above the screen's bottom edge; a card
    /// scrolled to from below lands with its top 82 pt below the top edge; shelf items scrolled to sideways
    /// end 76 pt from the edge. Other platforms keep the minimal 40 pt margin.
    struct ScrollMargins { var top: CGFloat, bottom: CGFloat, leading: CGFloat, trailing: CGFloat }
    var scrollMargins: ScrollMargins {
        automaticInitialFocus ? ScrollMargins(top: 82, bottom: 178, leading: 76, trailing: 76)
                              : ScrollMargins(top: 40, bottom: 40, leading: 40, trailing: 40)
    }

    /// Scrolls the element's scroll views (innermost first) so it is visible. True when an offset changed.
    func scrollIntoView(_ e: FocusElement) -> Bool {
        var rect = e.frame
        var changed = false
        let margins = scrollMargins
        for scroll in e.scrolls.reversed() {
            let old = scrollOffsets[scroll.path] ?? .zero
            var offset = old
            func adjust(_ minE: CGFloat, _ maxE: CGFloat, _ minV: CGFloat, _ maxV: CGFloat, _ current: CGFloat, _ limit: CGFloat,
                        _ lead: CGFloat, _ trail: CGFloat) -> CGFloat {
                // Margins shrink when the element is too large for them (centred at worst).
                let room = max(0, (maxV - minV) - (maxE - minE))
                let k = lead + trail > room ? room / max(1, lead + trail) : 1
                let m0 = lead * k, m1 = trail * k
                var delta: CGFloat = 0
                if maxE - minE > maxV - minV - m0 - m1 || minE < minV + m0 { delta = minE - (minV + m0) }
                else if maxE > maxV - m1 { delta = maxE - (maxV - m1) }
                var next = min(max(0, current + delta), max(0, limit))
                // tvOS scrolls all the way to an end that is closer than the margin (measured: the last shelf item
                // ends 154 pt from the screen edge, at the end of the content 78 pt further, not 76 pt from the edge).
                if automaticInitialFocus {
                    if delta > 0, limit - next < max(trail, 100) { next = max(0, limit) }
                    if delta < 0, next < max(lead, 100) { next = 0 }
                }
                return next
            }
            // tvOS scroll views reach the screen's edges under the safe area (shelves scroll edge to edge), and
            // the measured margins are from those edges: a viewport within the safe-area inset of an edge is
            // taken to extend to it.
            var viewport = scroll.viewport
            if automaticInitialFocus {
                let screen = snapshot.screen, slack: CGFloat = 90
                if viewport.minX - screen.minX <= slack { viewport.size.width += viewport.minX - screen.minX; viewport.origin.x = screen.minX }
                if screen.maxX - viewport.maxX <= slack { viewport.size.width = screen.maxX - viewport.minX }
                if viewport.minY - screen.minY <= slack { viewport.size.height += viewport.minY - screen.minY; viewport.origin.y = screen.minY }
                if screen.maxY - viewport.maxY <= slack { viewport.size.height = screen.maxY - viewport.minY }
            }
            if scroll.axes.contains(.vertical) {
                offset.y = adjust(rect.minY, rect.maxY, viewport.minY, viewport.maxY, old.y, scroll.maxOffset.y,
                                  margins.top, margins.bottom)
            }
            if scroll.axes.contains(.horizontal) {
                offset.x = adjust(rect.minX, rect.maxX, viewport.minX, viewport.maxX, old.x, scroll.maxOffset.x,
                                  margins.leading, margins.trailing)
            }
            if abs(offset.x - old.x) > 0.25 || abs(offset.y - old.y) > 0.25 {
                scrollOffsets[scroll.path] = offset
                changed = true
                rect = rect.offsetBy(dx: -(offset.x - old.x), dy: -(offset.y - old.y))
            }
        }
        return changed
    }

    // MARK: Navigation

    /// The stack `select` pops with `menu`: the innermost one with a pushed screen around the focus.
    func popTarget() -> IdentityPath? {
        let candidates = pushes.filter { !$0.value.isEmpty }.map(\.key)
        let focused = focusedPath?.components ?? []
        let around = candidates.filter { focused.starts(with: $0.components) }
        return (around.isEmpty ? candidates : around).max { $0.components.count < $1.components.count }
    }
}

// MARK: - Identity strings

extension IdentityPath {
    /// A string stable across runs of the same source (type identities are positional, not addresses).
    var stableKey: String {
        components.map { c -> String in
            if c.base is ObjectIdentifier { return "T" }
            return String(describing: c.base)
        }.joined(separator: "/")
    }
    var shortHash: String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in stableKey.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        let s = String(h & 0xFFFFFF, radix: 16)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }
}
