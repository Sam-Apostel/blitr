import SwiftUI
import UIKit
import PreviewSupport

// Shows one preview full screen, chosen by launch arguments:
//
//   -screen 01_Settings -preview 0 [-out <dir>]
//
// After the view has appeared and settled, it writes <out>/<screen>-<preview>.json (element frames from
// the accessibility hierarchy) and then <out>/ready, which the capture script waits for before it takes
// the screenshot. <out> defaults to the app's Documents directory.

@main
struct ReferenceHostApp: App {
    @UIApplicationDelegateAdaptor(HostDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            HostRoot()
        }
    }
}

final class HostDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIView.setAnimationsEnabled(false)
        AccessibilityActivation.enable()
        return true
    }
}

enum LaunchOptions {
    static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var screen: String { value("-screen") ?? "" }
    static var preview: Int { Int(value("-preview") ?? "0") ?? 0 }
    static var settle: Double { Double(value("-settle") ?? "1.0") ?? 1.0 }
    /// With `-redump <seconds>`, the element frames are written again at that interval, so a driver that
    /// moves focus afterwards (the tvOS capture) finds frames for the state it photographed.
    static var redump: Double? { value("-redump").flatMap(Double.init) }
    static var outDirectory: URL {
        if let dir = value("-out") { return URL(fileURLWithPath: dir) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct HostRoot: View {
    var body: some View {
        let entries = previewRegistry[LaunchOptions.screen] ?? []
        Group {
            if LaunchOptions.preview < entries.count {
                entries[LaunchOptions.preview].make()
            } else {
                Text("No preview \(LaunchOptions.preview) in \"\(LaunchOptions.screen)\"")
            }
        }
        .onAppear(perform: scheduleCapture)
    }

    private func scheduleCapture() {
        let out = LaunchOptions.outDirectory
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: out.appendingPathComponent("ready"))
        // `.task` work and the first layout passes finish within a few run-loop turns; the settle time
        // also covers keyboard-free text fields becoming first responder and lazy stacks filling in.
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchOptions.settle) {
            let name = "\(LaunchOptions.screen)-\(LaunchOptions.preview)"
            ElementDump.write(to: out.appendingPathComponent(name + ".json"))
            if let interval = LaunchOptions.redump {
                Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    MainActor.assumeIsolated { ElementDump.write(to: out.appendingPathComponent(name + ".json")) }
                }
            }
            DispatchQueue.main.async {
                try? Data("ok".utf8).write(to: out.appendingPathComponent("ready"))
            }
        }
    }
}
