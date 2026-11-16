import XCTest

// Takes one tvOS reference screenshot: launches the reference host app (installed by
// capture-tvos.sh) on a preview, applies Siri Remote presses, waits for the focus animation, and
// saves the screen. Parameters come through TEST_RUNNER_CAPTURE_* variables.

final class CaptureTests: XCTestCase {
    func testCapture() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication(bundleIdentifier: env["CAPTURE_BUNDLE"] ?? "dev.blitr.reference-host")
        app.launchArguments = ["-screen", env["CAPTURE_SCREEN"] ?? "", "-preview", env["CAPTURE_PREVIEW"] ?? "0",
                               "-settle", "0.5", "-redump", "0.5"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 2.0)
        for press in (env["CAPTURE_PRESSES"] ?? "").split(separator: ",") {
            switch press {
            case "up": XCUIRemote.shared.press(.up)
            case "down": XCUIRemote.shared.press(.down)
            case "left": XCUIRemote.shared.press(.left)
            case "right": XCUIRemote.shared.press(.right)
            case "select": XCUIRemote.shared.press(.select)
            case "menu": XCUIRemote.shared.press(.menu)
            case "playpause": XCUIRemote.shared.press(.playPause)
            default: XCTFail("unknown press \(press)")
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        // The focus lift settles in well under a second; the host app re-dumps frames every 0.5s.
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: URL(fileURLWithPath: env["CAPTURE_OUT"]!))
        Thread.sleep(forTimeInterval: 0.6)
        app.terminate()
    }
}
