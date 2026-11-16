import Foundation

// Project mode, end to end: finds the project and target that own the entry file, builds the module
// graph, compiles the entry's dependency closure into a runner, and hands the renderer the target's
// resources. Tool.swift calls in at three points: `takeFlags` (before option parsing), `prepare`
// (after it), and `build` (instead of the single-module build).

struct ProjectFlags {
    var project: String?
    var target: String?
    var disabled = false
    var wholeTarget = false
    var locale: String?
    var explicit: Bool { project != nil || target != nil }
}

/// What a project-mode command resolved to.
struct ProjectContext {
    var project: Project
    var target: ProjectTarget
    var entry: String?
    var graph: ModuleGraph
}

enum ProjectSession {
    static var flags = ProjectFlags()
    /// Set when the current command runs in project mode; `build` then returns `built`.
    static var current: ProjectContext?
    static var built: Build?

    static let usage = """
    Project mode (a file inside an XcodeGen, Xcode or Swift package project):
          --project <path>   project.yml, X.xcodeproj, Package.swift, or a directory holding one (default: found from the file)
          --target <name>    Target to build (default: the target that compiles the file)
          --no-project       Compile only the given files, as for a loose file
          --whole-target     Compile every file of the target instead of the files the entry needs
          --locale <id>      Language for string catalogs and .strings (default: the project's development language),
                             and the device's region and formats (see render --help)
      swiftui-screenshot check <file | --target Name> [--json]   Compile without rendering; summarize what is unsupported
    """

    /// Removes the project-mode flags from `arguments` (they are not known to the option parser).
    static func takeFlags(_ arguments: [String]) -> [String] {
        var rest: [String] = []
        var args = arguments[...]
        func value(_ flag: String) -> String {
            guard let v = args.popFirst() else { fail("\(flag) needs a value") }
            return v
        }
        while let arg = args.popFirst() {
            switch arg {
            case "--project": flags.project = value(arg)
            case "--target": flags.target = value(arg)
            case "--no-project": flags.disabled = true
            case "--whole-target": flags.wholeTarget = true
            case "--locale":
                // Also the device's formatting locale: the render options see it too.
                flags.locale = value(arg)
                rest += [arg, flags.locale!]
            default: rest.append(arg)
            }
        }
        return rest
    }

    static func absolute(_ path: String) -> String {
        ProjectFiles.absolute(path, relativeTo: FileManager.default.currentDirectoryPath)
    }

    /// Finds the project, target and module graph for the inputs, or nil when they are not part of a project.
    static func resolve(_ options: Options) -> ProjectContext? {
        guard !flags.disabled else { return nil }
        var entry: String?
        if options.inputs.count == 1, !ProjectFiles.isDirectory(options.inputs[0]) {
            entry = absolute(options.inputs[0])
            guard FileManager.default.fileExists(atPath: entry!) else { fail("no such file: \(options.inputs[0])") }
        } else if !options.inputs.isEmpty {
            // Several files or a directory: the loose-files mode, unless a project was asked for.
            guard flags.explicit else { return nil }
            fail("in project mode pass one entry file (or none, with --target)")
        } else if !flags.explicit {
            return nil
        }

        var notes: [String] = []
        var project: Project?
        if let path = flags.project {
            let path = absolute(path)
            var candidates: [(Project.Format, String)] = []
            if ProjectFiles.isDirectory(path), !path.hasSuffix(".xcodeproj") { candidates = ProjectLocator.descriptions(in: path) }
            else if path.hasSuffix(".xcodeproj") { candidates = [(.xcodeproj, path)] }
            else if path.hasSuffix("Package.swift") { candidates = [(.swiftpm, path)] }
            else { candidates = [(.xcodegen, path)] }
            guard let first = candidates.first else { fail("no project.yml, .xcodeproj or Package.swift in \(path)") }
            do { project = try ProjectLocator.load(first.0, first.1) } catch { fail("cannot read \(first.1): \(error)") }
        } else if let entry {
            project = ProjectLocator.find(owning: entry, notes: &notes)
        } else if let nearest = ProjectLocator.nearest(from: FileManager.default.currentDirectoryPath) {
            do { project = try ProjectLocator.load(nearest.0, nearest.1) } catch { fail("cannot read \(nearest.1): \(error)") }
        }
        guard let project else {
            if flags.explicit { fail("no project found" + (notes.isEmpty ? "" : ":\n  " + notes.joined(separator: "\n  "))) }
            if options.verbose { for n in notes { note("note: \(n)") }; note("not part of a project: compiling the file on its own") }
            return nil
        }
        if options.verbose { for n in project.notes { note("note: \(n)") } }

        var target: ProjectTarget
        if let name = flags.target {
            guard let named = project.target(named: name) else {
                fail("no target \(name) in \(project.path). Targets: " + project.targets.map(\.name).joined(separator: ", "))
            }
            if let entry, !named.sources.contains(entry) {
                let owners = project.owners(of: entry).map(\.name)
                fail("target \(name) does not compile \((entry as NSString).lastPathComponent)" + (owners.isEmpty ? "" : "; it is in: " + owners.joined(separator: ", ")))
            }
            target = named
        } else if let entry {
            let owners = project.owners(of: entry)
            guard let first = owners.first else {
                if flags.explicit { fail("no target of \(project.path) compiles \(entry)") }
                return nil
            }
            target = first
            if owners.count > 1, options.verbose || !options.json {
                note("note: \((entry as NSString).lastPathComponent) is in \(owners.map(\.name).joined(separator: ", ")); using \(first.name) (choose with --target)")
            }
        } else {
            let apps = project.targets.filter { $0.kind == "application" }
            fail("pass an entry file or --target. Targets: " + (apps.isEmpty ? project.targets : apps).map(\.name).joined(separator: ", "))
        }
        if let reason = target.unsupportedReason { fail("target \(target.name) cannot be rendered: \(reason)") }
        let graph = ModuleGraph.resolve(target, in: project)
        if options.verbose {
            note("project: \(project.path) (\(project.format.rawValue)), target \(target.name) (\(target.kind), \(target.platform ?? "?")\(target.deploymentTarget.map { " " + $0 } ?? ""))")
            note("modules: " + graph.nodes.map { "\($0.target.moduleName) [\($0.origin)]" }.joined(separator: ", "))
            for n in graph.notes { note("note: \(n)") }
        }
        for missing in graph.unsupported { note("warning: \(missing) cannot be built here; continuing without it") }
        return ProjectContext(project: project, target: target, entry: entry, graph: graph)
    }

    /// Applies the target's platform unless `--platform`/`--device` chose one.
    static func applyPlatform(_ target: ProjectTarget, to options: inout Options) {
        guard !options.platformWasSet, let platform = target.platform, ["iOS", "tvOS", "watchOS", "macOS", "visionOS"].contains(platform) else { return }
        // A --device already implied a platform in parse(); keep that one.
        if options.runnerArguments.contains("--device") { return }
        options.platform = platform
        if let index = options.runnerArguments.lastIndex(of: "--platform"), index + 1 < options.runnerArguments.count {
            options.runnerArguments[index + 1] = platform
        }
        if platform == "macOS" || platform == "visionOS" {
            note("warning: \(platform) has no device profile yet; the screen is drawn at iPhone size with iOS chrome")
        }
    }

    /// Called after option parsing for `render` and `list`. In project mode it builds everything and
    /// returns the options with the renderer's resource flags added.
    static func prepare(_ options: Options, command: String) -> Options {
        guard let context = resolve(options) else { return options }
        var options = options
        applyPlatform(context.target, to: &options)
        if command == "list" { listPreviews(context); exit(0) }
        current = context
        if options.inputs.isEmpty { options.inputs = [context.target.name] }
        let installation = Installation.locate()
        guard !installation.swiftc.isEmpty else { fail("swiftc not found. Install a Swift 6 toolchain and put it on PATH, or set SWIFTC.") }
        do {
            let result = try ProjectBuild(context: context, options: options, installation: installation).run()
            built = result.build
            options.runnerArguments += result.runnerArguments
        } catch let failure as CompileFailure {
            reportFailure(failure, context: context, json: options.json)
            exit(1)
        } catch {
            fail("\(error)")
        }
        return options
    }

    static func reportFailure(_ failure: CompileFailure, context: ProjectContext, json: Bool) {
        FileHandle.standardError.write(Data(failure.diagnostics.utf8))
        let report = failure.report ?? UnsupportedReport(diagnostics: failure.diagnostics, stubbedModules: [:])
        note("")
        note("error: \(failure.origin) (module \(failure.module)) did not compile against this renderer. Nothing was rendered.")
        if !report.isEmpty { note(report.text()) }
        if let mismatch = compilerMismatch(Installation.locate()) { note("error: " + mismatch) }
    }

    /// `build` in project mode: everything was built in `prepare`.
    static func build(_ options: Options, _ installation: Installation) -> Build {
        guard let built else { fail("internal error: project build missing") }
        return built
    }

    /// `list` in project mode: the previews of every file of the target, found in the sources.
    static func listPreviews(_ context: ProjectContext) {
        for file in context.target.sources {
            guard let data = FileManager.default.contents(atPath: file) else { continue }
            let names = previewNames(String(decoding: data, as: UTF8.self))
            let display = file.hasPrefix(context.project.root + "/") ? String(file.dropFirst(context.project.root.count + 1)) : file
            for (index, name) in names.enumerated() { print("\(display)\t\(index)\t\(name.isEmpty ? "(unnamed)" : name)") }
        }
    }

    /// Names of the `#Preview`s and `PreviewProvider`s of a file, in the order the runner numbers them.
    static func previewNames(_ source: String) -> [String] {
        let bytes = Array(source.utf8)
        let tokens = SwiftLexer.tokens(bytes)
        var names: [String] = []
        for (k, t) in tokens.enumerated() where t.kind == .pound && t.text == "Preview" {
            var name = ""
            if k + 2 < tokens.count, tokens[k + 1].text == "(", tokens[k + 2].kind == .string {
                let literal = String(decoding: bytes[tokens[k + 2].start..<tokens[k + 2].end], as: UTF8.self)
                name = String(literal.dropFirst().dropLast())
            }
            names.append(name)
        }
        if let regex = try? NSRegularExpression(pattern: #"struct\s+(\w+)\s*:\s*[^{]*\bPreviewProvider\b"#) {
            let ns = source as NSString
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) { names.append(ns.substring(with: match.range(at: 1))) }
        }
        return names
    }
}

/// One project-mode build: dependency modules, the entry closure, resources.
struct ProjectBuild {
    var context: ProjectContext
    var options: Options
    var installation: Installation

    struct Result {
        var build: Build
        var runnerArguments: [String]
    }

    func read(_ path: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else { throw ProjectError("cannot read \(path)") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Generated files for a module: `Bundle.module` and asset symbols.
    func generatedFiles(_ target: ProjectTarget, stage: String?, isPackage: Bool, sdk: Bool, sources: [(path: String, contents: String)]) -> [CompiledSource] {
        var files: [CompiledSource] = []
        if target.name == context.target.name {
            // SWIFTUI_SCREENSHOT_EXTRA_SOURCES (colon-separated .swift files): compiled into the entry target.
            // A scouting aid: stand-ins for something the target needs and the SDK lacks.
            for path in (ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_EXTRA_SOURCES"] ?? "").split(separator: ":").map(String.init) {
                if let text = try? read(path) { files.append(CompiledSource(path: path, contents: text)) }
            }
        }
        if isPackage, let stage { files.append(CompiledSource(path: "/__swiftui_screenshot__/\(target.moduleName)/resource_bundle_accessor.swift", contents: ProjectResources.bundleAccessor(stage))) }
        let catalogs = ProjectResources.assetCatalogs(target.resources)
        if sdk, !catalogs.isEmpty {
            var declared: Set<String> = []
            for source in sources {
                for ext in SwiftIndexer.index(Array(source.contents.utf8)).extensions { declared.formUnion(ext.members) }
            }
            if let symbols = ProjectResources.assetSymbols(catalogs, bundle: isPackage && stage != nil ? "Bundle.module" : "Bundle.main", declared: declared) {
                files.append(CompiledSource(path: "/__swiftui_screenshot__/\(target.moduleName)/GeneratedAssetSymbols.swift", contents: symbols))
            }
        }
        return files
    }

    func run() throws -> Result {
        var builder = ModuleBuilder(installation: installation, platform: options.platform)
        builder.verbose = options.verbose
        builder.noCache = options.noCache
        var runnerArguments: [String] = []
        var allResources: [Resource] = []
        var fontDirectories: [String] = []
        var assetDirectories: [String] = []

        func addResources(_ target: ProjectTarget, stage: String?) {
            allResources += target.resources
            if let stage, ProjectResources.containsFonts(target.resources) { fontDirectories.append(stage) }
            assetDirectories += ProjectResources.assetCatalogs(target.resources)
            if let stage, ProjectResources.hasLooseImages(target.resources) { assetDirectories.append(stage) }
        }

        // Dependencies, in order.
        var built: [String: BuiltModule] = [:]
        for node in context.graph.nodes.dropLast() {
            let target = node.target
            var sources: [(path: String, contents: String)] = []
            for path in target.sources { sources.append((path, try read(path))) }
            let stage = ProjectResources.stage(target.resources, module: target.moduleName)
            addResources(target, stage: stage)
            var flagged = target
            if !flagged.compilationConditions.contains("DEBUG") { flagged.compilationConditions.insert("DEBUG", at: 0) }
            var plannedNode = node
            plannedNode.target = flagged
            let sdk = builder.needsSDK(sources)
            let generated = generatedFiles(target, stage: stage, isPackage: target.kind == "package-target", sdk: sdk, sources: sources)
            let plan = ModuleBuilder.LibraryPlan(node: plannedNode, sources: sources, generated: generated, resourceDirectory: stage)
            do {
                built[target.moduleName] = try builder.buildLibrary(plan, dependencies: transitiveDependencies(node, built))
            } catch var failure as CompileFailure {
                if failure.diagnostics.contains("no such module") {
                    failure.report = CheckCommand.typecheck(builder, flagged, sources, generated, transitiveDependencies(node, built), entry: nil).1
                }
                throw failure
            }
        }

        // The entry target: its closure.
        let node = context.graph.entry
        var target = node.target
        if target.kind == "package-target", !target.compilationConditions.contains("DEBUG") { target.compilationConditions.insert("DEBUG", at: 0) }
        var sources: [(path: String, contents: String)] = []
        for path in target.sources { sources.append((path, try read(path))) }
        let selected = closure(sources)
        let stage = ProjectResources.stage(target.resources, module: target.moduleName)
        addResources(target, stage: stage)
        let generated = generatedFiles(target, stage: stage, isPackage: target.kind == "package-target", sdk: true, sources: selected)
        var bundle: [String: String] = [:]
        if target.kind != "package-target" { bundle = ProjectResources.bundleLayout(target.resources) }
        let plan = ModuleBuilder.RunnerPlan(target: target, sources: selected, generated: generated, entry: context.entry,
                                            viewExpression: options.view, bundleResources: bundle)
        let runner: ModuleBuilder.Runner
        do {
            runner = try builder.buildRunner(plan, dependencies: transitiveDependencies(node, built))
        } catch var failure as CompileFailure {
            if failure.diagnostics.contains("no such module") {
                failure.report = CheckCommand.typecheck(builder, target, selected, generated, transitiveDependencies(node, built), entry: context.entry).1
            }
            throw failure
        }

        // Strings for the chosen locale.
        let language = ProjectSession.flags.locale ?? target.developmentLanguage ?? context.project.developmentLanguage ?? "en"
        let available = ProjectResources.languages(allResources)
        if let wanted = ProjectSession.flags.locale, !available.isEmpty,
           !ProjectResources.localeCandidates(wanted).contains(where: { c in available.contains { $0.lowercased() == c.lowercased() } }) {
            note("warning: no strings for locale \(wanted); available: \(available.sorted().joined(separator: ", "))")
        }
        let table = ProjectResources.table(allResources, locale: language)
        if !table.isEmpty, let data = try? JSONSerialization.data(withJSONObject: table, options: [.sortedKeys]) {
            let path = (runner.path as NSString).deletingLastPathComponent + "/strings-\(language).json"
            try? data.write(to: URL(fileURLWithPath: path))
            setenv("SWIFTUI_SCREENSHOT_STRINGS", path, 1)
        }
        setenv("SWIFTUI_SCREENSHOT_LOCALE", language, 1)
        for dir in fontDirectories { runnerArguments += ["--fonts", dir] }
        var seen: Set<String> = []
        for dir in assetDirectories where seen.insert(dir).inserted { runnerArguments += ["--assets", dir] }
        if options.verbose {
            note("resources: \(fontDirectories.count) font folder(s), \(seen.count) asset folder(s), \(table.count) strings (\(language))")
        }

        // Previews, as Tool.build does.
        let listing = swiftuiScreenshotRun(runner.path, ["--list"])
        guard listing.status == 0 else { fail("runner failed to list previews:\n\(listing.stderr)") }
        let previews: [(index: Int, name: String)] = listing.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let index = Int(parts[0]) else { return nil }
            return (index, parts.count > 1 ? String(parts[1]) : "")
        }
        return Result(build: Build(runner: runner.path, previews: previews), runnerArguments: runnerArguments)
    }

    /// Modules visible to `node`: its dependencies and theirs (a dynamic library's dependencies must be
    /// on the search path for its module to load).
    func transitiveDependencies(_ node: ModuleGraph.Node, _ built: [String: BuiltModule]) -> [BuiltModule] {
        var result: [BuiltModule] = []
        var seen: Set<String> = []
        func visit(_ name: String) {
            guard seen.insert(name).inserted, let module = built[name] else { return }
            if let dependencyNode = context.graph.nodes.first(where: { $0.target.moduleName == name }) {
                for dependency in dependencyNode.dependencies { visit(dependency) }
            }
            result.append(module)
        }
        for dependency in node.dependencies { visit(dependency) }
        return result
    }

    /// The entry file and what it needs (or every file with `--whole-target`). Without an entry file
    /// (`--target Name`) the roots are the `--view` expression or the target's `@main App`; `check`
    /// compiles the whole target in that case (`wholeWithoutEntry`).
    func closure(_ sources: [(path: String, contents: String)], wholeWithoutEntry: Bool = false) -> [(path: String, contents: String)] {
        if ProjectSession.flags.wholeTarget || (context.entry == nil && wholeWithoutEntry) { return sources }
        let entry = context.entry
        var indexes = sources.map { source in
            (path: source.path, index: SwiftIndexer.index(Array((source.path == entry ? source.contents : PreviewStripper.strip(source.contents)).utf8)))
        }
        var roots = entry.map { [$0] } ?? []
        var extra: Set<String> = []
        let entryHasPreviews = entry.map { path in
            (indexes.first { $0.path == path }?.index.hasPreviews ?? false) || sources.contains { $0.path == path && $0.contents.contains("PreviewProvider") }
        } ?? false
        if let view = options.view {
            for token in SwiftLexer.tokens(Array(view.utf8)) where token.kind == .identifier { extra.insert(token.text) }
        } else if !entryHasPreviews {
            // No previews to render: the app's first window is rendered, so its App type is a root.
            if let app = sources.first(where: { $0.contents.range(of: #"struct\s+\w+\s*:\s*(?:[^{\n]*,\s*)?(?:SwiftUI\.)?App\b"#, options: .regularExpression) != nil }) {
                roots.append(app.path)
                if let entry, entry != app.path {
                    note("note: \((entry as NSString).lastPathComponent) has no previews; rendering the app's first window (\((app.path as NSString).lastPathComponent)). Pass --view to pick a view.")
                }
            } else if entry == nil {
                return sources
            }
        }
        // Rendering a preview or --view: the @main App type is not needed, and its body would pull in the
        // whole app through the file it shares with other declarations.
        var sources = sources
        if options.view != nil || entryHasPreviews {
            for i in sources.indices where sources[i].path != entry && sources[i].contents.contains("@main") {
                let stripped = PreviewStripper.stripMainApp(sources[i].contents)
                if stripped != sources[i].contents {
                    sources[i].contents = stripped
                    indexes[i] = (path: sources[i].path, index: SwiftIndexer.index(Array(PreviewStripper.strip(stripped).utf8)))
                }
            }
        }
        let result = DependencyClosure.compute(roots: roots, extraReferences: extra, indexes: indexes)
        if options.verbose {
            note("compiling \(result.files.count) of \(sources.count) files of \(context.target.name)")
            for file in result.files where file != entry { note("  \((file as NSString).lastPathComponent): \(result.reasons[file] ?? "")") }
        }
        let keep = Set(result.files)
        return sources.filter { keep.contains($0.path) }
    }
}
