import XCTest

// Walks the tvOS focus engine of one preview with the Siri Remote and records where every press moves
// focus. Run by record-focus.sh, which passes the preview through TEST_RUNNER_FOCUS_* variables.
//
// Every focusable element is reached from a fresh launch by replaying the shortest press path found so
// far, then each of the four directions is pressed once from it (one launch per element and direction).
// Elements are told apart by label: frames move while an element is focused (the lift) and as scroll
// views follow focus, so they cannot identify one.
//
// The output follows the shape of `swiftui-screenshot render --focus-map`: elements with id, index,
// label, role, frame [x, y, w, h], moves {up, down, left, right} (an id, or null when focus stays) and
// the press path from launch.

final class FocusWalkTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var screen: String { env["FOCUS_SCREEN"] ?? "TVFocus" }
    private var preview: String { env["FOCUS_PREVIEW"] ?? "0" }
    private var output: String { env["FOCUS_OUT"] ?? NSTemporaryDirectory() + "focus.json" }
    private var limit: Int { Int(env["FOCUS_LIMIT"] ?? "80") ?? 80 }
    private let settle = 0.5

    override func setUp() { continueAfterFailure = true }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", screen, "-preview", preview, "-settle", "0.3"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    struct Focus { let key: String; let label: String; let role: String; let frame: CGRect }

    private func focused(_ app: XCUIApplication) -> Focus? {
        let element = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        guard element.exists else { return nil }
        // Text fields often have no label; their placeholder names them.
        let label = [element.label, element.placeholderValue ?? "", element.identifier].first { !$0.isEmpty } ?? ""
        let role = Self.role(element.elementType)
        return Focus(key: label.isEmpty ? "\(role)@\(Int(element.frame.midX)),\(Int(element.frame.midY))" : label,
                     label: label, role: role, frame: element.frame)
    }

    static func role(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .cell: return "cell"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .switch, .toggle: return "switch"
        case .segmentedControl: return "segmentedControl"
        case .tab, .tabBar: return "tab"
        case .link: return "link"
        case .searchField: return "searchField"
        case .staticText: return "staticText"
        case .image: return "image"
        case .other: return "other"
        default: return "type\(type.rawValue)"
        }
    }

    private func press(_ name: String) {
        let button: XCUIRemote.Button
        switch name {
        case "up": button = .up
        case "down": button = .down
        case "left": button = .left
        case "right": button = .right
        case "select": button = .select
        case "menu": button = .menu
        default: button = .playPause
        }
        XCUIRemote.shared.press(button)
        Thread.sleep(forTimeInterval: settle)
    }

    private static func rect(_ r: CGRect) -> [Double] {
        [r.minX, r.minY, r.width, r.height].map { (Double($0) * 10).rounded() / 10 }
    }

    func testWalk() throws {
        let directions = ["up", "down", "left", "right"]
        var order: [String] = []                 // keys in discovery order
        var found: [String: Focus] = [:]
        var paths: [String: [String]] = [:]
        var moves: [String: [String: Any]] = [:]
        var queue: [String] = []
        var notes: [String] = []

        func register(_ f: Focus, path: [String]) {
            guard found[f.key] == nil else { return }
            found[f.key] = f
            order.append(f.key)
            paths[f.key] = path
            queue.append(f.key)
        }

        var app = launch()
        guard let start = focused(app) else {
            try write(["version": 1, "platform": "tvOS", "error": "nothing has focus after launch"])
            return
        }
        register(start, path: [])

        while !queue.isEmpty, moves.count < limit {
            let key = queue.removeFirst()
            var row: [String: Any] = [:]
            for direction in directions {
                app.terminate()
                app = launch()
                for step in paths[key]! { press(step) }
                guard let here = focused(app), here.key == key else {
                    row[direction] = NSNull()
                    notes.append("\(key): replaying \(paths[key]!) reached \(focused(app)?.key ?? "nothing"); \(direction) not recorded")
                    continue
                }
                press(direction)
                if let there = focused(app) {
                    register(there, path: paths[key]! + [direction])
                    row[direction] = there.key == key ? NSNull() : there.key
                } else {
                    row[direction] = NSNull()
                    notes.append("\(key): nothing has focus after \(direction)")
                }
            }
            moves[key] = row
        }

        // Layout frames at launch (unfocused, unscrolled), where the element can be found by label.
        app.terminate()
        app = launch()
        let size = app.windows.firstMatch.frame.size
        var frames: [String: CGRect] = [:]
        for key in order where !found[key]!.label.isEmpty {
            let f = found[key]!
            let match = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", f.label, f.label)).firstMatch
            if match.exists { frames[key] = match.frame }
        }
        app.terminate()

        let ids = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, Self.slug(found[$1]!, $0 + 1)) })
        let elements: [[String: Any]] = order.enumerated().map { index, key in
            let f = found[key]!
            var row: [String: Any] = [:]
            for (direction, target) in moves[key] ?? [:] {
                row[direction] = (target as? String).map { ids[$0]! as Any } ?? NSNull()
            }
            var e: [String: Any] = [
                "id": ids[key]!, "index": index + 1, "label": f.label, "role": f.role,
                "frame": frames[key].map(Self.rect) ?? Self.rect(f.frame),
                "focusedFrame": Self.rect(f.frame),
                "visible": frames[key].map { $0.intersects(CGRect(origin: .zero, size: size)) } ?? false,
                "section": NSNull(),
                "path": paths[key]!,
            ]
            e["moves"] = moves[key] == nil ? NSNull() : row
            return e
        }
        try write(["version": 1, "platform": "tvOS", "screen": screen, "preview": preview,
                   "size": ["width": size.width, "height": size.height],
                   "initialFocus": ids[start.key]!, "focused": ids[start.key]!, "presses": [],
                   "elements": elements, "complete": queue.isEmpty, "notes": notes])
    }

    /// Replays FOCUS_PROBE (comma-separated presses, including select and menu) from launch and records the
    /// focused element and the visible text after each press. Used for questions that need history.
    func testProbe() throws {
        guard let probe = env["FOCUS_PROBE"], !probe.isEmpty else { return }
        let app = launch()
        func state(_ press: String) -> [String: Any] {
            let texts = app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label).filter { !$0.isEmpty }
            return ["press": press, "focused": focused(app)?.label ?? NSNull(), "texts": Array(texts)]
        }
        var steps = [state("launch")]
        for p in probe.split(separator: ",").map(String.init) {
            press(p)
            Thread.sleep(forTimeInterval: 0.6)
            steps.append(state(p))
        }
        app.terminate()
        try write(["screen": screen, "preview": preview, "probe": probe, "steps": steps])
    }

    static func slug(_ f: Focus, _ index: Int) -> String {
        let base = f.label.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "\(f.role)-\(base.isEmpty ? String(index) : base)"
    }

    private func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output))
    }
}
