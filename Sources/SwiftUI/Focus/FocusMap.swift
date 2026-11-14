// The focus map: every focusable element with its moves, the shortest press path to it from the
// initial focus, and navigation issues. Computed geometrically from the final laid-out tree (no
// re-rendering per element). Written as JSON (`--focus-map`) and drawn as an overlay (`--focus-overlay`).
// The JSON shape is documented in docs/FOCUS.md.

struct FocusRequest {
    var mapPath: String?
    var overlayPath: String?
    var presses: [RemotePress] = []
    var focusSelector: String?
    var wantsMap: Bool { mapPath != nil || overlayPath != nil }
}

struct FocusIssue {
    var kind: String
    var elements: [Int]
    var message: String
}

@MainActor
struct FocusMap {
    let snap: FocusSnapshot
    let initial: Int?
    let focused: Int?
    /// [element][direction] -> target
    var moves: [[MoveCommandDirection: Int]] = []
    /// Shortest press sequence from the initial focus; nil when unreachable.
    var paths: [[MoveCommandDirection]?] = []
    var issues: [FocusIssue] = []

    static let directions: [MoveCommandDirection] = [.up, .down, .left, .right]

    init(_ snap: FocusSnapshot, initial: Int?, focused: Int?) {
        self.snap = snap
        self.initial = initial
        self.focused = focused
        let n = snap.elements.count
        moves = (0..<n).map { i in
            var m: [MoveCommandDirection: Int] = [:]
            for d in FocusMap.directions { if let t = snap.move(i, d) { m[d] = t } }
            return m
        }
        paths = Array(repeating: nil, count: n)
        if let start = initial {
            paths[start] = []
            var queue = [start], head = 0
            while head < queue.count {
                let i = queue[head]; head += 1
                for d in FocusMap.directions {
                    guard let t = moves[i][d], paths[t] == nil else { continue }
                    paths[t] = paths[i]! + [d]
                    queue.append(t)
                }
            }
        }
        findIssues()
    }

    func name(_ i: Int) -> String {
        let e = snap.elements[i]
        return "#\(e.index) " + (e.label.isEmpty ? e.role : "\"\(e.label)\"")
    }

    static func word(_ d: MoveCommandDirection) -> String {
        switch d { case .up: "up"; case .down: "down"; case .left: "left"; case .right: "right" }
    }

    private mutating func findIssues() {
        let n = snap.elements.count
        guard n > 0 else {
            issues.append(FocusIssue(kind: "noFocusableElements", elements: [],
                                     message: "Nothing on this screen can take focus; the remote can do nothing here."))
            return
        }
        let unreachable = (0..<n).filter { paths[$0] == nil }
        if !unreachable.isEmpty {
            for i in unreachable {
                issues.append(FocusIssue(kind: "unreachable", elements: [i],
                                         message: "\(name(i)) cannot be reached with the remote from the initial focus. Wrap the groups it sits between in .focusSection(), or line it up with its neighbours."))
            }
        }
        // Traps: groups you can enter but never leave again (no way back to the initial focus).
        if let start = initial {
            var reverse = [[Int]](repeating: [], count: n)
            for i in 0..<n { for (_, t) in moves[i] { reverse[t].append(i) } }
            var canReturn = [Bool](repeating: false, count: n)
            canReturn[start] = true
            var stack = [start]
            while let i = stack.popLast() { for p in reverse[i] where !canReturn[p] { canReturn[p] = true; stack.append(p) } }
            let trapped = (0..<n).filter { paths[$0] != nil && !canReturn[$0] }
            for group in sinkGroups(trapped) {
                issues.append(FocusIssue(kind: "trap", elements: group,
                                         message: "Once focus reaches \(group.map(name).joined(separator: ", ")), no press leads back to the rest of the screen."))
            }
        }
        // One-way moves (information: common with items of different sizes).
        for i in 0..<n {
            for d in FocusMap.directions {
                guard let t = moves[i][d] else { continue }
                let back = moves[t][FocusMovement.opposite(d)]
                if back != i {
                    let backText = back.map { "goes to \(name($0))" } ?? "goes nowhere"
                    issues.append(FocusIssue(kind: "oneWay", elements: [i, t],
                                             message: "\(Self.word(d)) from \(name(i)) goes to \(name(t)), but \(Self.word(FocusMovement.opposite(d))) from there \(backText)."))
                }
            }
        }
    }

    /// Strongly connected groups of `members` with no move out of the group.
    private func sinkGroups(_ members: [Int]) -> [[Int]] {
        let set = Set(members)
        var groups: [[Int]] = []
        var assigned: Set<Int> = []
        func reach(_ from: Int) -> Set<Int> {
            var seen: Set<Int> = [from], stack = [from]
            while let i = stack.popLast() { for (_, t) in moves[i] where !seen.contains(t) { seen.insert(t); stack.append(t) } }
            return seen
        }
        for i in members where !assigned.contains(i) {
            let forward = reach(i)
            let component = forward.filter { reach($0).contains(i) }
            assigned.formUnion(component)
            if forward.isSubset(of: component), component.isSubset(of: set) { groups.append(component.sorted()) }
        }
        return groups
    }

    // MARK: JSON

    func json(config: RenderConfiguration, canvasSize: CGSize, presses: [PressLog]) -> AXJSON {
        func id(_ i: Int?) -> AXJSON { i.map { .string(snap.elements[$0].id) } ?? .null }
        func frame(_ r: CGRect) -> AXJSON { .array([.num(r.minX), .num(r.minY), .num(r.width), .num(r.height)]) }
        var elements: [AXJSON] = []
        for (i, e) in snap.elements.enumerated() {
            var pairs: [(String, AXJSON)] = [
                ("id", .string(e.id)), ("index", .int(e.index)), ("label", .string(e.label)), ("role", .string(e.role)),
                ("frame", frame(e.frame)), ("visible", .bool(e.visible)),
                ("section", e.sections.last.map { .string(snap.sections[$0].id) } ?? .null),
                ("moves", .inlineObject(FocusMap.directions.map { (Self.word($0), id(moves[i][$0])) })),
                ("path", paths[i].map { p in .array(p.map { .string(Self.word($0)) }) } ?? .null),
            ]
            if i == focused { pairs.append(("focused", .bool(true))) }
            elements.append(.object(pairs))
        }
        let sections: [AXJSON] = snap.sections.filter { !$0.members.isEmpty }.map { s in
            .object([("id", .string(s.id)), ("kind", .string(s.kind)), ("frame", frame(s.frame)),
                     ("elements", .array(s.members.map { .string(snap.elements[$0].id) }))])
        }
        var byKind: [String: Int] = [:]
        for issue in issues { byKind[issue.kind, default: 0] += 1 }
        let summary: [(String, AXJSON)] = [
            ("elementCount", .int(snap.elements.count)),
            ("visibleCount", .int(snap.elements.filter(\.visible).count)),
            ("unreachableCount", .int(paths.filter { $0 == nil }.count)),
            ("issuesByKind", .object(byKind.sorted { $0.key < $1.key }.map { ($0.key, AXJSON.int($0.value)) })),
        ]
        return .object([
            ("version", .int(1)),
            ("platform", .string(config.platform.rawValue)),
            ("device", .string(config.device.name)),
            ("size", .object([("width", .num(canvasSize.width)), ("height", .num(canvasSize.height))])),
            ("modal", snap.modalKind.map { .string($0) } ?? .null),
            ("initialFocus", id(initial)),
            ("focused", id(focused)),
            ("presses", .array(presses.map { p in
                .object([("press", .string(p.press)), ("from", p.from.map { .string($0) } ?? .null),
                         ("to", p.to.map { .string($0) } ?? .null), ("note", .string(p.note))])
            })),
            ("elements", .array(elements)),
            ("sections", .array(sections)),
            ("summary", .object(summary)),
            ("issues", .array(issues.map { issue in
                .object([("kind", .string(issue.kind)), ("elements", .array(issue.elements.map { .string(snap.elements[$0].id) })),
                         ("message", .string(issue.message))])
            })),
        ])
    }

    /// A few lines for stderr.
    func summaryText() -> String {
        let n = snap.elements.count
        var lines: [String] = []
        let visible = snap.elements.filter(\.visible).count
        var head = "focus: \(n) focusable element\(n == 1 ? "" : "s") (\(visible) on screen)"
        if let initial { head += ", initial \(name(initial))" }
        if let focused, focused != initial { head += ", focused \(name(focused))" }
        if let modal = snap.modalKind { head += ", modal: \(modal)" }
        lines.append(head)
        var byKind: [String: Int] = [:]
        for issue in issues { byKind[issue.kind, default: 0] += 1 }
        let unreachable = paths.filter { $0 == nil }.count
        lines.append("  \(unreachable) unreachable, \(byKind["trap"] ?? 0) trap\(byKind["trap"] == 1 ? "" : "s"), \(byKind["oneWay"] ?? 0) one-way move\(byKind["oneWay"] == 1 ? "" : "s")")
        for issue in issues where issue.kind != "oneWay" { lines.append("  \(issue.kind): \(issue.message)") }
        return lines.joined(separator: "\n")
    }
}
