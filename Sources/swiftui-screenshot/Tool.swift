import Foundation

// swiftui-screenshot: renders SwiftUI source files to PNG on Linux.
//
// The tool rewrites the given sources (see Preprocessor), compiles them against the
// bundled `SwiftUI` module into a small runner executable (cached by content), and runs
// that runner once per requested image.

let usage = """
Usage:
  swiftui-screenshot render <file-or-dir>... [options]   Render previews to PNG
  swiftui-screenshot list <file-or-dir>...               List the previews found
  swiftui-screenshot devices                             List device profiles
  swiftui-screenshot doctor                              Check the installation

What is rendered (first match wins):
  --view "<expr>"        A view expression, e.g. --view "ContentView()"
  #Preview blocks        Selected with --preview <index|name>, or --all for every one
  PreviewProvider types
  @main App              The first WindowGroup's content

Render options:
  -o, --out <file.png>   Output file (default: <first-source-name>.png)
      --out-dir <dir>    Output directory (used with --all / --scheme both)
      --preview <n|name> Which preview (default 0)
      --all              Render every preview
      --device <name>    Device profile (default iphone-16); see `devices`
      --scheme <s>       light | dark | both (default light)
      --layout <l>       device (full screen, default) | fit (size of the view) | fixed
      --width <pt>       Canvas width (fixed), or width proposed to the view (fit)
      --height <pt>      Same for height
      --scale <n>        Pixels per point (default: the device's)
      --padding <pt>     Margin around the view in fit layout
      --background <hex> Background color, or "clear"
      --dynamic-type <s> xSmall ... xxxLarge, accessibility1 ... accessibility5
      --no-chrome        Omit the status bar and home indicator
      --assets <dir>     Extra directory with images / .xcassets (repeatable)
      --fonts <dir>      Extra font directory, e.g. with your own SF-Pro.ttf (repeatable)
      --task-budget <s>  Seconds .task closures may run before the frame is taken (default 0.5)
      --json             Print one JSON object per image instead of text
      --no-cache         Recompile even if an identical build is cached
  -v, --verbose          Show the compiler invocation
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(code)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Installation layout

struct Installation {
    /// Directory containing SwiftUI.swiftmodule and libSwiftUI.so.
    var sdk: String
    var fontDirectories: [String]
    var swiftc: String

    static func locate() -> Installation {
        let fm = FileManager.default
        let executable = (try? fm.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
        let binDir = (executable as NSString).deletingLastPathComponent
        let env = ProcessInfo.processInfo.environment

        // The module sits next to the tool in a build tree, or under ../lib in an installed layout.
        let sdkCandidates = [env["SWIFTUI_SCREENSHOT_SDK"], binDir, binDir + "/../lib/swiftui-screenshot"].compactMap { $0 }
        guard let sdk = sdkCandidates.first(where: { fm.fileExists(atPath: $0 + "/SwiftUI.swiftmodule") }) else {
            fail("cannot find the SwiftUI module next to the tool (looked in: \(sdkCandidates.joined(separator: ", "))). Set SWIFTUI_SCREENSHOT_SDK.")
        }

        var fonts: [String] = []
        if let dir = env["SWIFTUI_SCREENSHOT_FONTS"] { fonts += dir.split(separator: ":").map(String.init) }
        if fm.fileExists(atPath: sdk + "/fonts") { fonts.append(sdk + "/fonts") }
        // In a source checkout the fonts are in <repo>/Vendor/fonts: walk up from the build dir.
        var dir = binDir
        for _ in 0..<8 {
            if fm.fileExists(atPath: dir + "/Vendor/fonts") { fonts.append(dir + "/Vendor/fonts"); break }
            dir = (dir as NSString).deletingLastPathComponent
        }

        var swiftc = env["SWIFTC"] ?? ""
        if swiftc.isEmpty {
            let paths = (env["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/swift/usr/bin", "/usr/local/swift/usr/bin"]
            swiftc = paths.map { $0 + "/swiftc" }.first(where: { fm.isExecutableFile(atPath: $0) }) ?? ""
        }
        return Installation(sdk: (sdk as NSString).standardizingPath, fontDirectories: fonts, swiftc: swiftc)
    }
}

// MARK: - Helpers

@discardableResult
func run(_ executable: String, _ arguments: [String], captureOutput: Bool = true) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let out = Pipe(), err = Pipe()
    if captureOutput {
        process.standardOutput = out
        process.standardError = err
    }
    do { try process.run() } catch { fail("could not launch \(executable): \(error.localizedDescription)") }
    // Read before waiting so a full pipe cannot block the child.
    let outData = captureOutput ? out.fileHandleForReading.readDataToEndOfFile() : Data()
    let errData = captureOutput ? err.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
}

/// FNV-1a, enough to key the build cache.
func hash(_ parts: [String]) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for part in parts {
        for byte in part.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        h = (h ^ 0xff) &* 0x100000001b3
    }
    return String(h, radix: 16)
}

func collectSources(_ inputs: [String]) -> (files: [String], assetDirectories: [String]) {
    let fm = FileManager.default
    var files: [String] = [], assets: [String] = []
    for input in inputs {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: input, isDirectory: &isDirectory) else { fail("no such file or directory: \(input)") }
        if isDirectory.boolValue {
            assets.append(input)
            guard let walker = fm.enumerator(atPath: input) else { continue }
            for case let relative as String in walker {
                let parts = relative.split(separator: "/")
                // Skip build products, tests and package manifests: they are not part of the UI module.
                if parts.contains(where: { $0 == ".build" || $0 == "Tests" || $0.hasSuffix("Tests") || $0 == "Pods" || $0 == "DerivedData" || $0.hasPrefix(".") }) { continue }
                if relative.hasSuffix(".swift"), parts.last != "Package.swift" { files.append(input + "/" + relative) }
            }
        } else {
            files.append(input)
            assets.append((input as NSString).deletingLastPathComponent.isEmpty ? "." : (input as NSString).deletingLastPathComponent)
        }
    }
    return (files.sorted(), assets)
}

// MARK: - Arguments

struct Options {
    var inputs: [String] = []
    var out: String?
    var outDir: String?
    var preview: String?
    var all = false
    var view: String?
    var schemes = ["light"]
    var json = false
    var noCache = false
    var verbose = false
    /// Passed through to the runner unchanged.
    var runnerArguments: [String] = []
    var userAssetDirectories: [String] = []
    var userFontDirectories: [String] = []
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var args = arguments
    func value(_ flag: String) -> String {
        guard !args.isEmpty else { fail("\(flag) needs a value") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "-o", "--out": options.out = value(arg)
        case "--out-dir": options.outDir = value(arg)
        case "--preview": options.preview = value(arg)
        case "--all": options.all = true
        case "--view": options.view = value(arg)
        case "--scheme":
            let v = value(arg)
            guard ["light", "dark", "both"].contains(v) else { fail("--scheme must be light, dark or both") }
            options.schemes = v == "both" ? ["light", "dark"] : [v]
        case "--json": options.json = true
        case "--no-cache": options.noCache = true
        case "-v", "--verbose": options.verbose = true
        case "--assets": options.userAssetDirectories.append(value(arg))
        case "--fonts": options.userFontDirectories.append(value(arg))
        case "--device", "--layout", "--width", "--height", "--scale", "--padding", "--background", "--dynamic-type", "--task-budget":
            options.runnerArguments += [arg, value(arg)]
        case "--no-chrome": options.runnerArguments.append(arg)
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n\(usage)", code: 2) }
            options.inputs.append(arg)
        }
    }
    return options
}

// MARK: - Build

struct Build {
    var runner: String
    var previews: [(index: Int, name: String)]
}

func build(_ options: Options, _ installation: Installation) -> Build {
    guard !options.inputs.isEmpty else { fail("no input files\n\n\(usage)", code: 2) }
    guard !installation.swiftc.isEmpty else { fail("swiftc not found. Install a Swift 6 toolchain and put it on PATH, or set SWIFTC.") }
    let (paths, _) = collectSources(options.inputs)
    guard !paths.isEmpty else { fail("no .swift files found in \(options.inputs.joined(separator: ", "))") }
    let sources: [(path: String, contents: String)] = paths.map { path in
        guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
        return (path, String(decoding: data, as: UTF8.self))
    }

    var preprocessor = Preprocessor()
    let output = preprocessor.process(sources, viewExpression: options.view)
    guard !output.entries.isEmpty else {
        fail("nothing to render: no #Preview, PreviewProvider or @main App found. Pass --view \"YourView()\" to pick a view.")
    }

    // Cache key: the rewritten sources plus the identity of the module they are compiled against.
    let moduleStamp = (try? FileManager.default.attributesOfItem(atPath: installation.sdk + "/libSwiftUI.so"))
        .map { "\($0[.size] ?? 0)-\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" } ?? ""
    let key = hash(output.files.flatMap { [$0.name, $0.contents] } + [moduleStamp, installation.swiftc])
    let cacheRoot = ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_CACHE"]
        ?? (NSHomeDirectory() + "/.cache/swiftui-screenshot")
    let work = cacheRoot + "/" + key
    let runner = work + "/runner"

    if options.noCache || !FileManager.default.isExecutableFile(atPath: runner) {
        try? FileManager.default.removeItem(atPath: work)
        do { try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true) } catch {
            fail("cannot create cache directory \(work): \(error.localizedDescription)")
        }
        var written: [String] = []
        var originalPath: [String: String] = [:]
        for (index, file) in output.files.enumerated() {
            let path = work + "/" + file.name
            do { try file.contents.write(toFile: path, atomically: true, encoding: .utf8) } catch { fail("cannot write \(path)") }
            written.append(path)
            if index < sources.count { originalPath[path] = sources[index].path }
        }
        var arguments = ["-swift-version", "5", "-Onone", "-module-name", "App", "-no-color-diagnostics",
                         "-I", installation.sdk, "-L", installation.sdk, "-lSwiftUI",
                         "-Xlinker", "-rpath", "-Xlinker", installation.sdk]
        arguments += written + ["-o", runner]
        if options.verbose { note(([installation.swiftc] + arguments).joined(separator: " ")) }
        let result = run(installation.swiftc, arguments)
        if result.status != 0 || !FileManager.default.isExecutableFile(atPath: runner) {
            // Point diagnostics back at the user's files instead of the rewritten copies.
            var diagnostics = result.stderr + result.stdout
            for (rewritten, original) in originalPath { diagnostics = diagnostics.replacingOccurrences(of: rewritten, with: original) }
            FileHandle.standardError.write(Data(diagnostics.utf8))
            try? FileManager.default.removeItem(atPath: work)
            fail("the sources did not compile against the Linux SwiftUI module. Errors about unknown members usually mean an API this renderer does not implement yet.")
        }
    }

    let listing = run(runner, ["--list"])
    guard listing.status == 0 else { fail("runner failed to list previews:\n\(listing.stderr)") }
    let previews: [(Int, String)] = listing.stdout.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard let index = Int(parts[0]) else { return nil }
        return (index, parts.count > 1 ? String(parts[1]) : "")
    }
    return Build(runner: runner, previews: previews)
}

// MARK: - Commands

func render(_ options: Options, _ installation: Installation) {
    let built = build(options, installation)
    let (_, autoAssets) = collectSources(options.inputs)

    var selected = built.previews
    if !options.all {
        if let wanted = options.preview {
            if let index = Int(wanted) { selected = selected.filter { $0.index == index } }
            else { selected = selected.filter { $0.name == wanted } }
            guard !selected.isEmpty else {
                fail("no preview \"\(wanted)\". Available: " + built.previews.map { "\($0.index): \($0.name.isEmpty ? "(unnamed)" : $0.name)" }.joined(separator: ", "))
            }
        } else {
            selected = Array(selected.prefix(1))
        }
    }

    let firstInput = options.inputs[0]
    let stem = ((firstInput as NSString).lastPathComponent as NSString).deletingPathExtension
    let multiple = selected.count > 1 || options.schemes.count > 1
    if multiple, options.out != nil, options.outDir == nil {
        fail("several images will be produced; use --out-dir instead of --out")
    }
    if let dir = options.outDir { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }

    var failures = 0
    for preview in selected {
        for scheme in options.schemes {
            var path: String
            if let out = options.out, !multiple {
                path = out
            } else {
                var name = stem
                if selected.count > 1 || options.all {
                    let label = preview.name.isEmpty ? "\(preview.index)" : preview.name
                    name += "-" + label.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
                }
                if options.schemes.count > 1 { name += "-" + scheme }
                path = (options.outDir ?? ".") + "/" + name + ".png"
            }
            var arguments = ["--out", path, "--preview", "\(preview.index)", "--scheme", scheme] + options.runnerArguments
            for dir in options.userFontDirectories + installation.fontDirectories { arguments += ["--fonts", dir] }
            for dir in options.userAssetDirectories + autoAssets { arguments += ["--assets", dir] }
            let result = run(built.runner, arguments)
            if result.status != 0 {
                failures += 1
                note(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                if result.status != 2 { note("error: rendering \(path) crashed (exit \(result.status))") }
                continue
            }
            let line = result.stdout.split(separator: "\n").last.map(String.init) ?? ""
            if options.json {
                print(line)
            } else if let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("\(path)  \(object["width"] ?? "?")x\(object["height"] ?? "?")")
                for warning in (object["warnings"] as? [String]) ?? [] { note("warning: \(warning)") }
            } else {
                print(path)
            }
            if !result.stderr.isEmpty { note(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    exit(failures == 0 ? 0 : 1)
}

func doctor(_ installation: Installation) {
    print("SwiftUI module: \(installation.sdk)")
    print("swiftc:         \(installation.swiftc.isEmpty ? "NOT FOUND" : installation.swiftc)")
    if !installation.swiftc.isEmpty { print("                " + run(installation.swiftc, ["--version"]).stdout.split(separator: "\n").first.map(String.init)!) }
    print("font dirs:      \(installation.fontDirectories.isEmpty ? "NONE (run scripts/bootstrap.sh)" : installation.fontDirectories.joined(separator: ", "))")
    let fm = FileManager.default
    let hasSystemFont = installation.fontDirectories.contains { fm.fileExists(atPath: $0 + "/InterVariable.ttf") || fm.fileExists(atPath: $0 + "/SF-Pro.ttf") }
    let usesSF = installation.fontDirectories.contains { fm.fileExists(atPath: $0 + "/SF-Pro.ttf") }
    print("system font:    \(usesSF ? "SF Pro (user supplied)" : hasSystemFont ? "Inter (substitute for SF Pro)" : "MISSING")")
    exit(hasSystemFont && !installation.swiftc.isEmpty ? 0 : 1)
}

// MARK: - Entry

@main
enum Tool {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            print(usage)
            exit(2)
        }
        arguments.removeFirst()

        switch command {
        case "render":
            render(parse(arguments), Installation.locate())
        case "list":
            let options = parse(arguments)
            for preview in build(options, Installation.locate()).previews {
                print("\(preview.index)\t\(preview.name.isEmpty ? "(unnamed)" : preview.name)")
            }
        case "devices":
            // Mirrors the device table in the runtime module (Render/Renderer.swift).
            print(["iphone-se", "iphone-16", "iphone-16-plus", "iphone-16-pro", "iphone-16-pro-max",
                   "iphone-17", "iphone-17-pro", "iphone-17-pro-max", "ipad", "ipad-pro-11"].joined(separator: "\n"))
        case "doctor":
            doctor(Installation.locate())
        case "-h", "--help", "help":
            print(usage)
        default:
            fail("unknown command \(command)\n\n\(usage)", code: 2)
        }
    }
}
