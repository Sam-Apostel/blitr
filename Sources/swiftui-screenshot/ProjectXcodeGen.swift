import Foundation

/// Reads an XcodeGen spec (`project.yml`): targets with their sources, dependencies, platform,
/// deployment target and compilation conditions, and the local packages they use.
/// See https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md for the format.
enum XcodeGenReader {
    static let platforms = ["ios": "iOS", "tvos": "tvOS", "watchos": "watchOS", "macos": "macOS", "visionos": "visionOS"]

    /// A spec with its `include:`s merged in. Each target remembers the directory its paths are relative to.
    struct Spec {
        var root: YAML
        var targetBase: [String: String] = [:]
        var packageBase: [String: String] = [:]
    }

    static func readSpec(_ path: String, depth: Int = 0) throws -> Spec {
        guard depth < 8 else { throw ProjectError("include: nested too deeply at \(path)") }
        guard let data = FileManager.default.contents(atPath: path) else { throw ProjectError("cannot read \(path)") }
        let yaml: YAML
        do { yaml = try YAML.parse(String(decoding: data, as: UTF8.self)) } catch { throw ProjectError("\(path): \(error)") }
        let base = (path as NSString).deletingLastPathComponent
        var spec = Spec(root: .map([]))
        for include in yaml["include"]?.list ?? [] {
            let file = include.string ?? include["path"]?.string
            guard let file else { continue }
            let relative = include["relativePaths"]?.bool ?? true
            let resolved = ProjectFiles.absolute(file, relativeTo: base)
            var included = try readSpec(resolved, depth: depth + 1)
            if !relative {
                for key in included.targetBase.keys { included.targetBase[key] = base }
                for key in included.packageBase.keys { included.packageBase[key] = base }
            }
            spec.root = spec.root.merged(with: included.root)
            spec.targetBase.merge(included.targetBase) { _, new in new }
            spec.packageBase.merge(included.packageBase) { _, new in new }
        }
        var own = yaml
        if case .map(let entries) = own { own = .map(entries.filter { $0.key != "include" }) }
        spec.root = spec.root.merged(with: own)
        for (name, _) in yaml["targets"]?.entries ?? [] { spec.targetBase[name] = base }
        for (name, _) in yaml["packages"]?.entries ?? [] { spec.packageBase[name] = base }
        return spec
    }

    static func load(_ path: String) throws -> Project {
        let spec = try readSpec(path)
        let yaml = spec.root
        let root = (path as NSString).deletingLastPathComponent
        let options = yaml["options"] ?? .null
        let developmentLanguage = options["developmentLanguage"]?.string ?? "en"
        var notes: [String] = []

        // packages: Name: { path: Local } | { url: ..., from: ... } | { github: owner/repo }
        var packages: [String: ProjectDependency] = [:]
        for (name, value) in yaml["packages"]?.entries ?? [] {
            let base = spec.packageBase[name] ?? root
            if let local = value["path"]?.string {
                packages[name] = .package(path: ProjectFiles.absolute(local, relativeTo: base), product: name)
            } else {
                let location = value["url"]?.string ?? value["github"]?.string.map { "github.com/" + $0 } ?? "unknown location"
                packages[name] = .remote(name: name, location: location)
            }
        }
        // The older `localPackages: [path]` form.
        for local in yaml["localPackages"]?.strings ?? [] {
            let name = (local as NSString).lastPathComponent
            packages[name] = .package(path: ProjectFiles.absolute(local, relativeTo: root), product: name)
        }

        let projectSettings = yaml["settings"] ?? .null
        let templates = yaml["targetTemplates"] ?? .null
        var targets: [ProjectTarget] = []

        for (name, rawTarget) in yaml["targets"]?.entries ?? [] {
            var definition = YAML.map([])
            for template in rawTarget["templates"]?.strings ?? [] {
                if let body = templates[template] { definition = definition.merged(with: body) }
                else { notes.append("target \(name): unknown template \(template)") }
            }
            definition = definition.merged(with: rawTarget)
            let base = spec.targetBase[name] ?? root

            // `platform: [iOS, tvOS]` makes one target per platform, named Name_iOS, Name_tvOS.
            var platformNames = definition["platform"]?.strings ?? []
            if platformNames == ["auto"] || platformNames.isEmpty {
                platformNames = [definition["supportedDestinations"]?.strings.first ?? "iOS"]
            }
            let multiple = platformNames.count > 1
            for platformName in platformNames {
                let platform = platforms[platformName.lowercased()] ?? platformName
                let targetName = multiple ? "\(name)_\(platform)" : name
                let substituted = substitute(definition, ["target_name": name, "platform": platform])
                var target = try makeTarget(targetName, substituted, platform: platform, base: base, packages: packages,
                                            projectSettings: projectSettings, options: options, notes: &notes)
                target.developmentLanguage = developmentLanguage
                targets.append(target)
            }
        }
        return Project(format: .xcodegen, path: path, root: root, name: yaml["name"]?.string ?? (root as NSString).lastPathComponent,
                       targets: targets, developmentLanguage: developmentLanguage, notes: notes)
    }

    /// Replaces `${name}` / `$name` placeholders in every scalar.
    static func substitute(_ yaml: YAML, _ values: [String: String]) -> YAML {
        switch yaml {
        case .scalar(var s):
            for (key, value) in values {
                s = s.replacingOccurrences(of: "${\(key)}", with: value).replacingOccurrences(of: "$\(key)", with: value)
            }
            return .scalar(s)
        case .list(let items): return .list(items.map { substitute($0, values) })
        case .map(let entries): return .map(entries.map { ($0.key, substitute($0.value, values)) })
        case .null: return .null
        }
    }

    static func kind(_ type: String) -> String {
        switch type {
        case "application", "application.messages", "application.watchapp", "application.watchapp2", "application.watchapp2-container", "application.on-demand-install-capable":
            return "application"
        case "framework", "framework.static", "xcframework": return "framework"
        case "library.static": return "static-library"
        case "library.dynamic": return "dynamic-library"
        case "bundle.unit-test", "bundle.ui-testing": return "test"
        case "app-extension", "app-extension.messages", "app-extension.messages-sticker-pack", "app-extension.intents-service",
             "extensionkit-extension", "watchkit-extension", "watchkit2-extension", "tv-app-extension":
            return "app-extension"
        default: return type
        }
    }

    /// Build settings for the Debug configuration: project base, project Debug, target base, target Debug.
    static func settings(_ value: YAML) -> [(String, YAML)] {
        guard case .map(let entries) = value else { return [] }
        let structured = entries.contains { ["base", "configs", "groups"].contains($0.key) }
        guard structured else { return entries.map { ($0.key, $0.value) } }
        var result = value["base"]?.entries.map { ($0.key, $0.value) } ?? []
        for (config, body) in value["configs"]?.entries ?? [] where config.lowercased() == "debug" {
            result += body.entries.map { ($0.key, $0.value) }
        }
        return result
    }

    static func makeTarget(_ name: String, _ definition: YAML, platform: String, base: String, packages: [String: ProjectDependency],
                           projectSettings: YAML, options: YAML, notes: inout [String]) throws -> ProjectTarget {
        let type = definition["type"]?.string ?? "application"
        var target = ProjectTarget(name: name, kind: kind(type), platform: platform)
        target.deploymentTarget = definition["deploymentTarget"]?.string ?? definition["deploymentTarget"]?[platform]?.string
            ?? options["deploymentTarget"]?[platform]?.string

        // Settings: Debug is what previews run, so it decides the compilation conditions (DEBUG included).
        var conditions = ["DEBUG"]
        let allSettings = settings(projectSettings) + settings(definition["settings"] ?? .null)
        for (key, value) in allSettings {
            switch key {
            case "SWIFT_ACTIVE_COMPILATION_CONDITIONS":
                let list = value.strings.flatMap { $0.split(separator: " ").map(String.init) }
                if !list.contains("$(inherited)") { conditions = [] }
                conditions += list.filter { $0 != "$(inherited)" }
            case "OTHER_SWIFT_FLAGS":
                let words = value.strings.flatMap { $0.split(separator: " ").map(String.init) }
                for (i, word) in words.enumerated() where word == "-D" && i + 1 < words.count { conditions.append(words[i + 1]) }
                for word in words where word.hasPrefix("-D") && word.count > 2 { conditions.append(String(word.dropFirst(2))) }
            case "SWIFT_VERSION": target.swiftVersion = value.string
            case "IPHONEOS_DEPLOYMENT_TARGET" where platform == "iOS",
                 "TVOS_DEPLOYMENT_TARGET" where platform == "tvOS",
                 "WATCHOS_DEPLOYMENT_TARGET" where platform == "watchOS",
                 "MACOSX_DEPLOYMENT_TARGET" where platform == "macOS":
                if definition["deploymentTarget"] == nil { target.deploymentTarget = value.string ?? target.deploymentTarget }
            default: break
            }
        }
        var seen: Set<String> = []
        target.compilationConditions = conditions.filter { !$0.isEmpty && seen.insert($0).inserted }
        let infoPlist = definition["info"]?["path"]?.string.map { ProjectFiles.absolute($0, relativeTo: base) }

        // Sources.
        var sources: [String] = []
        var resources: [Resource] = []
        for entry in definition["sources"]?.list ?? [] {
            let relative = entry.string ?? entry["path"]?.string
            guard let relative else { continue }
            let path = ProjectFiles.absolute(relative, relativeTo: base)
            let phase = entry["buildPhase"]?.string ?? entry["buildPhase"]?.entries.first?.key
            let optional = entry["optional"]?.bool ?? false
            guard FileManager.default.fileExists(atPath: path) else {
                if !optional { notes.append("target \(name): source path \(relative) does not exist") }
                continue
            }
            let excludes = (entry["excludes"]?.strings ?? []).compactMap(ProjectFiles.globRegex)
            let includes = (entry["includes"]?.strings ?? []).compactMap(ProjectFiles.globRegex)
            let isFolderReference = entry["type"]?.string == "folder"
            if !ProjectFiles.isDirectory(path) || isFolderReference || ProjectFiles.bundleExtensions.contains((path as NSString).pathExtension.lowercased()) {
                classify(path, phase: phase, folder: isFolderReference, infoPlist: infoPlist, sources: &sources, resources: &resources)
                continue
            }
            for file in ProjectFiles.walk(path) {
                if excludes.contains(where: { ProjectFiles.matches($0, file) }) { continue }
                if !includes.isEmpty, !includes.contains(where: { ProjectFiles.matches($0, file) }) { continue }
                classify(path + "/" + file, phase: phase, folder: false, infoPlist: infoPlist, sources: &sources, resources: &resources)
            }
        }
        target.sources = sources
        target.resources = resources

        for dependency in definition["dependencies"]?.list ?? [] {
            if let other = dependency["target"]?.string {
                target.dependencies.append(.target(other))
            } else if let package = dependency["package"]?.string {
                let products = dependency["products"]?.strings ?? dependency["product"].map { $0.strings } ?? [package]
                guard let declared = packages[package] else {
                    notes.append("target \(name): package \(package) is not declared under packages:")
                    continue
                }
                for product in products {
                    switch declared {
                    case .package(let path, _): target.dependencies.append(.package(path: path, product: product))
                    case .remote(_, let location): target.dependencies.append(.remote(name: product, location: location))
                    default: break
                    }
                }
            } else if let sdk = dependency["sdk"]?.string ?? dependency["framework"]?.string {
                target.dependencies.append(.sdk((sdk as NSString).lastPathComponent))
            } else if let carthage = dependency["carthage"]?.string {
                target.dependencies.append(.remote(name: carthage, location: "Carthage"))
            }
        }
        if target.kind == "test" { target.unsupportedReason = "test target" }
        return target
    }

    static func classify(_ path: String, phase: String?, folder: Bool, infoPlist: String?, sources: inout [String], resources: inout [Resource]) {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if folder { resources.append(Resource(path: path, rule: .copy)); return }
        switch phase {
        case "none": return
        case "resources", "copyFiles": resources.append(Resource(path: path)); return
        case "sources": if ext == "swift" { sources.append(path) }; return
        default: break
        }
        if ext == "swift" { sources.append(path); return }
        if path == infoPlist || name == "Info.plist" || name.hasSuffix("-Info.plist") { return }
        if ProjectFiles.ignoredExtensions.contains(ext) || ProjectFiles.nonResourceDirectories.contains(ext) { return }
        resources.append(Resource(path: path))
    }
}
