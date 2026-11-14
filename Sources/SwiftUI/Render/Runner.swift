// The public surface used by the generated `main.swift` that wraps user code.

/// One renderable entry: a `#Preview`, a `PreviewProvider`, or an explicit view expression.
public struct _PreviewEntry {
    let name: String?
    let make: @MainActor () -> AnyView
    /// Per-preview defaults from `#Preview(traits:)`; explicit command-line options override them.
    let orientation: String?
    let layout: String?
    let width: Double?
    let height: Double?
    public init<V: View>(_ name: String? = nil, orientation: String? = nil, layout: String? = nil, width: Double? = nil,
                         height: Double? = nil, @ViewBuilder _ body: @escaping @MainActor () -> V) {
        self.name = name
        self.orientation = orientation
        self.layout = layout
        self.width = width
        self.height = height
        self.make = { AnyView(body()) }
    }
}

public enum _ScreenshotRunner {
    /// Parses the runner's arguments, renders the selected preview, prints a JSON result line.
    public static func run(_ previews: [_PreviewEntry]) -> Never {
        MainActor.assumeIsolated { runOnMain(previews) }
    }

    @MainActor
    private static func runOnMain(_ previews: [_PreviewEntry]) -> Never {
        var config = RenderConfiguration()
        var output = "screenshot.png"
        var index = 0
        var previewName: String?
        var listOnly = false
        var listDevices = false
        var deviceWasSet = false
        var orientation: DeviceOrientation?
        var layoutSet = false
        var args = Array(CommandLine.arguments.dropFirst())
        // `compare` support: pixel comparison of PNG pairs needs Skia, so the CLI delegates it here.
        if args.first == "--compare", args.count >= 2 { ImageComparison.runJobs(args[1]) }

        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
            exit(2)
        }
        func value(_ flag: String) -> String {
            guard !args.isEmpty else { fail("\(flag) needs a value") }
            return args.removeFirst()
        }
        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--out": output = value(flag)
            case "--preview":
                let v = value(flag)
                if let i = Int(v) { index = i } else { previewName = v }
            case "--list": listOnly = true
            case "--device":
                let key = value(flag)
                guard let device = DeviceProfile.lookup(key) else {
                    fail("unknown device \"\(key)\". Known: \(DeviceProfile.table.map(\.id).joined(separator: ", "))")
                }
                config.device = device
                deviceWasSet = true
            case "--list-devices": listDevices = true
            case "--platform":
                guard let platform = RenderPlatform(argument: value(flag)) else {
                    fail("--platform must be one of \(RenderPlatform.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", "))")
                }
                config.platform = platform
            case "--orientation":
                switch DeviceProfile.normalize(value(flag)) {
                case "portrait": orientation = .portrait
                case "landscape", "landscapeleft": orientation = .landscapeLeft
                case "landscaperight": orientation = .landscapeRight
                default: fail("--orientation must be portrait, landscape, landscape-left or landscape-right")
                }
            case "--rounded-corners": config.roundedCorners = true
            case "--show-island": config.showsSensorHousing = true
            case "--layout":
                layoutSet = true
                switch value(flag) {
                case "device": config.layout = .device
                case "fit", "sizeThatFits": config.layout = .sizeThatFits
                case "fixed": config.layout = .fixed
                default: fail("--layout must be device, fit or fixed")
                }
            case "--width": config.width = Double(value(flag)).map { CGFloat($0) }
            case "--height": config.height = Double(value(flag)).map { CGFloat($0) }
            case "--scale": config.scale = Double(value(flag)).map { CGFloat($0) }
            case "--padding": config.padding = CGFloat(Double(value(flag)) ?? 0)
            case "--scheme": config.colorScheme = value(flag) == "dark" ? .dark : .light
            case "--dynamic-type":
                let wanted = value(flag).lowercased()
                guard let size = DynamicTypeSize.allCases.first(where: { "\($0)".lowercased() == wanted }) else {
                    fail("unknown dynamic type size \"\(wanted)\"")
                }
                config.dynamicTypeSize = size
            case "--ios":
                let raw = value(flag).lowercased()
                let latest = RenderedPlatform.supportedVersions.max()!
                guard let major = raw == "latest" ? latest : Int(raw.split(separator: ".").first ?? "") else {
                    fail("--ios takes a version such as 18, 26, 27 or \"latest\"")
                }
                config.osVersion = major
            case "--no-chrome": config.showsDeviceChrome = false
            case "--background":
                let hex = value(flag).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                if hex == "clear" || hex == "transparent" { config.background = .clear }
                else if let v = UInt32(hex, radix: 16) { config.background = RGBA(hex: v) }
            case "--task-budget": config.taskBudget = Double(value(flag)) ?? 0.5
            case "--fonts": config.fontDirectories.append(value(flag))
            case "--assets": config.assetDirectories.append(value(flag))
            case "--accessibility-tree": AccessibilityOutputs.request.treePath = value(flag)
            case "--tap-targets": AccessibilityOutputs.request.tapTargetsPath = value(flag)
            case "--accessibility-outline": AccessibilityOutputs.request.wantsOutline = true
            default: fail("unknown option \(flag)")
            }
        }

        if listDevices {
            print(DeviceProfile.listing())
            exit(0)
        }
        // The platform and the device have to agree: a TV platform defaults to an Apple TV, and vice versa.
        if config.platform == .tvOS, !deviceWasSet, let tv = DeviceProfile.lookup("apple-tv-4k") { config.device = tv }
        if config.device.idiom == .tv { config.platform = .tvOS }

        if listOnly {
            for (i, p) in previews.enumerated() { print("\(i)\t\(p.name ?? "")") }
            exit(0)
        }
        guard !previews.isEmpty else { fail("no previews found") }
        if let previewName {
            guard let match = previews.firstIndex(where: { $0.name == previewName }) else {
                fail("no preview named \"\(previewName)\". Available: \(previews.map { $0.name ?? "(unnamed)" }.joined(separator: ", "))")
            }
            index = match
        }
        guard previews.indices.contains(index) else { fail("preview index \(index) out of range (found \(previews.count))") }

        // `#Preview(traits:)` supplies defaults; flags given on the command line win.
        let entry = previews[index]
        if orientation == nil {
            switch entry.orientation {
            case "landscapeLeft"?: orientation = .landscapeLeft
            case "landscapeRight"?: orientation = .landscapeRight
            default: break
            }
        }
        config.device.orientation = orientation ?? .portrait
        if !layoutSet {
            switch entry.layout {
            case "fit"?: config.layout = .sizeThatFits
            case "fixed"?: config.layout = .fixed
            default: break
            }
        }
        if !layoutSet, entry.layout == "fixed" {
            if config.width == nil { config.width = entry.width.map { CGFloat($0) } }
            if config.height == nil { config.height = entry.height.map { CGFloat($0) } }
        }

        do {
            let result = try Renderer.render(previews[index].make(), config: config, to: output)
            var payload: [String: Any] = ["output": output, "width": result.pixelSize.width, "height": result.pixelSize.height,
                                          "warnings": result.warnings]
            payload.merge(AccessibilityOutputs.payload) { current, _ in current }
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(decoding: json, as: UTF8.self))
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
}
