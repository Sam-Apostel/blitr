import Foundation

// Project mode: the data model shared by the XcodeGen, SwiftPM and Xcode readers, and the code that
// finds the project an entry file belongs to and resolves a target's module graph.
//
// A project is described as targets (compiled as one Swift module each) that depend on local package
// products and other targets. Local packages are loaded lazily as their products are needed.

/// One Swift module to compile: an app/extension/framework target or a SwiftPM target.
struct ProjectTarget {
    var name: String
    /// application, app-extension, framework, library, watch-app, package-target, ...
    var kind: String
    /// Swift's spelling of the platform (iOS, tvOS, watchOS, macOS, visionOS), when known.
    var platform: String?
    var deploymentTarget: String?
    /// Absolute paths of the .swift files compiled into the module.
    var sources: [String] = []
    /// Absolute paths of resources: files, asset catalogs, string catalogs, `.lproj` folders, folder references.
    var resources: [Resource] = []
    var dependencies: [ProjectDependency] = []
    /// `-D` conditions (SWIFT_ACTIVE_COMPILATION_CONDITIONS / swiftSettings define).
    var compilationConditions: [String] = []
    /// `-swift-version` (4, 4.2, 5, 6).
    var swiftVersion: String?
    /// For SwiftPM targets: the package's name, used for `-package-name` and the module's `Bundle.module`.
    var packageName: String?
    var developmentLanguage: String?
    /// A target that is part of the project but that this tool cannot use; the reason is shown if it is needed.
    var unsupportedReason: String?

    var moduleName: String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        return cleaned.first?.isNumber == true ? "_" + cleaned : cleaned
    }
    /// Targets whose sources other modules can `import`. Apps and extensions are embedded, not imported.
    var isImportable: Bool { ["framework", "library", "package-target", "static-library", "dynamic-library"].contains(kind) }
}

struct Resource: Hashable {
    enum Rule: Hashable { case process, copy }
    var path: String
    var rule: Rule = .process
}

enum ProjectDependency: Hashable {
    /// Another target of the same project.
    case target(String)
    /// A product of a local package (directory containing Package.swift).
    case package(path: String, product: String)
    /// A package that would have to be fetched; it cannot be built here.
    case remote(name: String, location: String)
    /// A system framework or SDK library (WidgetKit.framework, ...). Informational.
    case sdk(String)
}

/// A local Swift package as described by its manifest.
struct LocalPackage {
    var name: String
    var root: String
    var targets: [ProjectTarget]
    /// Product name -> target names.
    var products: [String: [String]]
    /// Package dependencies: identity -> local path, or nil for remote packages.
    var dependencies: [String: String?]
    var defaultLocalization: String?
    /// Minimum deployment versions declared in `platforms:` (platform -> version).
    var platforms: [String: String] = [:]
}

/// A parsed project: XcodeGen spec, Xcode project or a bare Swift package.
struct Project {
    enum Format: String { case xcodegen = "XcodeGen", xcodeproj = "Xcode project", swiftpm = "Swift package" }
    var format: Format
    /// The project description file (project.yml, X.xcodeproj, Package.swift).
    var path: String
    /// Directory that relative paths in the description are resolved against.
    var root: String
    var name: String
    var targets: [ProjectTarget]
    var developmentLanguage: String?
    /// Problems found while reading the description that do not stop it from being used.
    var notes: [String] = []
    /// For a Swift package project, the package itself.
    var package: LocalPackage?

    func target(named name: String) -> ProjectTarget? { targets.first { $0.name == name } }

    /// Targets that compile `file`, the most likely owner first: apps before extensions, then declaration order.
    func owners(of file: String) -> [ProjectTarget] {
        let owning = targets.filter { $0.sources.contains(file) && $0.unsupportedReason == nil }
        func rank(_ t: ProjectTarget) -> Int {
            switch t.kind {
            case "application", "package-target": return 0
            case "framework", "library", "static-library", "dynamic-library": return 1
            default: return 2
            }
        }
        return owning.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}

struct ProjectError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Discovery

enum ProjectLocator {
    /// Project descriptions in `directory`, in priority order: XcodeGen spec, Xcode project, Swift package.
    static func descriptions(in directory: String) -> [(Project.Format, String)] {
        let fm = FileManager.default
        var found: [(Project.Format, String)] = []
        for name in ["project.yml", "project.yaml"] where fm.fileExists(atPath: directory + "/" + name) {
            found.append((.xcodegen, directory + "/" + name))
        }
        let projects = ((try? fm.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".xcodeproj") }.sorted()
        for name in projects where fm.fileExists(atPath: directory + "/" + name + "/project.pbxproj") {
            found.append((.xcodeproj, directory + "/" + name))
        }
        if fm.fileExists(atPath: directory + "/Package.swift") { found.append((.swiftpm, directory + "/Package.swift")) }
        return found
    }

    static func load(_ format: Project.Format, _ path: String) throws -> Project {
        switch format {
        case .xcodegen: return try XcodeGenReader.load(path)
        case .xcodeproj: return try PBXProjectReader.load(path)
        case .swiftpm: return try SwiftPMReader.project(path)
        }
    }

    /// Walks up from `file` to the nearest project description with a target that compiles it.
    /// Descriptions that do not include the file are skipped, so a stray Package.swift above an
    /// unrelated file does not capture it.
    static func find(owning file: String, notes: inout [String]) -> Project? {
        var directory = (file as NSString).deletingLastPathComponent
        while !directory.isEmpty {
            for (format, path) in descriptions(in: directory) {
                do {
                    let project = try load(format, path)
                    if !project.owners(of: file).isEmpty { return project }
                    notes.append("\(path) does not compile \((file as NSString).lastPathComponent)")
                } catch {
                    notes.append("could not read \(path): \(error)")
                }
            }
            if directory == "/" { break }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// The nearest project description at or above `directory`, whatever it contains.
    static func nearest(from directory: String) -> (Project.Format, String)? {
        var directory = directory
        while !directory.isEmpty {
            if let first = descriptions(in: directory).first { return first }
            if directory == "/" { break }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }
}

// MARK: - Module graph

/// The ordered set of modules a target needs: local package targets and importable project targets,
/// dependencies before dependents, the target itself last.
struct ModuleGraph {
    struct Node {
        var target: ProjectTarget
        /// Module names this one imports directly (resolved, buildable).
        var dependencies: [String]
        /// Where the module comes from, for messages: "package DesignKit", "target Shared".
        var origin: String
    }
    var nodes: [Node] = []
    /// Remote packages (and unresolvable products) the target depends on, by name.
    var unsupported: [String] = []
    var notes: [String] = []

    var entry: Node { nodes[nodes.count - 1] }

    static func resolve(_ target: ProjectTarget, in project: Project) -> ModuleGraph {
        var graph = ModuleGraph()
        var packages: [String: LocalPackage] = [:]
        if let package = project.package { packages[package.root] = package }
        var visiting: Set<String> = []
        var done: [String: String] = [:]   // key -> module name

        func loadPackage(_ root: String) -> LocalPackage? {
            let root = (root as NSString).standardizingPath
            if let cached = packages[root] { return cached }
            do {
                let package = try SwiftPMReader.load(root + "/Package.swift")
                packages[root] = package
                return package
            } catch {
                graph.notes.append("could not read the package at \(root): \(error)")
                return nil
            }
        }

        /// Visits a package target, returns its module name.
        @discardableResult
        func visitPackageTarget(_ package: LocalPackage, _ name: String) -> String? {
            let key = package.root + "#" + name
            if let module = done[key] { return module }
            guard let target = package.targets.first(where: { $0.name == name }) else {
                graph.notes.append("package \(package.name) has no target \(name)")
                return nil
            }
            if let reason = target.unsupportedReason {
                graph.unsupported.append("\(package.name)/\(name) (\(reason))")
                return nil
            }
            guard !visiting.contains(key) else { return nil }
            visiting.insert(key)
            var deps: [String] = []
            for dependency in target.dependencies {
                deps += visitDependency(dependency, from: package)
            }
            visiting.remove(key)
            graph.nodes.append(Node(target: target, dependencies: deps, origin: "package \(package.name)"))
            done[key] = target.moduleName
            return target.moduleName
        }

        func visitProduct(_ package: LocalPackage, _ product: String) -> [String] {
            // A product that is not declared falls back to a target of the same name (SwiftPM allows
            // `.target(name:)` style references from inside the package).
            let names = package.products[product] ?? (package.targets.contains { $0.name == product } ? [product] : nil)
            guard let names else {
                graph.unsupported.append("product \(product) of package \(package.name) (not declared)")
                return []
            }
            return names.compactMap { visitPackageTarget(package, $0) }
        }

        func visitDependency(_ dependency: ProjectDependency, from package: LocalPackage?) -> [String] {
            switch dependency {
            case .target(let name):
                if let package {
                    if package.targets.contains(where: { $0.name == name }) { return visitPackageTarget(package, name).map { [$0] } ?? [] }
                    // `byName` dependencies may also name a product of a package dependency.
                    for (_, path) in package.dependencies {
                        if let path, let other = loadPackage(path), other.products[name] != nil { return visitProduct(other, name) }
                    }
                    graph.unsupported.append("\(name) (needed by package \(package.name); not found locally)")
                    return []
                }
                guard let other = project.target(named: name) else {
                    graph.notes.append("dependency on unknown target \(name)")
                    return []
                }
                guard other.isImportable else { return [] }   // embedded app extensions, watch apps: not imported
                return visitProjectTarget(other).map { [$0] } ?? []
            case .package(let path, let product):
                guard let other = loadPackage(path) else { return [] }
                return visitProduct(other, product)
            case .remote(let name, let location):
                graph.unsupported.append("\(name) (remote package \(location))")
                return []
            case .sdk:
                return []
            }
        }

        func visitProjectTarget(_ target: ProjectTarget) -> String? {
            let key = "project#" + target.name
            if let module = done[key] { return module }
            guard !visiting.contains(key) else { return nil }
            visiting.insert(key)
            var deps: [String] = []
            for dependency in target.dependencies {
                // In a package project, a target's dependencies are package targets/products.
                deps += visitDependency(dependency, from: project.format == .swiftpm ? project.package : nil)
            }
            visiting.remove(key)
            graph.nodes.append(Node(target: target, dependencies: deps, origin: "target \(target.name)"))
            done[key] = target.moduleName
            return target.moduleName
        }

        _ = visitProjectTarget(target)
        // The entry target must be last; it is, since it finishes visiting last.
        return graph
    }
}

// MARK: - File helpers

enum ProjectFiles {
    /// Directory extensions that are resources as a whole (never descended into for sources).
    static let bundleExtensions: Set<String> = ["xcassets", "lproj", "bundle", "xcdatamodeld", "xcdatamodel", "scnassets", "spriteatlas",
                                                "storyboardc", "icon", "docc", "playground", "framework", "xcframework", "xcodeproj",
                                                "xcworkspace", "momd", "rcproject", "reality", "xcmappingmodel", "mlpackage"]
    /// Files that are part of a target's folder but neither compiled nor copied.
    static let ignoredExtensions: Set<String> = ["h", "m", "mm", "c", "cc", "cpp", "md", "entitlements", "xcconfig", "modulemap",
                                                 "xcscheme", "pch", "docc", "orig", "swp", "xctestplan", "gitkeep"]
    static let nonResourceDirectories: Set<String> = ["docc", "playground", "xcodeproj", "xcworkspace", "framework", "xcframework"]

    /// All files below `directory` (relative paths), not descending into bundle-like directories,
    /// which are returned as entries themselves. Hidden files are skipped.
    static func walk(_ directory: String) -> [String] {
        let fm = FileManager.default
        var result: [String] = []
        func visit(_ relative: String) {
            let path = relative.isEmpty ? directory : directory + "/" + relative
            guard let names = try? fm.contentsOfDirectory(atPath: path) else { return }
            for name in names.sorted() where !name.hasPrefix(".") {
                let child = relative.isEmpty ? name : relative + "/" + name
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: directory + "/" + child, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    if bundleExtensions.contains((name as NSString).pathExtension.lowercased()) { result.append(child) }
                    else { visit(child) }
                } else {
                    result.append(child)
                }
            }
        }
        visit("")
        return result
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Converts a glob (`*`, `**`, `?`, `{a,b}`) to an anchored regular expression.
    static func globRegex(_ glob: String) -> NSRegularExpression? {
        var pattern = "^"
        let chars = Array(glob)
        var i = 0
        var braces = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*" {
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" { pattern += "(.*/)?"; i += 3; continue }
                    pattern += ".*"; i += 2; continue
                }
                pattern += "[^/]*"
            } else if c == "?" {
                pattern += "[^/]"
            } else if c == "{" {
                pattern += "("; braces += 1
            } else if c == "}", braces > 0 {
                pattern += ")"; braces -= 1
            } else if c == ",", braces > 0 {
                pattern += "|"
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        // A pattern naming a directory also matches everything inside it.
        pattern += "(/.*)?$"
        return try? NSRegularExpression(pattern: pattern)
    }

    static func matches(_ regex: NSRegularExpression, _ path: String) -> Bool {
        regex.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
    }

    static func absolute(_ path: String, relativeTo base: String) -> String {
        let joined = path.hasPrefix("/") ? path : base + "/" + path
        return (joined as NSString).standardizingPath
    }
}
