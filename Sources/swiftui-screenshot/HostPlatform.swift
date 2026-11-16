import Foundation

// What differs between the operating systems the tool runs on: library file names, loader paths, how a
// library names itself, and where the running executable is. Everything else in the tool is the same on
// Linux and macOS, so platform checks belong here and nowhere else.
//

enum HostPlatform {
    /// The engine's library: the SwiftUI module and every shim module linked into one dynamic library
    /// (Package.swift's `SwiftUIScreenshotEngine` product). Its file name must not be mistaken for Apple's
    /// SwiftUI; the module itself stays `SwiftUI`.
    static let engineLibrary = "SwiftUIScreenshotEngine"

    #if canImport(Darwin)
    /// The host's spelling in `#if os(...)`.
    static let osName = "macOS"
    static let sharedLibraryExtension = "dylib"
    /// The minimum macOS the engine is built for (Package.swift's `platforms`). Every compile against it
    /// targets this version, so the modules load whatever the compiler would default to.
    static let deploymentTarget = "15.0"
    #else
    static let osName = "Linux"
    static let sharedLibraryExtension = "so"
    #endif

    /// `libName.so` on Linux, `libName.dylib` on macOS.
    static func sharedLibraryFile(_ module: String) -> String {
        "lib\(module).\(sharedLibraryExtension)"
    }

    /// The module name of a library file (`libFoo.so` -> `Foo`), or nil if `file` is not one.
    static func libraryName(fromFile file: String) -> String? {
        let suffix = "." + sharedLibraryExtension
        guard file.hasPrefix("lib"), file.hasSuffix(suffix), file.count > 3 + suffix.count else { return nil }
        return String(file.dropFirst(3).dropLast(suffix.count))
    }

    /// Linker flags that give a library built for `module` its identity: the SONAME on Linux, the install
    /// name on macOS. Dependents find it through their rpaths in both cases.
    static func libraryIdentityFlags(_ module: String) -> [String] {
        #if canImport(Darwin)
        return ["-Xlinker", "-install_name", "-Xlinker", "@rpath/" + sharedLibraryFile(module)]
        #else
        return ["-Xlinker", "-soname=" + sharedLibraryFile(module)]
        #endif
    }

    /// Flags every swiftc invocation of the tool gets ahead of its own: none on Linux; on macOS the
    /// deployment target the engine's modules were built for and the filtered SDK (`FilteredSDK`).
    static let compilerFlags: [String] = {
        #if canImport(Darwin)
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let target = ["-target", "\(arch)-apple-macosx\(deploymentTarget)"]
        guard let sdk = FilteredSDK.path else { return target }
        return target + ["-sdk", sdk]
        #else
        return []
        #endif
    }()

    /// Runners format numbers, currencies and dates as en_US (or `SWIFTUI_SCREENSHOT_LOCALE`), whatever the host's
    /// settings. Foundation on Linux reads Locale.current from the POSIX locale variables once, as the process
    /// starts, so they are set here and every runner inherits them; on macOS the runner sets its own defaults
    /// (`_ScreenshotRunner.applyLocale`).
    static func setRenderLocale() {
        #if !canImport(Darwin)
        let identifier = ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_LOCALE"] ?? "en_US"
        setenv("LC_ALL", identifier + ".UTF-8", 1)
        setenv("LANG", identifier + ".UTF-8", 1)
        #endif
    }

    /// The running executable, with symbolic links resolved (an installed tool is usually reached through
    /// a link in a bin directory, and the SDK is found next to the real file).
    static var executablePath: String {
        #if canImport(Darwin)
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return CommandLine.arguments[0] }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
        #else
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
        #endif
    }
}

#if canImport(Darwin)
/// The macOS SDK as user code sees it: only the frameworks Apple's Foundation is built from (Foundation,
/// CoreFoundation, Combine, Security, CoreServices, ...) plus os, OSLog and Observation. Every other framework
/// is left out, so `import ARKit` is "no such module" and `#if canImport(HealthKit)` is false, as on Linux, and
/// no Apple UI framework (which would bring Apple's SwiftUI or UIKit with it) can reach a render. Our modules
/// still shadow the SDK's of the same name through `-I`.
///
/// It is a directory of symbolic links into the real SDK, made once per SDK in the tool's cache. Apple's
/// prebuilt modules still apply to it.
enum FilteredSDK {
    static let path: String? = make()

    /// The modules user code may import from the SDK, beyond the ones Foundation brings with it.
    static let roots = ["Foundation", "Combine", "Security", "os", "OSLog", "Observation", "Dispatch", "Darwin"]

    private static func make() -> String? {
        let env = ProcessInfo.processInfo.environment
        if env["SWIFTUI_SCREENSHOT_FULL_SDK"] == "1" { return nil }
        let fm = FileManager.default
        let xcrun = "/usr/bin/xcrun"
        guard let shown = env["SDKROOT"].flatMap({ $0.isEmpty ? nil : $0 })
                ?? capture(xcrun, ["--sdk", "macosx", "--show-sdk-path"]),
              let real = (try? URL(fileURLWithPath: shown).resolvingSymlinksInPath().path) else { return nil }
        let settings = (try? fm.attributesOfItem(atPath: real + "/SDKSettings.json"))?[.modificationDate] as? Date
        let key = hash([real, settings.map { "\($0.timeIntervalSince1970)" } ?? "", "filtered-sdk-1"])
        let destination = ModuleBuilder.cacheRoot + "/sdk-" + key
        if fm.fileExists(atPath: destination + "/SDKSettings.json") { return destination }

        // The modules Foundation and the other roots are made of, from a dependency scan.
        let work = ModuleBuilder.cacheRoot + "/sdk-scan-\(getpid())"
        try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }
        let source = work + "/roots.swift"
        try? roots.map { "import \($0)" }.joined(separator: "\n").write(toFile: source, atomically: true, encoding: .utf8)
        let swiftc = env["SWIFTC"] ?? "swiftc"
        let scanArguments = (env["SWIFTC"] == nil ? ["swiftc"] : []) + ["-scan-dependencies", source, "-sdk", real,
                                                                        "-o", work + "/scan.json"]
        guard capture(env["SWIFTC"] == nil ? xcrun : swiftc, scanArguments) != nil,
              let scan = try? String(contentsOfFile: work + "/scan.json", encoding: .utf8) else {
            note("warning: could not scan the macOS SDK; user code sees every framework in it")
            return nil
        }
        var allowed = Set<String>()
        for pattern in [#"/System/Library/Frameworks/([A-Za-z0-9_]+)\.framework"#, #"/usr/lib/swift/([A-Za-z0-9_]+)\.swiftmodule"#] {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: scan, range: NSRange(scan.startIndex..., in: scan)) {
                if let range = Range(match.range(at: 1), in: scan) { allowed.insert(String(scan[range])) }
            }
        }
        allowed.formUnion(roots)
        let frameworks = Set(((try? fm.contentsOfDirectory(atPath: real + "/System/Library/Frameworks")) ?? [])
            .filter { $0.hasSuffix(".framework") }.map { String($0.dropLast(".framework".count)) })

        let staging = destination + ".staging-\(getpid())"
        try? fm.removeItem(atPath: staging)
        /// Mirrors `relative` with a link per entry, except `descend` (made a directory and filled by the caller)
        /// and entries `keep` turns down.
        func mirror(_ relative: String, descend: String? = nil, keep: (String) -> Bool = { _ in true }) -> Bool {
            let from = relative.isEmpty ? real : real + "/" + relative
            let to = relative.isEmpty ? staging : staging + "/" + relative
            guard (try? fm.createDirectory(atPath: to, withIntermediateDirectories: true)) != nil,
                  let entries = try? fm.contentsOfDirectory(atPath: from) else { return false }
            for entry in entries where entry != descend && keep(entry) {
                guard (try? fm.createSymbolicLink(atPath: to + "/" + entry, withDestinationPath: from + "/" + entry)) != nil else { return false }
            }
            return true
        }
        let built = mirror("", descend: "System") && mirror("System", descend: "Library")
            && mirror("System/Library", descend: "Frameworks")
            && mirror("System/Library/Frameworks") { entry in
                !entry.hasSuffix(".framework") || allowed.contains(String(entry.dropLast(".framework".count)))
            }
        // usr: everything but usr/lib/swift, whose overlays for left-out frameworks are left out too.
        let usr = built && (try? fm.removeItem(atPath: staging + "/usr")) != nil
            && mirror("usr", descend: "lib") && mirror("usr/lib", descend: "swift")
            && mirror("usr/lib/swift") { entry in
                let name = String(entry.split(separator: ".").first ?? "")
                return !frameworks.contains(name) || allowed.contains(name)
            }
        guard usr else {
            try? fm.removeItem(atPath: staging)
            note("warning: could not make the filtered macOS SDK; user code sees every framework in it")
            return nil
        }
        if (try? fm.moveItem(atPath: staging, toPath: destination)) == nil {
            try? fm.removeItem(atPath: staging)   // another render made it first
        }
        return fm.fileExists(atPath: destination + "/SDKSettings.json") ? destination : nil
    }

    private static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let result = run(executable, arguments)
        guard result.status == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
