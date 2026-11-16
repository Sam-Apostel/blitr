import Foundation

/// Reads a local Swift package's manifest with `swift package dump-package`, run on a copy of the
/// manifest in the cache so the package directory is never written to. The JSON is cached by the
/// manifest's contents, so this costs about a second once per manifest version.
enum SwiftPMReader {
    static var cacheRoot: String {
        ProcessInfo.processInfo.environment["BLITR_CACHE"] ?? (NSHomeDirectory() + "/.cache/blitr")
    }

    static func swiftExecutable() -> String? { located }
    private static let located: String? = {
        let swiftc = Installation.locate().swiftc
        guard !swiftc.isEmpty else { return nil }
        let swift = (swiftc as NSString).deletingLastPathComponent + "/swift"
        return FileManager.default.isExecutableFile(atPath: swift) ? swift : nil
    }()

    /// Where the manifest is copied to be evaluated; paths in the dump are relative to it.
    static func copyDirectory(for manifest: String) -> String {
        let text = FileManager.default.contents(atPath: manifest).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return cacheRoot + "/manifests/" + hash([text, swiftExecutable() ?? ""])
    }

    static func relativePath(from base: String, to path: String) -> String {
        let a = (base as NSString).standardizingPath.split(separator: "/"), b = (path as NSString).standardizingPath.split(separator: "/")
        var common = 0
        while common < a.count, common < b.count, a[common] == b[common] { common += 1 }
        return (Array(repeating: "..", count: a.count - common) + b[common...].map(String.init)).joined(separator: "/")
    }

    static func dump(_ manifest: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: manifest) else { throw ProjectError("cannot read \(manifest)") }
        let text = String(decoding: data, as: UTF8.self)
        let swift = swiftExecutable()
        let directory = copyDirectory(for: manifest)
        let json = directory + ".json"
        if let cached = FileManager.default.contents(atPath: json),
           let object = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] { return object }
        guard let swift else { throw ProjectError("cannot read \(manifest): the `swift` executable was not found next to swiftc") }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try text.write(toFile: directory + "/Package.swift", atomically: true, encoding: .utf8)
        let result = run(swift, ["package", "--package-path", directory, "--disable-sandbox", "dump-package"])
        try? FileManager.default.removeItem(atPath: directory)
        guard result.status == 0, let object = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else {
            let message = result.stderr.split(separator: "\n").filter { $0.contains("error") }.prefix(3).joined(separator: "\n")
            throw ProjectError("swift package dump-package failed for \(manifest)\(message.isEmpty ? "" : ":\n" + message)")
        }
        try? Data(result.stdout.utf8).write(to: URL(fileURLWithPath: json))
        return object
    }

    /// The first element of a `{"kind": [a, b, ...]}` style enum payload.
    private static func payload(_ value: Any?) -> (String, [Any])? {
        guard let dict = value as? [String: Any], let (kind, body) = dict.first else { return nil }
        return (kind, body as? [Any] ?? [body])
    }

    static func load(_ manifest: String) throws -> LocalPackage {
        let json = try dump(manifest)
        let root = (manifest as NSString).deletingLastPathComponent
        let name = json["name"] as? String ?? (root as NSString).lastPathComponent

        var dependencies: [String: String?] = [:]
        var remoteLocations: [String: String] = [:]
        for dependency in json["dependencies"] as? [Any] ?? [] {
            guard let (kind, body) = payload(dependency), let info = body.first as? [String: Any] else { continue }
            let identity = (info["identity"] as? String ?? "").lowercased()
            if kind == "fileSystem", let path = info["path"] as? String {
                // dump-package resolves relative paths against the copy's directory; recover the original.
                let original = ProjectFiles.absolute(relativePath(from: copyDirectory(for: manifest), to: path), relativeTo: root)
                dependencies[identity] = .some(original)
                if let explicit = info["nameForTargetDependencyResolutionOnly"] as? String { dependencies[explicit.lowercased()] = .some(original) }
            } else {
                dependencies[identity] = .some(nil)
                var location = "unknown"
                if let loc = info["location"] as? [String: Any], let (_, parts) = payload(loc) {
                    location = (parts.first as? [String: Any])?["urlString"] as? String ?? (parts.first as? String) ?? location
                }
                remoteLocations[identity] = location
            }
        }

        let toolsVersion = ((json["toolsVersion"] as? [String: Any])?["_version"] as? String) ?? "5.9"
        let modes = (json["swiftLanguageModes"] as? [Any] ?? json["swiftLanguageVersions"] as? [Any] ?? []).compactMap { mode -> String? in
            if let s = mode as? String { return s }
            if let (_, body) = payload(mode) { return body.first as? String }
            return nil
        }
        let swiftVersion = modes.last ?? (Int(toolsVersion.split(separator: ".").first ?? "5") ?? 5 >= 6 ? "6" : "5")

        var products: [String: [String]] = [:]
        for product in json["products"] as? [[String: Any]] ?? [] {
            if let productName = product["name"] as? String { products[productName] = product["targets"] as? [String] ?? [] }
        }

        var platforms: [String: String] = [:]
        for platform in json["platforms"] as? [[String: Any]] ?? [] {
            if let n = platform["platformName"] as? String, let v = platform["version"] as? String {
                platforms[XcodeGenReader.platforms[n.lowercased()] ?? n] = v
            }
        }

        var targets: [ProjectTarget] = []
        for target in json["targets"] as? [[String: Any]] ?? [] {
            guard let targetName = target["name"] as? String else { continue }
            let type = target["type"] as? String ?? "regular"
            var result = ProjectTarget(name: targetName, kind: "package-target")
            result.packageName = name
            result.swiftVersion = swiftVersion
            result.developmentLanguage = json["defaultLocalization"] as? String
            switch type {
            case "regular", "executable": break
            case "test": result.kind = "test"; result.unsupportedReason = "test target"
            case "macro": result.unsupportedReason = "macro target (compiler plugins cannot be built here)"
            default: result.unsupportedReason = "\(type) target"
            }

            let defaultDirectory = ["Sources", "Source", "src", "srcs"].map { root + "/" + $0 + "/" + targetName }
                .first(where: ProjectFiles.isDirectory) ?? root + "/Sources/" + targetName
            let testDirectory = root + "/Tests/" + targetName
            let directory = (target["path"] as? String).map { ProjectFiles.absolute($0, relativeTo: root) }
                ?? (type == "test" ? testDirectory : defaultDirectory)

            let excludes = (target["exclude"] as? [String] ?? []).map { ProjectFiles.absolute($0, relativeTo: directory) }
            var resources: [Resource] = []
            for resource in target["resources"] as? [[String: Any]] ?? [] {
                guard let path = resource["path"] as? String else { continue }
                let rule = (resource["rule"] as? [String: Any])?.keys.first == "copy" ? Resource.Rule.copy : .process
                resources.append(Resource(path: ProjectFiles.absolute(path, relativeTo: directory), rule: rule))
            }
            let explicitSources = (target["sources"] as? [String])?.map { ProjectFiles.absolute($0, relativeTo: directory) }
            func excluded(_ path: String) -> Bool {
                (excludes + resources.map(\.path)).contains { path == $0 || path.hasPrefix($0 + "/") }
            }
            var sources: [String] = []
            for base in explicitSources ?? [directory] {
                if !ProjectFiles.isDirectory(base) {
                    if base.hasSuffix(".swift"), !excluded(base) { sources.append(base) }
                    continue
                }
                for file in ProjectFiles.walk(base) {
                    let path = base + "/" + file
                    if excluded(path) { continue }
                    let ext = (file as NSString).pathExtension.lowercased()
                    if ext == "swift" { sources.append(path) }
                    // Resources SwiftPM processes without being declared.
                    else if ["xcassets", "xcstrings", "lproj", "storyboard", "xib", "xcdatamodeld", "xcdatamodel", "metal"].contains(ext) {
                        resources.append(Resource(path: path))
                    }
                }
            }
            result.sources = sources
            result.resources = resources

            for setting in target["settings"] as? [[String: Any]] ?? [] {
                guard (setting["tool"] as? String) == "swift", let (kind, body) = payload(setting["kind"]) else { continue }
                let value = (body.first as? [String: Any])?["_0"] as? String ?? body.first as? String
                if kind == "define", let value { result.compilationConditions.append(value) }
                if kind == "swiftLanguageMode" || kind == "swiftLanguageVersion", let value { result.swiftVersion = value }
            }

            for dependency in target["dependencies"] as? [Any] ?? [] {
                guard let (kind, body) = payload(dependency), let dependencyName = body.first as? String else { continue }
                switch kind {
                case "product":
                    let packageIdentity = (body.count > 1 ? body[1] as? String : nil)?.lowercased() ?? dependencyName.lowercased()
                    switch dependencies[packageIdentity] {
                    case .some(.some(let path)): result.dependencies.append(.package(path: path, product: dependencyName))
                    case .some(.none): result.dependencies.append(.remote(name: dependencyName, location: remoteLocations[packageIdentity] ?? "remote"))
                    case .none: result.dependencies.append(.remote(name: dependencyName, location: "package \(packageIdentity) is not declared"))
                    }
                default:
                    result.dependencies.append(.target(dependencyName))
                }
            }
            targets.append(result)
        }
        return LocalPackage(name: name, root: root, targets: targets, products: products, dependencies: dependencies,
                            defaultLocalization: json["defaultLocalization"] as? String, platforms: platforms)
    }

    /// A Swift package opened directly: its targets are the project's targets.
    static func project(_ manifest: String) throws -> Project {
        let package = try load(manifest)
        // A multi-platform package renders as iOS when it supports iOS, else as its first declared platform.
        let platform = package.platforms["iOS"] != nil ? "iOS" : package.platforms.keys.sorted().first
        var targets = package.targets
        for i in targets.indices {
            targets[i].platform = platform
            targets[i].deploymentTarget = platform.flatMap { package.platforms[$0] }
        }
        return Project(format: .swiftpm, path: manifest, root: package.root, name: package.name, targets: targets,
                       developmentLanguage: package.defaultLocalization, package: package)
    }
}
