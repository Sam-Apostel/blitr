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
  swiftui-screenshot compare <reference> <candidate>     Compare reference screenshots with renders (see compare --help)
  swiftui-screenshot doctor                              Check the installation
  swiftui-screenshot version                             Tool version and the Swift version it was built with

What is rendered (first match wins):
  --view "<expr>"        A view expression, e.g. --view "ContentView()"
  #Preview blocks        Selected with --preview <index|name>, or --all for every one
  PreviewProvider types
  @main App              The first WindowGroup's content
  Widget / WidgetBundle  Each widget from its provider's snapshot, once per supported family
                         (#Preview(as: .systemSmall) ... timeline: and Live Activity previews are #Preview blocks)

Render options:
  -o, --out <file.png>   Output file (default: <first-source-name>.png)
      --out-dir <dir>    Output directory (used with --all / --scheme both)
      --preview <n|name> Which preview (default 0)
      --all              Render every preview
      --device <name>    Device profile (default iphone-16); see `devices`. "iPhone 16 Pro", iphone-16-pro, iphone16pro all work
      --orientation <o>  portrait (default) | landscape (= landscape-left) | landscape-right
      --rounded-corners  Clip to the device's rounded display shape, corners transparent
      --show-island     Draw the Dynamic Island / notch over the content (simulator screenshots do not show it)
      --frame            Draw generic device hardware around the screen: bezel, band, buttons, island or notch
      --frame-dir <dir>  Use your own frame images instead: <dir>/<device-id>.png with a transparent screen
                         (optionally <device-id>-landscape.png); devices without one get the generic frame
      --scheme <s>       light | dark | both (default light; dark on watchOS, which has no light appearance)
      --ios <version>    OS release whose look is drawn: 18, 26, 27 or latest (default latest)
      --os <version>     Same as --ios; the version applies to the platform rendered (tvOS 18, 26, 27, ...)
      --platform <p>     ios (default) | tvos | watchos. Decides which #if os(...) branches of your code are compiled.
                         Implied by --device apple-tv-* and apple-watch-*.
      --layout <l>       device (full screen, default) | fit (size of the view) | fixed
      --width <pt>       Canvas width (fixed), or width proposed to the view (fit)
      --height <pt>      Same for height
      --scale <n>        Pixels per point (default: the device's)
      --padding <pt>     Margin around the view in fit layout
      --background <hex> Background color, or "clear"
      --dynamic-type <s> xSmall ... xxxLarge, accessibility1 ... accessibility5
      --no-chrome        Omit the status bar and home indicator (iPhones at --ios 27 draw no home
                         indicator, as the iOS 27.0 simulator does)
      --show-tips        Display TipKit tips (as Tips.showAllTipsForTesting() does); hidden by default
      --assets <dir>     Extra directory with images / .xcassets (repeatable)
      --fonts <dir>      Extra font directory, searched first (repeatable)
      --open-fonts       Use the open substitute fonts even if Apple's fonts are installed
      --task-timeout <s> Real seconds .task closures may run before the frame is taken (default 0.5)
      --settle-time <s>  Virtual seconds that pass before the frame is taken: Task.sleep calls that end within
                         them return at once (default 2). Sleeps that end later wait past the frame
      --time-zone <tz>   The device's time zone, an IANA name such as Europe/Brussels (default UTC)
      --allow-network    Let the code reach the network; by default requests fail at once (offline)
      --widget-family <f>          Widgets: render this family (systemSmall, systemMedium, systemLarge,
                                   systemExtraLarge, accessoryCircular, accessoryRectangular, accessoryInline)
      --widget-rendering-mode <m>  Widgets: fullColor | accented | vibrant (default: fullColor; vibrant for
                                   accessory families). See docs/WIDGETS.md
      --accessibility-tree <file.json>  Write the accessibility tree, tap-target data and issues as JSON
      --tap-targets <file.png>          Write the screenshot dimmed with every tap target outlined
                                        (green >= 44x44pt, red below)
      --accessibility-outline           Print the accessibility tree as indented text on stdout
      --focus-map <file.json>           Write the tvOS focus map: focusable elements, where each remote press
                                        moves focus, the press path to each element, and issues (unreachable,
                                        one-way, traps). A summary goes to stderr. See docs/FOCUS.md
      --focus-overlay <file.png>        Write the screenshot with focusable elements numbered and move arrows
      --press <list>                    Siri Remote presses applied after the first frame, comma-separated:
                                        up, down, left, right, select, menu, playpause (repeatable)
      --focus <selector>                Start with focus on an element: its id, #index, or (part of) its label
\(InteractionCLIOptions.usage)
      --json             Print one JSON object per image instead of text
      --no-cache         Recompile even if an identical build is cached
  -v, --verbose          Show the compiler invocation

\(ProjectSession.usage)
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
    /// Directory containing SwiftUI.swiftmodule and the engine library (HostPlatform.engineLibrary).
    var sdk: String
    var fontDirectories: [String]
    /// Apple's own fonts, if the user installed them. Used ahead of the open substitutes unless `--open-fonts`.
    var appleFontDirectory: String?
    var swiftc: String

    static func locate() -> Installation {
        let fm = FileManager.default
        let executable = HostPlatform.executablePath
        let binDir = (executable as NSString).deletingLastPathComponent
        let env = ProcessInfo.processInfo.environment

        // The module sits next to the tool in a build tree, or under ../lib in an installed layout.
        let sdkCandidates = [env["SWIFTUI_SCREENSHOT_SDK"], binDir, binDir + "/../lib/swiftui-screenshot"].compactMap { $0 }
        guard let sdk = sdkCandidates.first(where: { fm.fileExists(atPath: $0 + "/SwiftUI.swiftmodule") }) else {
            fail("cannot find the SwiftUI module next to the tool (looked in: \(sdkCandidates.joined(separator: ", "))). Set SWIFTUI_SCREENSHOT_SDK.")
        }

        var fonts: [String] = []
        var appleFonts: String?
        if let dir = env["SWIFTUI_SCREENSHOT_FONTS"] { fonts += dir.split(separator: ":").map(String.init) }
        if fm.fileExists(atPath: sdk + "/fonts") { fonts.append(sdk + "/fonts") }
        // In a source checkout the fonts are in <repo>/Vendor/fonts: walk up from the build dir.
        var dir = binDir
        for _ in 0..<8 {
            if fm.fileExists(atPath: dir + "/Vendor/fonts") {
                // Apple's fonts, when the user fetched them (scripts/fetch-apple-fonts.sh), take precedence.
                if fm.fileExists(atPath: dir + "/Vendor/apple-fonts/SF-Pro.ttf") { appleFonts = dir + "/Vendor/apple-fonts" }
                fonts.append(dir + "/Vendor/fonts")
                break
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        if fm.fileExists(atPath: sdk + "/apple-fonts/SF-Pro.ttf") { appleFonts = sdk + "/apple-fonts" }
        #if canImport(Darwin)
        // A Mac has SF Pro, SF Pro Rounded, SF Mono, New York and Apple Color Emoji installed with the system.
        if appleFonts == nil, fm.fileExists(atPath: "/System/Library/Fonts/SFNS.ttf") { appleFonts = "/System/Library/Fonts" }
        #endif

        var swiftc = env["SWIFTC"] ?? ""
        if swiftc.isEmpty {
            let paths = (env["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/swift/usr/bin", "/usr/local/swift/usr/bin"]
            swiftc = paths.map { $0 + "/swiftc" }.first(where: { fm.isExecutableFile(atPath: $0) }) ?? ""
        }
        return Installation(sdk: (sdk as NSString).standardizingPath, fontDirectories: fonts, appleFontDirectory: appleFonts, swiftc: swiftc)
    }

    /// The modules of the SDK: every `Name.swiftmodule` next to the SwiftUI module (SwiftUI, Combine, the
    /// shim frameworks and the Foundation shim, all linked into the engine library).
    var modules: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: sdk)) ?? []).filter { $0.hasSuffix(".swiftmodule") }
            .map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    /// Identity of the SDK for build caches: size and date of every library and module file in it, so a
    /// rebuilt SwiftUI or shim module invalidates what was compiled against the old one.
    var stamp: String {
        let fm = FileManager.default
        var parts: [String] = []
        for name in ((try? fm.contentsOfDirectory(atPath: sdk)) ?? []).sorted() {
            let path = sdk + "/" + name
            if HostPlatform.libraryName(fromFile: name) != nil {
                parts.append(name + fileStamp(path))
            } else if name.hasSuffix(".swiftmodule") {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
                let files = isDirectory.boolValue ? ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted().filter { $0.hasSuffix(".swiftmodule") }.map { path + "/" + $0 } : [path]
                parts += files.map { name + fileStamp($0) }
            }
        }
        return hash(parts)
    }

    private func fileStamp(_ path: String) -> String {
        (try? FileManager.default.attributesOfItem(atPath: path))
            .map { "-\($0[.size] ?? 0)-\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" } ?? ""
    }

    /// Libraries every compile against the SDK links. The shim frameworks and the Foundation shim need no flag
    /// of their own: their code is in the engine library, which the SwiftUI module also autolinks.
    var linkFlags: [String] {
        ["-I", sdk, "-L", sdk, "-l" + HostPlatform.engineLibrary, "-Xlinker", "-rpath", "-Xlinker", sdk]
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
    // Drain both pipes at once, before waiting: reading one to the end while the child is blocked
    // writing more than a pipe buffer (64 KB) to the other would deadlock.
    nonisolated(unsafe) var errData = Data()
    let drained = DispatchGroup()
    if captureOutput {
        DispatchQueue.global().async(group: drained) { errData = err.fileHandleForReading.readDataToEndOfFile() }
    }
    let outData = captureOutput ? out.fileHandleForReading.readDataToEndOfFile() : Data()
    drained.wait()
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
    var schemeWasSet = false
    var json = false
    var noCache = false
    var openFonts = false
    /// Swift's spelling of the rendered platform (iOS, tvOS, ...). Affects compilation, not just drawing.
    var platform = "iOS"
    var platformWasSet = false
    var verbose = false
    /// Passed through to the runner unchanged.
    var runnerArguments: [String] = []
    var userAssetDirectories: [String] = []
    var userFontDirectories: [String] = []
    var accessibility = AccessibilityCLIOptions()
    var focus = FocusCLIOptions()
    var interaction = InteractionCLIOptions()
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
            options.schemeWasSet = true
        case "--json": options.json = true
        case "--no-cache": options.noCache = true
        case "--open-fonts": options.openFonts = true
        case "--platform":
            let raw = value(arg).lowercased()
            guard let name = ["ios": "iOS", "tvos": "tvOS", "watchos": "watchOS", "macos": "macOS", "visionos": "visionOS"][raw] else {
                fail("--platform must be ios, tvos, watchos, macos or visionos")
            }
            options.platform = name
            options.platformWasSet = true
        case "-v", "--verbose": options.verbose = true
        case "--assets": options.userAssetDirectories.append(value(arg))
        case "--fonts": options.userFontDirectories.append(value(arg))
        case "--device", "--layout", "--width", "--height", "--scale", "--padding", "--background", "--dynamic-type", "--task-budget", "--task-timeout",
             "--settle-time", "--ios", "--time-zone":
            options.runnerArguments += [arg, value(arg)]
        case "--os": options.runnerArguments += ["--ios", value(arg)]
        case "--no-chrome", "--show-tips", "--allow-network": options.runnerArguments.append(arg)
        case "--orientation": options.runnerArguments += [arg, value(arg)]
        case "--rounded-corners", "--show-island", "--frame": options.runnerArguments.append(arg)
        case "--frame-dir":
            let dir = value(arg)
            options.runnerArguments += [arg, dir.hasPrefix("/") ? dir : FileManager.default.currentDirectoryPath + "/" + dir]
        case "--widget-family", "--widget-rendering-mode": options.runnerArguments += [arg, value(arg)]
        case "--accessibility-tree", "--tap-targets": options.accessibility.record(arg, value: value(arg))
        case "--accessibility-outline": options.accessibility.record(arg, value: nil)
        case "--focus-map", "--focus-overlay", "--press", "--focus": options.focus.record(arg, value: value(arg))
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            if options.interaction.record(arg, value: { value(arg) }) { continue }
            if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n\(usage)", code: 2) }
            options.inputs.append(arg)
        }
    }
    // A device implies its platform unless one was given explicitly.
    if !options.platformWasSet, let index = options.runnerArguments.firstIndex(of: "--device"), index + 1 < options.runnerArguments.count {
        let device = options.runnerArguments[index + 1].lowercased().filter { $0.isLetter || $0.isNumber }
        if device.hasPrefix("appletv") || device == "tv" { options.platform = "tvOS" }
        if device.hasPrefix("applewatch") || device == "watch" { options.platform = "watchOS" }
    }
    options.runnerArguments += ["--platform", options.platform]
    return options
}

// MARK: - Build

struct Build {
    var runner: String
    var previews: [(index: Int, name: String)]
}

func build(_ options: Options, _ installation: Installation) -> Build {
    if ProjectSession.current != nil { return ProjectSession.build(options, installation) }
    guard !options.inputs.isEmpty else { fail("no input files\n\n\(usage)", code: 2) }
    guard !installation.swiftc.isEmpty else { fail("swiftc not found. Install a Swift 6 toolchain and put it on PATH, or set SWIFTC.") }
    let (paths, _) = collectSources(options.inputs)
    guard !paths.isEmpty else { fail("no .swift files found in \(options.inputs.joined(separator: ", "))") }
    let sources: [(path: String, contents: String)] = paths.map { path in
        guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
        return (path, String(decoding: data, as: UTF8.self))
    }

    var preprocessor = Preprocessor()
    preprocessor.platform = options.platform
    preprocessor.hostOS = HostPlatform.osName
    let output = preprocessor.process(sources, viewExpression: options.view)
    for warning in output.warnings { note("warning: \(warning)") }
    guard !output.entries.isEmpty else {
        fail("nothing to render: no #Preview, PreviewProvider or @main App found. Pass --view \"YourView()\" to pick a view.")
    }

    // Cache key: the rewritten sources plus the identity of the module they are compiled against.
    let key = hash(output.files.flatMap { [$0.name, $0.contents] } + [installation.stamp, installation.swiftc])
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
        var arguments = HostPlatform.compilerFlags + ["-swift-version", "5", "-Onone", "-module-name", "App", "-no-color-diagnostics"] + installation.linkFlags
        arguments += written + ["-o", runner]
        if options.verbose { note(([installation.swiftc] + arguments).joined(separator: " ")) }
        let result = run(installation.swiftc, arguments)
        if result.status != 0 || !FileManager.default.isExecutableFile(atPath: runner) {
            // Point diagnostics back at the user's files instead of the rewritten copies.
            var diagnostics = result.stderr + result.stdout
            for (rewritten, original) in originalPath { diagnostics = diagnostics.replacingOccurrences(of: rewritten, with: original) }
            FileHandle.standardError.write(Data(diagnostics.utf8))
            try? FileManager.default.removeItem(atPath: work)
            if let mismatch = compilerMismatch(installation) { fail(mismatch) }
            let report = UnsupportedReport(diagnostics: diagnostics, stubbedModules: [:])
            if !report.isEmpty { note(report.text()) }
            fail("the sources did not compile against this renderer's SwiftUI module. Errors about unknown members usually mean an API this renderer does not implement yet.")
        }
    }

    // The options go along: widget previews expand per --widget-family and --device.
    let listing = run(runner, ["--list"] + options.runnerArguments)
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
    var options = options
    // watchOS has no light appearance: watch apps are drawn dark unless --scheme asks otherwise.
    if !options.schemeWasSet, options.platform == "watchOS" { options.schemes = ["dark"] }
    let built = build(options, installation)
    let (_, autoAssets) = ProjectSession.current == nil ? collectSources(options.inputs) : ([], [])

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
            arguments += options.accessibility.arguments(png: path, stem: stem, multiple: multiple, outDir: options.outDir)
            arguments += options.focus.arguments(png: path, stem: stem, multiple: multiple, outDir: options.outDir)
            arguments += options.interaction.arguments(png: path, stem: stem, multiple: multiple, outDir: options.outDir)
            let apple = options.openFonts ? [] : [installation.appleFontDirectory].compactMap { $0 }
            for dir in options.userFontDirectories + apple + installation.fontDirectories { arguments += ["--fonts", dir] }
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
            options.accessibility.report(line, json: options.json)
            options.focus.report(line, json: options.json)
            options.interaction.report(line, json: options.json)
            if !result.stderr.isEmpty { note(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    exit(failures == 0 ? 0 : 1)
}

// MARK: - Version

/// "Swift version 6.4.2 (swift-6.4.2-RELEASE)" out of compiler output or a .swiftmodule's metadata.
func swiftVersionBanner(in text: String) -> String? {
    guard let range = text.range(of: #"Swift version \S+ \([^)]*\)"#, options: .regularExpression) else { return nil }
    return String(text[range])
}

/// The compiler that built the bundled modules, read from the module file itself.
func moduleCompiler(_ installation: Installation) -> String? {
    let dir = installation.sdk + "/SwiftUI.swiftmodule"
    guard let name = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.first(where: { $0.hasSuffix(".swiftmodule") }),
          let data = FileManager.default.contents(atPath: dir + "/" + name) else { return nil }
    return swiftVersionBanner(in: String(decoding: data.map { $0 < 0x80 ? $0 : 0x20 }, as: UTF8.self))
}

func runtimeCompiler(_ installation: Installation) -> String? {
    guard !installation.swiftc.isEmpty else { return nil }
    return swiftVersionBanner(in: run(installation.swiftc, ["--version"]).stdout)
}

/// A plain-language message if the compiler on this machine cannot load the bundled modules.
func compilerMismatch(_ installation: Installation) -> String? {
    guard let built = moduleCompiler(installation), let current = runtimeCompiler(installation), built != current else { return nil }
    return "the bundled SwiftUI modules were built with \(built), but \(installation.swiftc) is \(current). "
        + "Swift modules only load with the exact compiler that built them: install \(built) (set SWIFTC or put it first on PATH), or rebuild swiftui-screenshot with this compiler."
}

func versionCommand(_ installation: Installation) {
    var version = "dev", commit = ""
    let file = installation.sdk + "/../../share/swiftui-screenshot/VERSION"
    if let text = try? String(contentsOfFile: file, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { if parts[0] == "version" { version = parts[1] } else if parts[0] == "commit" { commit = parts[1] } }
        }
    }
    print("swiftui-screenshot \(version)" + (commit.isEmpty ? "" : " (\(commit))"))
    print("built with:     \(moduleCompiler(installation) ?? "unknown")")
    if let current = runtimeCompiler(installation) { print("compiler now:   \(current)") }
}

func doctor(_ installation: Installation) {
    print("SwiftUI module: \(installation.sdk)")
    print("swiftc:         \(installation.swiftc.isEmpty ? "NOT FOUND" : installation.swiftc)")
    if !installation.swiftc.isEmpty { print("                " + run(installation.swiftc, ["--version"]).stdout.split(separator: "\n").first.map(String.init)!) }
    print("built with:     \(moduleCompiler(installation) ?? "unknown")")
    let mismatch = compilerMismatch(installation)
    if let mismatch { print("PROBLEM:        \(mismatch)") }
    print("font dirs:      \(installation.fontDirectories.isEmpty ? "NONE (run scripts/bootstrap.sh)" : installation.fontDirectories.joined(separator: ", "))")
    let fm = FileManager.default
    let hasSystemFont = installation.appleFontDirectory != nil
        || installation.fontDirectories.contains { fm.fileExists(atPath: $0 + "/InterVariable.ttf") || fm.fileExists(atPath: $0 + "/SF-Pro.ttf") }
    let usesSF = installation.appleFontDirectory != nil || installation.fontDirectories.contains { fm.fileExists(atPath: $0 + "/SF-Pro.ttf") }
    if let apple = installation.appleFontDirectory { print("Apple fonts:    \(apple)") }
    print("system font:    \(usesSF ? "SF Pro (fetched from Apple)" : hasSystemFont ? "Inter (open substitute; run scripts/fetch-apple-fonts.sh for SF Pro)" : "MISSING")")
    exit(hasSystemFont && !installation.swiftc.isEmpty && mismatch == nil ? 0 : 1)
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
        arguments = ProjectSession.takeFlags(arguments)

        switch command {
        case "render":
            render(ProjectSession.prepare(parse(arguments), command: command), Installation.locate())
        case "check":
            CheckCommand.run(arguments)
        case "list":
            let options = ProjectSession.prepare(parse(arguments), command: command)
            for preview in build(options, Installation.locate()).previews {
                print("\(preview.index)\t\(preview.name.isEmpty ? "(unnamed)" : preview.name)")
            }
        case "devices":
            // The table lives in the runtime module (Render/Devices.swift); ask a runner for it.
            listDevices(Installation.locate())
        case "compare":
            compareCommand(arguments, Installation.locate())
        case "doctor":
            doctor(Installation.locate())
        case "version", "--version", "-V":
            versionCommand(Installation.locate())
        case "-h", "--help", "help":
            print(usage)
        default:
            fail("unknown command \(command)\n\n\(usage)", code: 2)
        }
    }
}
