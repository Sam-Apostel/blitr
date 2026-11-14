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
        var distance: CGFloat, overlap: CGFloat, centre: CGFloat
        static func < (a: Score, b: Score) -> Bool {
            if abs(a.distance - b.distance) > 0.5 { return a.distance < b.distance }
            if abs(a.overlap - b.overlap) > 0.5 { return a.overlap > b.overlap }
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
        return Score(distance: distance, overlap: overlap, centre: hypot(r.midX - o.midX, r.midY - o.midY))
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
        return best?.1
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

    /// True when the focused element is chrome without its own focus effect.
    var focusedChromeFrame: CGRect? {
        guard let i = snapshot.index(of: focusedPath), snapshot.elements[i].synthesized else { return nil }
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

        if let f = focusedIndex, scrollIntoView(snap.elements[f]) { changed = true }
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
    /// of a tab bar, then the first element in reading order.
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
        return 0
    }

    // MARK: Scrolling

    /// Scrolls the element's scroll views (innermost first) so it is visible. True when an offset changed.
    func scrollIntoView(_ e: FocusElement) -> Bool {
        var rect = e.frame
        var changed = false
        for scroll in e.scrolls.reversed() {
            let old = scrollOffsets[scroll.path] ?? .zero
            var offset = old
            func adjust(_ minE: CGFloat, _ maxE: CGFloat, _ minV: CGFloat, _ maxV: CGFloat, _ current: CGFloat, _ limit: CGFloat) -> CGFloat {
                let margin = max(0, min(40, ((maxV - minV) - (maxE - minE)) / 2))
                var delta: CGFloat = 0
                if maxE - minE > maxV - minV - 2 * margin || minE < minV + margin { delta = minE - (minV + margin) }
                else if maxE > maxV - margin { delta = maxE - (maxV - margin) }
                return min(max(0, current + delta), max(0, limit))
            }
            if scroll.axes.contains(.vertical) {
                offset.y = adjust(rect.minY, rect.maxY, scroll.viewport.minY, scroll.viewport.maxY, old.y, scroll.maxOffset.y)
            }
            if scroll.axes.contains(.horizontal) {
                offset.x = adjust(rect.minX, rect.maxX, scroll.viewport.minX, scroll.viewport.maxX, old.x, scroll.maxOffset.x)
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
