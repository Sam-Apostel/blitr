import XCTest

// Takes the watchOS reference screenshots for one device and color scheme: launches the reference host app
// (installed by capture-watchos.sh) on each preview, waits for it to settle, saves the screen and the
// accessibility hierarchy XCUITest sees (watchOS apps have no UIKit views to walk in process).
// Parameters come through TEST_RUNNER_CAPTURE_* variables:
//   CAPTURE_JOBS    "<screen>:<preview>" pairs separated by spaces
//   CAPTURE_OUT     directory for <screen>-<preview>.png and <screen>-<preview>.tree.json
//   CAPTURE_SETTLE  seconds the host app waits before it signals ready (default 1.0)

final class CaptureTests: XCTestCase {
    func testCapture() throws {
        let env = ProcessInfo.processInfo.environment
        let bundle = env["CAPTURE_BUNDLE"] ?? "dev.swiftui-screenshot.reference-host"
        let out = URL(fileURLWithPath: try XCTUnwrap(env["CAPTURE_OUT"]))
        let settle = Double(env["CAPTURE_SETTLE"] ?? "1.0") ?? 1.0
        for job in (env["CAPTURE_JOBS"] ?? "").split(separator: " ") {
            let parts = job.split(separator: ":").map(String.init)
            guard parts.count == 2 else { continue }
            let app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-screen", parts[0], "-preview", parts[1], "-settle", String(settle)]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 15)
            // The host app writes its metadata after `settle`; leave the same margin the iOS capture has.
            Thread.sleep(forTimeInterval: settle + 1.5)
            let name = "\(parts[0])-\(parts[1])"
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent(name + ".png"))
            let snapshot = try app.snapshot()
            let tree = Self.describe(snapshot)
            let data = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: out.appendingPathComponent(name + ".tree.json"))
            app.terminate()
        }
    }

    private static func describe(_ s: XCUIElementSnapshot) -> [String: Any] {
        var item: [String: Any] = [
            "type": typeName(s.elementType),
            "label": s.label,
            "frame": ["x": round2(s.frame.minX), "y": round2(s.frame.minY),
                      "width": round2(s.frame.width), "height": round2(s.frame.height)],
            "enabled": s.isEnabled,
            "children": s.children.map(describe),
        ]
        if !s.identifier.isEmpty { item["identifier"] = s.identifier }
        if let value = s.value.map({ "\($0)" }), !value.isEmpty { item["value"] = value }
        if !s.title.isEmpty { item["title"] = s.title }
        if s.isSelected { item["selected"] = true }
        return item
    }

    private static func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }

    private static func typeName(_ t: XCUIElement.ElementType) -> String {
        switch t {
        case .application: return "Application"
        case .window: return "Window"
        case .button: return "Button"
        case .staticText: return "StaticText"
        case .image: return "Image"
        case .cell: return "Cell"
        case .table: return "Table"
        case .collectionView: return "CollectionView"
        case .scrollView: return "ScrollView"
        case .navigationBar: return "NavigationBar"
        case .switch: return "Switch"
        case .toggle: return "Toggle"
        case .slider: return "Slider"
        case .picker: return "Picker"
        case .pickerWheel: return "PickerWheel"
        case .textField: return "TextField"
        case .link: return "Link"
        case .other: return "Other"
        case .group: return "Group"
        case .pageIndicator: return "PageIndicator"
        case .progressIndicator: return "ProgressIndicator"
        case .activityIndicator: return "ActivityIndicator"
        case .tabBar: return "TabBar"
        case .tab: return "Tab"
        case .map: return "Map"
        case .icon: return "Icon"
        case .statusBar: return "StatusBar"
        default: return "ElementType\(t.rawValue)"
        }
    }
}
