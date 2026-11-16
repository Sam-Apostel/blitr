import XCTest

// Replays Siri Remote press sequences in an installed tvOS app and records, after every press, the
// focused element (label, role, frame), the focusable elements on screen and a screenshot. Run by
// record-app.sh, which passes its parameters through TEST_RUNNER_APP_* variables:
//
//   APP_BUNDLE  bundle id of the installed app
//   APP_ENV     JSON object: the app's launch environment
//   APP_ARGS    JSON array: the app's launch arguments
//   APP_PATHS   JSON array of {"name": ..., "presses": "down,select,menu"}
//   APP_OUT     directory: <name>.json and <name>-<step>.png per path
//   APP_SETTLE  seconds to wait after launch (default 3)

final class AppPathTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    private func json<T>(_ key: String, _ fallback: T) -> T {
        guard let raw = env[key], let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? T else { return fallback }
        return object
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: env["APP_BUNDLE"] ?? "")
        app.launchEnvironment = json("APP_ENV", [String: String]())
        app.launchArguments = json("APP_ARGS", [String]())
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 15)
        Thread.sleep(forTimeInterval: Double(env["APP_SETTLE"] ?? "3") ?? 3)
        return app
    }

    private static func rect(_ r: CGRect) -> [Double] {
        [r.minX, r.minY, r.width, r.height].map { (Double($0) * 10).rounded() / 10 }
    }

    /// One snapshot of the accessibility tree per step: querying element by element times out on busy
    /// screens (maps, long lists).
    private struct Step { var focused: [String: Any] = [:]; var elements: [[String: Any]] = []; var texts: [String] = [] }

    private func inspect(_ app: XCUIApplication) -> Step {
        var step = Step()
        guard let root = try? app.snapshot() else { return step }
        let screen = root.frame
        func label(_ e: XCUIElementSnapshot) -> String {
            [e.label, (e.placeholderValue ?? ""), e.identifier].first { !$0.isEmpty } ?? ""
        }
        func walk(_ e: XCUIElementSnapshot) {
            if e.hasFocus, step.focused.isEmpty {
                step.focused = ["label": label(e), "identifier": e.identifier, "role": FocusWalkRole.name(e.elementType),
                                "frame": Self.rect(e.frame)]
            }
            if e.elementType == .button || e.elementType == .cell, e.frame.intersects(screen), e.frame.width > 0, step.elements.count < 80 {
                step.elements.append(["label": e.label, "role": FocusWalkRole.name(e.elementType), "frame": Self.rect(e.frame),
                                      "focused": e.hasFocus])
            }
            if e.elementType == .staticText, !e.label.isEmpty, step.texts.count < 16 { step.texts.append(e.label) }
            for child in e.children { walk(child) }
        }
        walk(root)
        return step
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
        Thread.sleep(forTimeInterval: 1.2)
    }

    func testPaths() throws {
        let out = env["APP_OUT"] ?? NSTemporaryDirectory()
        let paths: [[String: String]] = json("APP_PATHS", [])
        for path in paths {
            let name = path["name"] ?? "path"
            let presses = (path["presses"] ?? "").split(separator: ",").map(String.init)
            let app = launch()
            var steps: [[String: Any]] = []
            func record(_ press: String, _ index: Int) throws {
                let shot = "\(name)-\(index)"
                try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(shot).png"))
                let step = inspect(app)
                steps.append(["press": press, "focused": step.focused, "elements": step.elements, "texts": step.texts,
                              "screenshot": shot + ".png"])
            }
            try record("launch", 0)
            for (index, p) in presses.enumerated() {
                press(p)
                try record(p, index + 1)
            }
            let size = (try? app.snapshot().frame.size) ?? .zero
            app.terminate()
            let doc: [String: Any] = ["name": name, "presses": presses, "steps": steps,
                                      "size": ["width": size.width, "height": size.height]]
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: "\(out)/\(name).json"))
        }
    }
}

enum FocusWalkRole {
    static func name(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .cell: return "cell"
        case .textField: return "textField"
        case .switch, .toggle: return "switch"
        case .segmentedControl: return "segmentedControl"
        case .tab, .tabBar: return "tab"
        case .staticText: return "staticText"
        case .image: return "image"
        case .other: return "other"
        default: return "type\(type.rawValue)"
        }
    }
}
