// The public surface used by the generated `main.swift` that wraps user code.

/// One renderable entry: a `#Preview`, a `PreviewProvider`, or an explicit view expression.
public struct _PreviewEntry {
    let name: String?
    let make: @MainActor () -> AnyView
    public init<V: View>(_ name: String? = nil, @ViewBuilder _ body: @escaping @MainActor () -> V) {
        self.name = name
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
        var args = Array(CommandLine.arguments.dropFirst())

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
                let key = value(flag).lowercased()
                guard let device = DeviceProfile.all[key] else {
                    fail("unknown device \"\(key)\". Known: \(DeviceProfile.all.keys.sorted().joined(separator: ", "))")
                }
                config.device = device
            case "--layout":
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
            default: fail("unknown option \(flag)")
            }
        }

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

        do {
            let result = try Renderer.render(previews[index].make(), config: config, to: output)
            let payload: [String: Any] = ["output": output, "width": result.pixelSize.width, "height": result.pixelSize.height,
                                          "warnings": result.warnings]
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(decoding: json, as: UTF8.self))
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
}
