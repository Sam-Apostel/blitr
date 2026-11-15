import SwiftUI
import WatchKit
import PreviewSupport

// The watchOS counterpart of App/HostApp.swift. watchOS apps have no UIKit view hierarchy to walk, so the
// element frames come from the UI test that drives this app (scripts/mac/watchos/CaptureTests.swift); the
// app writes only what the test cannot see:
//
//   -screen Watch -preview 0 [-settle 1.0]
//
// After the view has appeared and settled it writes <Documents>/<screen>-<preview>.meta.json (screen size and
// scale, safe area, the color scheme the view was drawn in) and then <Documents>/ready.

@main
struct ReferenceHostApp: App {
    var body: some Scene {
        WindowGroup {
            HostRoot()
        }
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
    static var outDirectory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
}

struct HostRoot: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let entries = previewRegistry[LaunchOptions.screen] ?? []
        Group {
            if LaunchOptions.preview < entries.count {
                entries[LaunchOptions.preview].make()
            } else {
                Text("No preview \(LaunchOptions.preview) in \"\(LaunchOptions.screen)\"")
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { scheduleCapture(safeArea: proxy.safeAreaInsets) }
            }
        }
    }

    private func scheduleCapture(safeArea: EdgeInsets) {
        let out = LaunchOptions.outDirectory
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: out.appendingPathComponent("ready"))
        let scheme = colorScheme == .dark ? "dark" : "light"
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchOptions.settle) {
            let device = WKInterfaceDevice.current()
            let doc: [String: Any] = [
                "device": device.name,
                "model": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "",
                "systemVersion": device.systemVersion,
                "size": ["width": device.screenBounds.width, "height": device.screenBounds.height],
                "scale": device.screenScale,
                "colorScheme": scheme,
                "safeArea": ["top": safeArea.top, "bottom": safeArea.bottom,
                             "left": safeArea.leading, "right": safeArea.trailing],
            ]
            let name = "\(LaunchOptions.screen)-\(LaunchOptions.preview).meta.json"
            if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.appendingPathComponent(name))
            }
            try? Data("ok".utf8).write(to: out.appendingPathComponent("ready"))
        }
    }
}
