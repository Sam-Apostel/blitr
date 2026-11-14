import Foundation

// Compiles a project's modules: each local package target (and importable framework target) as its own
// dynamic library, in dependency order, then the entry target into a runner executable that links them.
// Every module is cached by a hash of its (rewritten) sources, flags, dependencies, the SwiftUI module
// and this tool, so a second render in the same project only recompiles what changed.

struct BuiltModule {
    var name: String
    var directory: String
    var key: String
    /// Directory serving as the module's `Bundle.module`, if it has resources.
    var resourceDirectory: String?
}

struct CompileFailure: Error {
    var module: String
    var origin: String
    /// Diagnostics with paths pointing at the user's files.
    var diagnostics: String
    /// A fuller summary, when a missing module stopped the compiler early and the module was type-checked
    /// again with stand-ins to see what is used from it.
    var report: UnsupportedReport?
}

/// The file of a module as compiled: the original path and the text handed to the compiler.
struct CompiledSource {
    var path: String
    var contents: String
}

struct ModuleBuilder {
    let installation: Installation
    var platform: String
    var verbose = false
    var noCache = false

    static var cacheRoot: String {
        ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_CACHE"] ?? (NSHomeDirectory() + "/.cache/swiftui-screenshot")
    }

    /// Modules shipped next to the SwiftUI module (SwiftUI, Combine, the shim frameworks, CoreText, the
    /// Foundation shim). A module importing any of them is compiled against the SDK.
    var shimModules: [String] { installation.modules }

    static func stamp(_ path: String) -> String {
        (try? FileManager.default.attributesOfItem(atPath: path))
            .map { "\($0[.size] ?? 0)-\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" } ?? ""
    }

    /// Identity of everything a compiled module depends on besides its own inputs.
    var environmentStamp: [String] {
        let tool = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
        return [installation.swiftc, installation.stamp, ModuleBuilder.stamp(tool), "module-builder-2"]
            + ModuleBuilder.extraModuleDirectories.flatMap { directory in
                [directory] + ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted().map { $0 + ModuleBuilder.stamp(directory + "/" + $0) }
            } + ModuleBuilder.extraImports
    }

    /// True when the module's sources use SwiftUI or another module of the SDK, so they are compiled
    /// against it with the same rewriting as app code. Foundation-only modules compile unchanged.
    func needsSDK(_ sources: [(path: String, contents: String)]) -> Bool {
        let sdkModules = Set(shimModules)
        for source in sources {
            let index = SwiftIndexer.index(Array(source.contents.utf8))
            if !index.importsModules.isDisjoint(with: sdkModules) || index.hasPreviews { return true }
            // Apple frameworks the SDK does not provide still need the SwiftUI rewriting (#if os, #available).
            if index.importsModules.contains(where: { !["Foundation", "Swift", "Dispatch", "FoundationEssentials", "FoundationNetworking",
                                                       "_Concurrency", "Synchronization", "RegexBuilder", "os", "Darwin", "Glibc", "XCTest"].contains($0) }) {
                return true
            }
        }
        return false
    }

    static func swiftVersionFlag(_ version: String?) -> String {
        guard let version else { return "5" }
        if version.hasPrefix("4.2") { return "4.2" }
        if version.hasPrefix("4") { return "4" }
        if let major = Int(version.split(separator: ".").first ?? ""), major >= 6 { return "6" }
        return "5"
    }

    func run(_ arguments: [String]) -> (status: Int32, output: String) {
        if verbose { note(([installation.swiftc] + arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }).joined(separator: " ")) }
        let result = swiftuiScreenshotRun(installation.swiftc, arguments)
        return (result.status, result.stderr + result.stdout)
    }

    /// Writes `sources` under `work/src`, mirroring their absolute paths so names never collide and
    /// diagnostics can be mapped back by removing the prefix.
    static func write(_ sources: [CompiledSource], into work: String) throws -> [String] {
        var written: [String] = []
        for source in sources {
            let path = work + "/src" + (source.path.hasPrefix("/") ? source.path : "/" + source.path)
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try source.contents.write(toFile: path, atomically: true, encoding: .utf8)
            written.append(path)
        }
        return written
    }

    static func mapDiagnostics(_ text: String, work: String) -> String {
        text.replacingOccurrences(of: work + "/src/", with: "/")
    }

    /// Rewrites the sources of a module compiled against the SDK (see Preprocessor). `entry` keeps its
    /// previews; every other file has them blanked out first.
    func rewrite(_ sources: [(path: String, contents: String)], entry: String?, viewExpression: String?) -> (files: [CompiledSource], main: String, entries: [String]) {
        let stripped = sources.map { source in (source.path, source.path == entry ? source.contents : PreviewStripper.strip(source.contents)) }
        var preprocessor = Preprocessor()
        preprocessor.platform = platform
        let output = preprocessor.process(stripped.map { (path: $0.0, contents: $0.1) }, viewExpression: viewExpression)
        var files: [CompiledSource] = []
        for (index, source) in sources.enumerated() { files.append(CompiledSource(path: source.path, contents: output.files[index].contents)) }
        return (files, output.files.last?.contents ?? "", output.entries)
    }

    struct LibraryPlan {
        var node: ModuleGraph.Node
        var sources: [(path: String, contents: String)]
        var generated: [CompiledSource]
        var resourceDirectory: String?
    }

    /// Compiles one library module (cached).
    func buildLibrary(_ plan: LibraryPlan, dependencies: [BuiltModule]) throws -> BuiltModule {
        let target = plan.node.target
        let sdk = needsSDK(plan.sources)
        let files: [CompiledSource] = sdk
            ? rewrite(plan.sources, entry: nil, viewExpression: nil).files
            : plan.sources.map { CompiledSource(path: $0.path, contents: $0.contents) }
        let all = files + plan.generated
        var flags = ["-swift-version", ModuleBuilder.swiftVersionFlag(target.swiftVersion)]
        for condition in target.compilationConditions { flags += ["-D", condition] }
        if let package = target.packageName { flags += ["-package-name", package.filter { $0.isLetter || $0.isNumber || $0 == "_" }] }
        let key = hash([target.moduleName, sdk ? "sdk" : "native"] + flags + all.flatMap { [$0.path, $0.contents] }
                       + dependencies.map(\.key) + environmentStamp + [plan.resourceDirectory ?? ""])
        let directory = ModuleBuilder.cacheRoot + "/modules/\(target.moduleName)-\(key)"
        let built = BuiltModule(name: target.moduleName, directory: directory, key: key, resourceDirectory: plan.resourceDirectory)
        let library = directory + "/lib\(target.moduleName).so"
        if !noCache, FileManager.default.fileExists(atPath: library), FileManager.default.fileExists(atPath: directory + "/\(target.moduleName).swiftmodule") {
            if verbose { note("module \(target.moduleName): cached") }
            return built
        }
        try? FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let written = try ModuleBuilder.write(all, into: directory)
        if verbose || all.count > 20 { note("compiling module \(target.moduleName) (\(files.count) files)\(sdk ? "" : ", Foundation only")") }
        var arguments = flags + ["-Onone", "-module-name", target.moduleName, "-parse-as-library", "-no-color-diagnostics",
                                 "-emit-library", "-emit-module", "-emit-module-path", directory + "/\(target.moduleName).swiftmodule",
                                 "-Xlinker", "-soname=lib\(target.moduleName).so", "-j\(ProcessInfo.processInfo.activeProcessorCount)"]
        arguments += linkArguments(dependencies, sdk: sdk)
        arguments += written + ["-o", library]
        let result = run(arguments)
        if result.status != 0 || !FileManager.default.fileExists(atPath: library) {
            try? FileManager.default.removeItem(atPath: directory)
            throw CompileFailure(module: target.moduleName, origin: plan.node.origin, diagnostics: ModuleBuilder.mapDiagnostics(result.output, work: directory))
        }
        return built
    }

    static let foundationShim = "SwiftUIScreenshotFoundation"

    /// Modules imported into every file compiled against the SDK (SWIFTUI_SCREENSHOT_IMPORTS, comma-separated):
    /// lets a stand-in module add members to SDK types while scouting a project.
    static var extraImports: [String] {
        (ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_IMPORTS"] ?? "").split(separator: ",").map(String.init)
    }

    static var extraModuleDirectories: [String] {
        (ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_MODULES"] ?? "").split(separator: ":").map(String.init)
            .filter { ProjectFiles.isDirectory($0) }
    }

    /// A directory holding only the Foundation shim module (String(localized:), LocalizedStringResource),
    /// for modules compiled without the SDK: they must not see SwiftUI (`#if canImport(SwiftUI)` stays
    /// false, as on Linux) but do need what Linux Foundation lacks.
    var foundationShimDirectory: String? {
        let fm = FileManager.default
        let module = installation.sdk + "/\(ModuleBuilder.foundationShim).swiftmodule"
        let library = installation.sdk + "/lib\(ModuleBuilder.foundationShim).so"
        guard fm.fileExists(atPath: module), fm.fileExists(atPath: library) else { return nil }
        let directory = ModuleBuilder.cacheRoot + "/foundation-shim-" + hash([installation.sdk, ModuleBuilder.stamp(library)])
        if !fm.fileExists(atPath: directory + "/lib\(ModuleBuilder.foundationShim).so") {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? fm.createSymbolicLink(atPath: directory + "/\(ModuleBuilder.foundationShim).swiftmodule", withDestinationPath: module)
            try? fm.createSymbolicLink(atPath: directory + "/lib\(ModuleBuilder.foundationShim).so", withDestinationPath: library)
        }
        return directory
    }

    /// Search paths and libraries for a module. Every module imports the Foundation shim implicitly.
    /// Compiles against the SDK link libSwiftUI, which also holds Combine and the shim frameworks (UIKit,
    /// MapKit, WidgetKit, ...), so a process has one copy of SwiftUI whatever it imports. CoreText and the
    /// Foundation shim are separate libraries without SwiftUI, autolinked by their modules.
    func linkArguments(_ dependencies: [BuiltModule], sdk: Bool) -> [String] {
        var arguments: [String] = []
        if sdk {
            arguments += installation.linkFlags
        } else if let shim = foundationShimDirectory {
            arguments += ["-I", shim, "-L", shim, "-l" + ModuleBuilder.foundationShim, "-Xlinker", "-rpath", "-Xlinker", installation.sdk]
        }
        if sdk {
            // Extra module directories (SWIFTUI_SCREENSHOT_MODULES, colon-separated): stand-ins for frameworks
            // the SDK lacks, each a `Name.swiftmodule` with an optional `libName.so`.
            for directory in ModuleBuilder.extraModuleDirectories {
                arguments += ["-I", directory, "-L", directory, "-Xlinker", "-rpath", "-Xlinker", directory]
                for file in ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
                where file.hasPrefix("lib") && file.hasSuffix(".so") {
                    arguments.append("-l" + file.dropFirst(3).dropLast(3))
                }
            }
            for module in ModuleBuilder.extraImports { arguments += ["-Xfrontend", "-import-module", "-Xfrontend", module] }
        }
        if sdk || foundationShimDirectory != nil {
            arguments += ["-Xfrontend", "-import-module", "-Xfrontend", ModuleBuilder.foundationShim]
        }
        for dependency in dependencies {
            arguments += ["-I", dependency.directory, "-L", dependency.directory, "-l" + dependency.name,
                          "-Xlinker", "-rpath", "-Xlinker", dependency.directory]
        }
        return arguments
    }

    struct RunnerPlan {
        var target: ProjectTarget
        var sources: [(path: String, contents: String)]
        var generated: [CompiledSource]
        var entry: String?
        var viewExpression: String?
        /// Files copied (linked) next to the runner, so `Bundle.main` finds them.
        var bundleResources: [String: String]
    }

    struct Runner {
        var path: String
        var entries: [String]
    }

    /// Compiles the entry target with its dependencies into a runner executable (cached).
    func buildRunner(_ plan: RunnerPlan, dependencies: [BuiltModule]) throws -> Runner {
        let target = plan.target
        let rewritten = rewrite(plan.sources, entry: plan.entry, viewExpression: plan.viewExpression)
        if rewritten.entries.isEmpty {
            throw ProjectError("nothing to render: no #Preview, PreviewProvider or @main App found. Pass --view \"YourView()\" to pick a view.")
        }
        // The entry expressions (`--view`, the App type) may name things from the target's dependencies.
        let imports = dependencies.map { "import \($0.name)\n" }.joined()
        let main = CompiledSource(path: "/__swiftui_screenshot__/main.swift", contents: imports + rewritten.main)
        let all = rewritten.files + plan.generated + [main]
        var flags = ["-swift-version", ModuleBuilder.swiftVersionFlag(target.swiftVersion)]
        for condition in target.compilationConditions { flags += ["-D", condition] }
        let resources = plan.bundleResources.sorted { $0.key < $1.key }
        let key = hash([target.moduleName, "runner"] + flags + all.flatMap { [$0.path, $0.contents] } + dependencies.map(\.key)
                       + environmentStamp + resources.flatMap { [$0.key, $0.value, ModuleBuilder.stamp($0.value)] })
        let directory = ModuleBuilder.cacheRoot + "/runners/\(target.moduleName)-\(key)"
        let runner = directory + "/runner"
        if !noCache, FileManager.default.isExecutableFile(atPath: runner) {
            if verbose { note("target \(target.name): cached") }
            return Runner(path: runner, entries: rewritten.entries)
        }
        try? FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let written = try ModuleBuilder.write(all, into: directory)
        for (name, source) in resources {
            let destination = directory + "/" + name
            try? FileManager.default.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: source)
        }
        var arguments = flags + ["-Onone", "-module-name", target.moduleName, "-no-color-diagnostics", "-j\(ProcessInfo.processInfo.activeProcessorCount)"]
        arguments += linkArguments(dependencies, sdk: true)
        arguments += written + ["-o", runner]
        let result = run(arguments)
        if result.status != 0 || !FileManager.default.isExecutableFile(atPath: runner) {
            try? FileManager.default.removeItem(atPath: directory)
            throw CompileFailure(module: target.moduleName, origin: "target \(target.name)", diagnostics: ModuleBuilder.mapDiagnostics(result.output, work: directory))
        }
        return Runner(path: runner, entries: rewritten.entries)
    }

    /// Which of `names` cannot be imported with the module's search paths: one probe compile of
    /// `#if !canImport(X)` checks, since the compiler itself reports only the first missing module.
    func missingModules(_ names: Set<String>, dependencies: [BuiltModule], sdk: Bool) -> Set<String> {
        guard !names.isEmpty else { return [] }
        let work = ModuleBuilder.cacheRoot + "/check/probe-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: work) }
        var probe = ""
        for name in names.sorted() { probe += "#if !canImport(\(name))\n#error(\"MISSING-MODULE \(name)\")\n#endif\n" }
        let file = work + "/probe.swift"
        guard (try? probe.write(toFile: file, atomically: true, encoding: .utf8)) != nil else { return [] }
        let saved = verbose
        var quiet = self
        quiet.verbose = false
        _ = saved
        let result = quiet.run(["-typecheck", "-parse-as-library", "-no-color-diagnostics"] + linkArguments(dependencies, sdk: sdk) + [file])
        var missing: Set<String> = []
        for line in result.output.split(separator: "\n") {
            if let range = line.range(of: "MISSING-MODULE ") { missing.insert(String(line[range.upperBound...].prefix { $0 != "\"" && $0 != " " })) }
        }
        return missing.intersection(names)
    }

    /// Type-checks a module without producing anything (for `check`).
    func typecheck(_ target: ProjectTarget, sources: [(path: String, contents: String)], generated: [CompiledSource],
                   dependencies: [BuiltModule], stubs: String?, keepPreviews: String?) -> (status: Int32, diagnostics: String) {
        let sdk = needsSDK(sources)
        let files = sdk ? rewrite(sources, entry: keepPreviews, viewExpression: nil).files : sources.map { CompiledSource(path: $0.path, contents: $0.contents) }
        let work = ModuleBuilder.cacheRoot + "/check/\(target.moduleName)-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.removeItem(atPath: work)
        defer { try? FileManager.default.removeItem(atPath: work) }
        guard let written = try? ModuleBuilder.write(files + generated, into: work) else { return (1, "cannot write to \(work)") }
        var arguments = ["-swift-version", ModuleBuilder.swiftVersionFlag(target.swiftVersion), "-typecheck", "-module-name", target.moduleName,
                         "-parse-as-library", "-no-color-diagnostics", "-continue-building-after-errors", "-j\(ProcessInfo.processInfo.activeProcessorCount)"]
        if let package = target.packageName { arguments += ["-package-name", package.filter { $0.isLetter || $0.isNumber || $0 == "_" }] }
        for condition in target.compilationConditions { arguments += ["-D", condition] }
        arguments += linkArguments(dependencies, sdk: sdk)
        if let stubs { arguments += ["-I", stubs] }
        let result = run(arguments + written)
        return (result.status, ModuleBuilder.mapDiagnostics(result.output, work: work))
    }
}

/// `run` from Tool.swift, under a name that cannot clash with members called `run`.
func swiftuiScreenshotRun(_ executable: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
    run(executable, arguments)
}
