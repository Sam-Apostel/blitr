import Foundation

// `swiftui-screenshot check`: compile without rendering and summarize what is unsupported, grouped and
// counted, instead of a wall of compiler errors. The same summary follows a failed render.

struct Diagnostic: Hashable {
    var file: String
    var line: Int
    var column: Int
    var severity: String
    var message: String
}

struct UnsupportedReport {
    struct Group {
        var uses = 0
        var files: Set<String> = []
        var symbols: [String: Int] = [:]
    }
    var diagnostics: [Diagnostic] = []
    /// Missing modules: name -> files importing it, and the unknown names used in those files.
    var frameworks: [String: Group] = [:]
    /// `Type.member(labels:)` -> uses.
    var members: [String: Group] = [:]
    /// Names the compiler could not find that no missing framework explains.
    var unknownNames: [String: Group] = [:]
    /// Calls whose arguments do not match any overload.
    var calls: [String: Group] = [:]
    /// Everything else, by message with the specifics replaced.
    var other: [String: Group] = [:]

    var errorCount: Int { diagnostics.filter { $0.severity == "error" }.count }
    var isEmpty: Bool { errorCount == 0 }

    static let pattern = try! NSRegularExpression(pattern: #"^([^:\n ][^:\n]*\.swift):(\d+):(\d+): (error|warning|note): (.*)$"#, options: [.anchorsMatchLines])

    static func parse(_ text: String) -> [Diagnostic] {
        let ns = text as NSString
        var seen: Set<Diagnostic> = []
        var result: [Diagnostic] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let d = Diagnostic(file: ns.substring(with: match.range(at: 1)), line: Int(ns.substring(with: match.range(at: 2))) ?? 0,
                               column: Int(ns.substring(with: match.range(at: 3))) ?? 0, severity: ns.substring(with: match.range(at: 4)),
                               message: ns.substring(with: match.range(at: 5)))
            if seen.insert(d).inserted { result.append(d) }
        }
        return result
    }

    /// Framework a symbol most likely comes from, by Apple's prefixes.
    static let prefixes: [(String, String)] = [
        ("MK", "MapKit"), ("CL", "CoreLocation"), ("WK", "WatchKit"), ("Widget", "WidgetKit"), ("Timeline", "WidgetKit"),
        ("Activity", "ActivityKit"), ("AppIntent", "AppIntents"), ("Intent", "AppIntents"), ("AppShortcut", "AppIntents"),
        ("AppEntity", "AppIntents"), ("AppEnum", "AppIntents"), ("PH", "Photos"), ("Photos", "PhotosUI"), ("UN", "UserNotifications"),
        ("EK", "EventKit"), ("CI", "CoreImage"), ("WC", "WatchConnectivity"), ("AS", "AuthenticationServices"), ("PK", "PassKit"),
        ("CS", "CoreSpotlight"), ("Tip", "TipKit"), ("UT", "UniformTypeIdentifiers"), ("AV", "AVFoundation"), ("SF", "SafariServices"),
        ("CG", "CoreGraphics"), ("CT", "CoreText"), ("CA", "QuartzCore"), ("VN", "Vision"), ("PDF", "PDFKit"), ("QL", "QuickLook"),
        ("NW", "Network"), ("CN", "Contacts"), ("UI", "UIKit"), ("NS", "AppKit"), ("Map", "MapKit"), ("Translation", "Translation"),
        ("DataScanner", "VisionKit"), ("Chart", "Charts"), ("SK", "StoreKit"), ("Product", "StoreKit"), ("LookAround", "MapKit"),
    ]

    /// `stubbedModules`: missing modules that were replaced by empty stand-ins to see further, with the files importing each.
    init(diagnostics text: String, stubbedModules: [String: Set<String>]) {
        diagnostics = UnsupportedReport.parse(text)
        var importsCache: [String: Set<String>] = [:]
        func imports(_ file: String) -> Set<String> {
            if let cached = importsCache[file] { return cached }
            let modules = FileManager.default.contents(atPath: file).map { SwiftIndexer.index(Array($0)).importsModules } ?? []
            importsCache[file] = modules
            return modules
        }
        var missing = Set(stubbedModules.keys)
        for d in diagnostics where d.severity == "error" {
            if let name = UnsupportedReport.quoted(d.message, after: "no such module ") { missing.insert(name) }
        }
        for module in missing { frameworks[module] = Group(files: stubbedModules[module] ?? []) }
        for d in diagnostics where d.severity == "error" {
            let m = d.message
            if let name = UnsupportedReport.quoted(m, after: "no such module ") {
                frameworks[name, default: Group()].files.insert(d.file)
                continue
            }
            // A stubbed module referred to by name: `SunCalc.daylightHours`.
            if let module = UnsupportedReport.quoted(m, after: "module "), missing.contains(module), let range = m.range(of: "has no member named '") {
                let name = String(m[range.upperBound...].prefix { $0 != "'" })
                frameworks[module, default: Group()].files.insert(d.file)
                frameworks[module]!.symbols[name, default: 0] += 1
                frameworks[module]!.uses += 1
                continue
            }
            if let name = UnsupportedReport.quoted(m, after: "cannot find type ") ?? UnsupportedReport.quoted(m, after: "cannot find ") {
                let fileMissing = imports(d.file).intersection(missing)
                var framework: String?
                if fileMissing.count == 1 { framework = fileMissing.first }
                else if let guess = UnsupportedReport.prefixes.first(where: { name.hasPrefix($0.0) && (fileMissing.isEmpty || fileMissing.contains($0.1)) })?.1,
                        missing.contains(guess) || fileMissing.isEmpty == false {
                    framework = guess
                } else if let first = fileMissing.sorted().first { framework = first }
                if let framework {
                    frameworks[framework, default: Group()].files.insert(d.file)
                    frameworks[framework]!.symbols[name, default: 0] += 1
                    frameworks[framework]!.uses += 1
                } else {
                    unknownNames[name, default: Group()].uses += 1
                    unknownNames[name]!.files.insert(d.file)
                }
                continue
            }
            if let (type, member) = UnsupportedReport.memberError(m) {
                let label = UnsupportedReport.memberLabel(member, d)
                let key = UnsupportedReport.normalizeType(type) + "." + label
                members[key, default: Group()].uses += 1
                members[key]!.files.insert(d.file)
                continue
            }
            if let member = UnsupportedReport.quoted(m, after: "cannot infer contextual base in reference to member ") {
                // Usually the argument of a missing API, so it is listed on its own.
                let key = "." + member + " (implicit member, type unknown)"
                members[key, default: Group()].uses += 1
                members[key]!.files.insert(d.file)
                continue
            }
            if m.hasPrefix("no exact matches in call to") || m.hasPrefix("extra argument") || m.hasPrefix("incorrect argument label")
                || m.hasPrefix("missing argument") || m.hasPrefix("argument passed to call that takes no arguments") || m.hasPrefix("extra arguments")
                || m.hasPrefix("missing arguments") || m.hasPrefix("no exact matches in reference") {
                let callee = UnsupportedReport.callee(at: d) ?? "?"
                let key = callee + " — " + m
                calls[key, default: Group()].uses += 1
                calls[key]!.files.insert(d.file)
                continue
            }
            if m.hasPrefix("cannot convert value of type") || m.hasPrefix("argument type") || m.hasPrefix("instance method") || m.hasPrefix("initializer")
                || m.hasPrefix("generic parameter") || m.hasPrefix("referencing") || m.hasPrefix("static method") {
                let key = (UnsupportedReport.callee(at: d) ?? "?") + " — " + m
                calls[key, default: Group()].uses += 1
                calls[key]!.files.insert(d.file)
                continue
            }
            let key = UnsupportedReport.genericMessage(m)
            other[key, default: Group()].uses += 1
            other[key]!.files.insert(d.file)
        }
    }

    static func quoted(_ message: String, after prefix: String) -> String? {
        guard message.hasPrefix(prefix) else { return nil }
        let rest = message.dropFirst(prefix.count)
        guard rest.first == "'", let end = rest.dropFirst().firstIndex(of: "'") else { return nil }
        return String(rest[rest.index(after: rest.startIndex)..<end])
    }

    /// `value of type 'T' has no member 'm'`, `type 'T' has no member 'm'`, `reference to member 'm' cannot be resolved without a contextual type`.
    static func memberError(_ m: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(?:value of type|type|static member '[^']*' cannot be used on instance of type) '(.+)' has no member '([^']+)'"#),
              let match = regex.firstMatch(in: m, range: NSRange(location: 0, length: (m as NSString).length)) else {
            if let regex = try? NSRegularExpression(pattern: #"^type '(.+)' has no member '([^']+)'"#),
               let match = regex.firstMatch(in: m, range: NSRange(location: 0, length: (m as NSString).length)) {
                return ((m as NSString).substring(with: match.range(at: 1)), (m as NSString).substring(with: match.range(at: 2)))
            }
            return nil
        }
        return ((m as NSString).substring(with: match.range(at: 1)), (m as NSString).substring(with: match.range(at: 2)))
    }

    /// Modifier chains print as `ModifiedContent<...>` or `some View`; group them as View.
    static func normalizeType(_ type: String) -> String {
        var t = type
        if t.hasPrefix("any ") { t.removeFirst(4) }
        if t.hasPrefix("some ") { t.removeFirst(5) }
        if t.hasPrefix("ModifiedContent<") || t.hasPrefix("_ConditionalContent<") || t.hasPrefix("TupleView<") || t.hasSuffix(".Body") { return "View" }
        if let generic = t.firstIndex(of: "<") { t = String(t[..<generic]) }
        if t.hasSuffix(".Type") { t.removeLast(5) }
        return t
    }

    static var sourceCache: [String: [String]] = [:]
    static func sourceLines(_ file: String) -> [String] {
        if let cached = sourceCache[file] { return cached }
        let lines = (FileManager.default.contents(atPath: file).map { String(decoding: $0, as: UTF8.self) } ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        sourceCache[file] = lines
        return lines
    }

    /// The source from the diagnostic's position on, a few lines' worth.
    static func text(at d: Diagnostic) -> (line: [Character], rest: String)? {
        let lines = sourceLines(d.file)
        guard d.line >= 1, d.line <= lines.count else { return nil }
        let line = Array(lines[d.line - 1].utf8)
        let offset = min(max(d.column - 1, 0), line.count)
        let prefix = String(decoding: line[..<offset], as: UTF8.self)
        let rest = String(decoding: line[offset...], as: UTF8.self) + "\n" + lines[d.line..<min(lines.count, d.line + 8)].joined(separator: "\n")
        return (Array(prefix), rest)
    }

    /// Argument labels of the call starting at `text` (just after the name): `(a: 1, b)` -> "a:_:"; nil if not a call.
    static func labels(_ text: Substring) -> String? {
        var chars = text.drop(while: { $0 == " " })
        let trailing = chars.first == "{"
        guard chars.first == "(" else { return trailing ? "_:" : nil }
        chars = chars.dropFirst()
        var depth = 0
        var current = ""
        var labels: [String] = []
        var quote = false
        for c in chars {
            if quote { if c == "\"" { quote = false }; continue }
            if c == "\"" { quote = true; continue }
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            if c == ")" || c == "]" || c == "}" {
                if depth == 0 { if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { labels.append(label(current)) }; break }
                depth -= 1
            }
            if c == ",", depth == 0 { labels.append(label(current)); current = ""; continue }
            current.append(c)
        }
        return labels.map { $0 + ":" }.joined()
    }

    static func label(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.firstIndex(of: ":") {
            let name = trimmed[..<colon]
            if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { return String(name) }
        }
        return "_"
    }

    /// `member(labels:)` read from the source at the diagnostic.
    static func memberLabel(_ member: String, _ d: Diagnostic) -> String {
        guard let (_, rest) = text(at: d), rest.hasPrefix(member) else { return member }
        if let labels = labels(rest.dropFirst(member.count)) { return member + "(" + labels + ")" }
        return member
    }

    /// The function being called around a call-mismatch diagnostic: the name before the innermost open `(`.
    static func callee(at d: Diagnostic) -> String? {
        guard let (linePrefix, rest) = text(at: d) else { return nil }
        // The diagnostic may point at the callee itself.
        let restChars = Array(rest)
        var k = 0
        while k < restChars.count, restChars[k].isLetter || restChars[k].isNumber || restChars[k] == "_" { k += 1 }
        if k > 0, k < restChars.count, restChars[k] == "(" {
            let name = String(restChars[0..<k])
            return (linePrefix.last == "." ? "." : "") + name + "(" + (labels(Substring(rest.dropFirst(k))) ?? "") + ")"
        }
        // The call may have started on an earlier line: prepend up to eight of them.
        let lines = sourceLines(d.file)
        var prefix = linePrefix
        if d.line >= 2 {
            let earlier = lines[max(0, d.line - 9)..<(d.line - 1)].joined(separator: "\n")
            prefix = Array(earlier + "\n") + prefix
        }
        var depth = 0
        var i = prefix.count - 1
        while i >= 0 {
            let c = prefix[i]
            if c == ")" { depth += 1 } else if c == "(" {
                if depth == 0 {
                    var j = i - 1
                    while j >= 0, prefix[j].isLetter || prefix[j].isNumber || prefix[j] == "_" { j -= 1 }
                    let name = String(prefix[(j + 1)..<i])
                    guard !name.isEmpty else { return nil }
                    let callText = String(prefix[i...]) + rest
                    return (j >= 0 && prefix[j] == "." ? "." : "") + name + "(" + (labels(Substring(callText)) ?? "") + ")"
                }
                depth -= 1
            }
            i -= 1
        }
        return nil
    }

    static func genericMessage(_ m: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "'[^']*'") else { return m }
        return regex.stringByReplacingMatches(in: m, range: NSRange(location: 0, length: (m as NSString).length), withTemplate: "'…'")
    }

    func sorted(_ groups: [String: Group]) -> [(String, Group)] {
        groups.sorted { ($0.value.uses, $0.value.files.count, $1.key) > ($1.value.uses, $1.value.files.count, $0.key) }
    }

    func text(root: String? = nil) -> String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var lines = ["Unsupported, from \(count(errorCount, "error")) in \(count(Set(diagnostics.filter { $0.severity == "error" }.map(\.file)).count, "file")):"]
        if !frameworks.isEmpty {
            lines.append("  Frameworks not available on Linux:")
            for (name, group) in frameworks.sorted(by: { ($0.value.files.count, $1.key) > ($1.value.files.count, $0.key) }) {
                var line = "    \(name): \(count(group.files.count, "file")) import\(group.files.count == 1 ? "s" : "") it"
                if !group.symbols.isEmpty {
                    line += "; uses " + group.symbols.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
                }
                lines.append(line)
            }
        }
        let sections: [(String, [String: Group])] = [("APIs missing from the module", members), ("Names not found", unknownNames),
                                                     ("Calls with no matching overload", calls), ("Other errors", other)]
        for (title, groups) in sections where !groups.isEmpty {
            lines.append("  \(title):")
            for (key, group) in sorted(groups) { lines.append("    \(key): \(count(group.uses, "use")) in \(count(group.files.count, "file"))") }
        }
        return lines.joined(separator: "\n")
    }

    func json() -> [String: Any] {
        func files(_ group: Group) -> [String] { group.files.sorted() }
        return [
            "errors": errorCount,
            "diagnostics": diagnostics.filter { $0.severity == "error" }.map { ["file": $0.file, "line": $0.line, "column": $0.column, "message": $0.message] as [String: Any] },
            "frameworks": frameworks.sorted { $0.key < $1.key }.map { ["name": $0.key, "files": files($0.value), "symbols": $0.value.symbols] },
            "missingAPIs": sorted(members).map { ["api": $0.0, "uses": $0.1.uses, "files": files($0.1)] },
            "unknownNames": sorted(unknownNames).map { ["name": $0.0, "uses": $0.1.uses, "files": files($0.1)] },
            "callMismatches": sorted(calls).map { ["call": $0.0, "uses": $0.1.uses, "files": files($0.1)] },
            "otherErrors": sorted(other).map { ["message": $0.0, "uses": $0.1.uses, "files": files($0.1)] },
        ]
    }
}

// MARK: - Command

enum CheckCommand {
    /// An empty module named `name`, so a missing framework stops hiding the names used from it.
    /// The stand-in is built once (cached) and linked into `directory`, which holds only the stand-ins of
    /// one type-check: a module stubbed for another target must not become importable here unnoticed.
    static func stub(_ name: String, _ installation: Installation, into directory: String) -> Bool {
        let fm = FileManager.default
        let store = ModuleBuilder.cacheRoot + "/stubs-" + hash([installation.swiftc, ModuleBuilder.stamp(installation.swiftc)])
        let module = store + "/\(name).swiftmodule"
        if !fm.fileExists(atPath: module) {
            try? fm.createDirectory(atPath: store, withIntermediateDirectories: true)
            let source = store + "/\(name).swift"
            try? "// Empty stand-in used by `swiftui-screenshot check`.\n".write(toFile: source, atomically: true, encoding: .utf8)
            let result = swiftuiScreenshotRun(installation.swiftc, ["-parse-as-library", "-emit-module", "-module-name", name, source, "-emit-module-path", module])
            guard result.status == 0 else { return false }
        }
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: directory + "/\(name).swiftmodule", withDestinationPath: module)
        return true
    }

    /// Every module name imported by the sources, submodules as written (`CoreImage.CIFilterBuiltins`).
    static func importedModules(_ sources: [(path: String, contents: String)]) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*import[ \t]+(?:(?:struct|class|enum|protocol|typealias|func|var|let)[ \t]+)?([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"#,
                                                   options: [.anchorsMatchLines]) else { return [] }
        var names: Set<String> = []
        for source in sources {
            let ns = source.contents as NSString
            for match in regex.matches(in: source.contents, range: NSRange(location: 0, length: ns.length)) {
                let whole = ns.substring(with: match.range)
                var name = ns.substring(with: match.range(at: 1))
                // `import struct Foo.Bar` names a declaration, not a submodule.
                if whole.range(of: #"import[ \t]+(struct|class|enum|protocol|typealias|func|var|let)[ \t]"#, options: .regularExpression) != nil {
                    name = String(name.split(separator: ".").first ?? "")
                }
                // The preprocessor imports submodules of the SDK's shims as the module (`CoreImage.CIFilterBuiltins`).
                if let head = name.split(separator: ".").first, name.contains("."), Preprocessor.submoduleParents.contains(String(head)) {
                    name = String(head)
                }
                names.insert(name)
            }
        }
        return names
    }

    struct ModuleResult {
        var name: String
        var origin: String
        var files: Int
        var ok: Bool
        var report: UnsupportedReport?
        var note: String?
    }

    /// Type-checks, stubbing missing modules until none is missing (at most 12 rounds).
    static func typecheck(_ builder: ModuleBuilder, _ target: ProjectTarget, _ sources: [(path: String, contents: String)],
                          _ generated: [CompiledSource], _ dependencies: [BuiltModule], entry: String?) -> (Bool, UnsupportedReport) {
        var stubbed: Set<String> = []
        var stubDirectory: String?
        let runDirectory = ModuleBuilder.cacheRoot + "/check/stubs-\(target.moduleName)-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.removeItem(atPath: runDirectory)
        defer { try? FileManager.default.removeItem(atPath: runDirectory) }
        var diagnostics = ""
        var status: Int32 = 0
        var sources = sources
        var importers: [String: Set<String>] = [:]
        // The compiler stops at the first missing module, so find them all up front with one probe compile.
        var pending = builder.missingModules(importedModules(sources), dependencies: dependencies, sdk: builder.needsSDK(sources))
        for _ in 0..<12 {
            if !pending.isEmpty {
                for name in pending.subtracting(stubbed) {
                    stubbed.insert(name)
                    if name.contains("."), let parent = name.split(separator: ".").first {
                        for index in sources.indices where sources[index].contents.contains("import \(name)") {
                            importers[name, default: []].insert(sources[index].path)
                            sources[index].contents = sources[index].contents.replacingOccurrences(of: "import \(name)", with: "import \(parent)")
                        }
                    } else if stub(name, builder.installation, into: runDirectory) {
                        stubDirectory = runDirectory
                    }
                }
                pending = []
            }
            // The entry keeps its previews (they are part of what must compile); other files lose theirs.
            (status, diagnostics) = builder.typecheck(target, sources: sources, generated: generated, dependencies: dependencies, stubs: stubDirectory,
                                                      keepPreviews: entry)
            let missing = Set(UnsupportedReport.parse(diagnostics).compactMap { UnsupportedReport.quoted($0.message, after: "no such module ") })
                .subtracting(stubbed)
            if missing.isEmpty { break }
            // A submodule (`import CoreImage.CIFilterBuiltins`) cannot be stood in for: its parent is imported instead.
            pending = missing
        }
        for source in sources {
            for module in SwiftIndexer.index(Array(source.contents.utf8)).importsModules where stubbed.contains(module) {
                importers[module, default: []].insert(source.path)
            }
        }
        for module in stubbed where importers[module] == nil { importers[module] = [] }
        return (status == 0 && stubbed.isEmpty, UnsupportedReport(diagnostics: diagnostics, stubbedModules: importers))
    }

    static func run(_ arguments: [String]) -> Never {
        let options = parse(arguments)
        let installation = Installation.locate()
        guard !installation.swiftc.isEmpty else { fail("swiftc not found. Install a Swift 6 toolchain and put it on PATH, or set SWIFTC.") }
        var context = ProjectSession.resolve(options)
        if context == nil {
            // Loose files: check them as one module.
            guard !options.inputs.isEmpty else { fail("check needs a file or --target\n\n\(usage)", code: 2) }
            var target = ProjectTarget(name: "App", kind: "application", platform: options.platform)
            target.sources = collectSources(options.inputs).files.map(ProjectSession.absolute)
            target.compilationConditions = []
            let project = Project(format: .swiftpm, path: options.inputs[0], root: FileManager.default.currentDirectoryPath, name: "files", targets: [target])
            context = ProjectContext(project: project, target: target, entry: nil, graph: ModuleGraph(nodes: [.init(target: target, dependencies: [], origin: "files")]))
        }
        var options2 = options
        ProjectSession.applyPlatform(context!.target, to: &options2)
        let ctx = context!
        var builder = ModuleBuilder(installation: installation, platform: options2.platform)
        builder.verbose = options.verbose
        builder.noCache = options.noCache
        let projectBuild = ProjectBuild(context: ctx, options: options2, installation: installation)

        var results: [ModuleResult] = []
        var built: [String: BuiltModule] = [:]
        var blocked: String?
        func read(_ path: String) -> String { FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        for node in ctx.graph.nodes.dropLast() {
            var target = node.target
            if !target.compilationConditions.contains("DEBUG") { target.compilationConditions.insert("DEBUG", at: 0) }
            let sources = target.sources.map { ($0, read($0)) }
            let stage = ProjectResources.stage(target.resources, module: target.moduleName)
            let generated = projectBuild.generatedFiles(target, stage: stage, isPackage: target.kind == "package-target", sdk: builder.needsSDK(sources), sources: sources)
            var plannedNode = node
            plannedNode.target = target
            do {
                built[target.moduleName] = try builder.buildLibrary(.init(node: plannedNode, sources: sources, generated: generated, resourceDirectory: stage),
                                                                    dependencies: projectBuild.transitiveDependencies(node, built))
                results.append(ModuleResult(name: target.moduleName, origin: node.origin, files: sources.count, ok: true))
            } catch {
                let (_, report) = typecheck(builder, target, sources, generated, projectBuild.transitiveDependencies(node, built), entry: nil)
                results.append(ModuleResult(name: target.moduleName, origin: node.origin, files: sources.count, ok: false, report: report))
                blocked = "\(node.origin) (module \(target.moduleName))"
                break
            }
        }
        var closureNote: String?
        if blocked == nil {
            let node = ctx.graph.entry
            var target = node.target
            if target.kind == "package-target", !target.compilationConditions.contains("DEBUG") { target.compilationConditions.insert("DEBUG", at: 0) }
            let all = target.sources.map { ($0, read($0)) }
            let sources = projectBuild.closure(all, wholeWithoutEntry: true)
            if sources.count != all.count { closureNote = "compiling \(sources.count) of \(all.count) files of \(target.name)" }
            let stage = ProjectResources.stage(target.resources, module: target.moduleName)
            let generated = projectBuild.generatedFiles(target, stage: stage, isPackage: target.kind == "package-target", sdk: true, sources: sources)
            let (ok, report) = typecheck(builder, target, sources, generated, projectBuild.transitiveDependencies(node, built), entry: ctx.entry)
            results.append(ModuleResult(name: target.moduleName, origin: node.origin, files: sources.count, ok: ok, report: report, note: closureNote))
        }
        let ok = blocked == nil && results.allSatisfy(\.ok)

        if options.json {
            var object: [String: Any] = ["ok": ok, "project": ctx.project.path, "target": ctx.target.name, "platform": options2.platform,
                                         "unsupportedPackages": ctx.graph.unsupported]
            if let entry = ctx.entry { object["entry"] = entry }
            object["modules"] = results.map { r -> [String: Any] in
                var m: [String: Any] = ["name": r.name, "origin": r.origin, "files": r.files, "ok": r.ok]
                if let report = r.report, !report.isEmpty { m["report"] = report.json() }
                if let n = r.note { m["note"] = n }
                return m
            }
            if let blocked { object["blocked"] = "the target was not checked: \(blocked) does not compile" }
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("\(ctx.project.format.rawValue) \(ctx.project.name), target \(ctx.target.name) (\(options2.platform))")
            for r in results {
                print("\(r.ok ? "ok    " : "FAILED") \(r.origin) (\(r.files) files)\(r.note.map { ", " + $0 } ?? "")")
                if let report = r.report, !report.isEmpty {
                    print(report.text().split(separator: "\n").map { "  " + $0 }.joined(separator: "\n"))
                    if options.verbose {
                        for d in report.diagnostics where d.severity == "error" { print("  \(d.file):\(d.line):\(d.column): error: \(d.message)") }
                    }
                }
            }
            for missing in ctx.graph.unsupported { print("not built: \(missing)") }
            if let blocked { print("the target was not checked: \(blocked) does not compile") }
        }
        exit(ok ? 0 : 1)
    }
}
