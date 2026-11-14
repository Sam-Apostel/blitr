import XCTest

// Sets the Apple TV simulator's system appearance (Settings > General > Appearance), which simctl
// cannot do for tvOS. TEST_RUNNER_APPEARANCE_STYLE is "Light" or "Dark".

final class AppearanceTests: XCTestCase {
    private func focusedLabel(_ app: XCUIApplication) -> String {
        let e = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return e.exists ? e.label : ""
    }

    /// Presses down (then up) until an element whose label starts with `label` has focus, and selects it.
    private func select(_ label: String, in app: XCUIApplication) {
        for direction in [XCUIRemote.Button.down, .up] {
            for _ in 0..<25 {
                if focusedLabel(app).hasPrefix(label) {
                    XCUIRemote.shared.press(.select)
                    Thread.sleep(forTimeInterval: 1.5)
                    return
                }
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        XCTFail("could not focus \(label); last focused: \(focusedLabel(app))")
    }

    func testSetAppearance() {
        let style = ProcessInfo.processInfo.environment["APPEARANCE_STYLE"] ?? "Light"
        let settings = XCUIApplication(bundleIdentifier: "com.apple.TVSettings")
        settings.terminate()
        settings.launch()
        Thread.sleep(forTimeInterval: 2)
        select("General", in: settings)
        select("Appearance", in: settings)
        select(style, in: settings)
        Thread.sleep(forTimeInterval: 1)
        settings.terminate()
    }
}
