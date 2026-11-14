// Siri Remote presses (`--press`) and the start focus (`--focus`).
//
// Each press acts on the state of the last pass; the renderer then runs the resolve/layout pass loop
// again so state changes, pushed screens and dismissed presentations show up.

enum RemotePress: String, CaseIterable {
    case up, down, left, right, select, menu, playpause

    init?(argument: String) {
        let raw = argument.lowercased().filter { $0.isLetter }
        switch raw {
        case "back", "exit": self = .menu
        case "play", "pause": self = .playpause
        case "click", "ok", "enter": self = .select
        default: self.init(rawValue: raw)
        }
    }

    var direction: MoveCommandDirection? {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        default: nil
        }
    }
}

struct PressLog {
    var press: String
    var from: String?
    var to: String?
    var note: String
}

extension FocusEngine {
    private func describe(_ i: Int?) -> String {
        guard let i else { return "nothing" }
        let e = snapshot.elements[i]
        return "#\(e.index) \(e.label.isEmpty ? e.role : "\"\(e.label)\"")"
    }

    /// The innermost handler of a kind above the focused element.
    private func innermost<T>(_ pick: (FocusRecord.Kind) -> T?) -> T? {
        guard let f = snapshot.index(of: focusedPath) else { return nil }
        for record in snapshot.elements[f].chain.reversed() { if let h = pick(record.kind) { return h } }
        return nil
    }

    /// Applies one press to the current state. The caller runs the pass loop afterwards.
    func press(_ press: RemotePress, runtime: Runtime) -> PressLog {
        let f = snapshot.index(of: focusedPath)
        let fromID = f.map { snapshot.elements[$0].id }
        var log = PressLog(press: press.rawValue, from: fromID, to: fromID, note: "")
        runtime.needsAnotherPass = true

        if let direction = press.direction {
            guard let f else {
                log.note = "nothing has focus"
                runtime.warn("--press \(press.rawValue): nothing has focus")
                return log
            }
            var notes: [String] = []
            if let handler = innermost({ k -> ((MoveCommandDirection) -> Void)? in if case .onMove(let h) = k { return h }; return nil }) {
                handler(direction)
                notes.append("onMoveCommand(\(press.rawValue)) called")
            }
            if let t = snapshot.move(f, direction) {
                requestedPath = snapshot.elements[t].path
                userMoved = true
                log.to = snapshot.elements[t].id
                notes.append("focus \(describe(f)) -> \(describe(t))")
            } else {
                notes.append("no element \(press.rawValue) of \(describe(f)); focus stays")
            }
            log.note = notes.joined(separator: "; ")
            return log
        }

        switch press {
        case .select:
            guard let f else {
                log.note = "nothing has focus"
                runtime.warn("--press select: nothing has focus")
                return log
            }
            let e = snapshot.elements[f]
            if let action = e.activate ?? runtime.activations.action(for: e.path) {
                action()
                log.note = "activated \(describe(f))"
            } else {
                log.note = "\(describe(f)) has no action"
                runtime.warn("--press select: \(describe(f)) (\(e.role)) has no action to run")
            }
        case .menu:
            if let handler = innermost({ k -> (() -> Void)? in if case .onExit(let h) = k { return h }; return nil }) {
                handler()
                log.note = "onExitCommand called"
            } else if let dismiss = snapshot.dismissTop {
                dismiss()
                log.note = "dismissed the \(snapshot.modalKind ?? "presentation")"
            } else if let stack = popTarget() {
                pushes[stack]?.removeLast()
                log.note = "popped a screen pushed by select"
            } else {
                log.note = "nothing to go back to"
                runtime.warn("--press menu: no onExitCommand, presentation or pushed screen to go back from (tvOS would leave the app); screens pushed through a NavigationStack path binding cannot be popped")
            }
        case .playpause:
            if let handler = innermost({ k -> (() -> Void)? in if case .onPlayPause(let h) = k { return h }; return nil }) {
                handler()
                log.note = "onPlayPauseCommand called"
            } else {
                log.note = "no onPlayPauseCommand"
                runtime.warn("--press playpause: no onPlayPauseCommand around the focused element")
            }
        default:
            break
        }
        return log
    }

    /// Resolves a `--focus` selector: an element id, `#index`, or a label (exact, then case-insensitive substring).
    func element(matching selector: String) throws -> Int {
        let elements = snapshot.elements
        guard !elements.isEmpty else { throw RenderError("--focus \(selector): the screen has no focusable elements") }
        if let i = elements.firstIndex(where: { $0.id == selector }) { return i }
        if selector.hasPrefix("#"), let n = Int(selector.dropFirst()) {
            guard elements.indices.contains(n - 1) else { throw RenderError("--focus \(selector): there are \(elements.count) focusable elements") }
            return n - 1
        }
        let exact = elements.indices.filter { elements[$0].label == selector }
        let candidates = exact.isEmpty
            ? elements.indices.filter { elements[$0].label.range(of: selector, options: .caseInsensitive) != nil }
            : exact
        if candidates.count == 1 { return candidates[0] }
        let list = (candidates.isEmpty ? Array(elements.indices) : candidates)
            .map { "  #\(elements[$0].index) \(elements[$0].id) \"\(elements[$0].label)\"" }.joined(separator: "\n")
        if candidates.isEmpty { throw RenderError("--focus \"\(selector)\" matches no element. Elements:\n\(list)") }
        throw RenderError("--focus \"\(selector)\" is ambiguous; it matches:\n\(list)")
    }
}
