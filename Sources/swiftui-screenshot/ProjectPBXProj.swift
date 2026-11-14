import Foundation

/// Reads an Xcode project (`X.xcodeproj/project.pbxproj`, the old-style "ASCII plist" format):
/// native targets, their Sources and Resources build phases, file-system-synchronized folders
/// (Xcode 16) with their membership exceptions, local and remote package references, target
/// dependencies and the Debug build settings that matter for compiling (SDKROOT, deployment
/// targets, compilation conditions, Swift version).
enum PBXProjectReader {
    indirect enum Value {
        case string(String)
        case array([Value])
        case dict([String: Value])

        var string: String? { if case .string(let s) = self { return s }; return nil }
        var array: [Value] { if case .array(let a) = self { return a }; return [] }
        var dict: [String: Value] { if case .dict(let d) = self { return d }; return [:] }
        subscript(key: String) -> Value? { dict[key] }
        var strings: [String] {
            switch self {
            case .string(let s): return s.split(separator: " ").map(String.init)
            case .array(let a): return a.compactMap(\.string)
            case .dict: return []
            }
        }
    }

    struct Parser {
        let chars: [UInt8]
        var i = 0
        init(_ data: Data) { chars = Array(data) }

        mutating func skip() {
            while i < chars.count {
                let c = chars[i]
                if c == 32 || c == 9 || c == 10 || c == 13 { i += 1; continue }
                if c == UInt8(ascii: "/"), i + 1 < chars.count, chars[i + 1] == UInt8(ascii: "*") {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == UInt8(ascii: "*") && chars[i + 1] == UInt8(ascii: "/")) { i += 1 }
                    i += 2; continue
                }
                if c == UInt8(ascii: "/"), i + 1 < chars.count, chars[i + 1] == UInt8(ascii: "/") {
                    while i < chars.count, chars[i] != 10 { i += 1 }
                    continue
                }
                break
            }
        }

        mutating func expect(_ c: Character) throws {
            skip()
            guard i < chars.count, chars[i] == c.asciiValue! else { throw ProjectError("project.pbxproj: expected '\(c)' at byte \(i)") }
            i += 1
        }

        mutating func value() throws -> Value {
            skip()
            guard i < chars.count else { throw ProjectError("project.pbxproj: unexpected end") }
            switch chars[i] {
            case UInt8(ascii: "{"):
                i += 1
                var dict: [String: Value] = [:]
                while true {
                    skip()
                    if i < chars.count, chars[i] == UInt8(ascii: "}") { i += 1; break }
                    guard case .string(let key) = try value() else { throw ProjectError("project.pbxproj: bad key at byte \(i)") }
                    try expect("=")
                    dict[key] = try value()
                    try expect(";")
                }
                return .dict(dict)
            case UInt8(ascii: "("):
                i += 1
                var items: [Value] = []
                while true {
                    skip()
                    if i < chars.count, chars[i] == UInt8(ascii: ")") { i += 1; break }
                    items.append(try value())
                    skip()
                    if i < chars.count, chars[i] == UInt8(ascii: ",") { i += 1 }
                }
                return .array(items)
            case UInt8(ascii: "\""):
                i += 1
                var bytes: [UInt8] = []
                while i < chars.count, chars[i] != UInt8(ascii: "\"") {
                    if chars[i] == UInt8(ascii: "\\"), i + 1 < chars.count {
                        i += 1
                        switch chars[i] {
                        case UInt8(ascii: "n"): bytes.append(10)
                        case UInt8(ascii: "t"): bytes.append(9)
                        default: bytes.append(chars[i])
                        }
                    } else {
                        bytes.append(chars[i])
                    }
                    i += 1
                }
                i += 1
                return .string(String(decoding: bytes, as: UTF8.self))
            default:
                let start = i
                while i < chars.count {
                    let c = chars[i]
                    let isWord = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c >= 0x80
                        || [UInt8(ascii: "_"), UInt8(ascii: "$"), UInt8(ascii: "/"), UInt8(ascii: ":"), UInt8(ascii: "."),
                            UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "<"), UInt8(ascii: ">")].contains(c)
                    if !isWord { break }
                    i += 1
                }
                guard i > start else { throw ProjectError("project.pbxproj: unexpected character at byte \(i)") }
                return .string(String(decoding: chars[start..<i], as: UTF8.self))
            }
        }
    }

    static let sdkPlatforms = ["iphoneos": "iOS", "iphonesimulator": "iOS", "appletvos": "tvOS", "appletvsimulator": "tvOS",
                               "watchos": "watchOS", "watchsimulator": "watchOS", "macosx": "macOS", "xros": "visionOS", "xrsimulator": "visionOS"]

    static func load(_ xcodeproj: String) throws -> Project {
        guard let data = FileManager.default.contents(atPath: xcodeproj + "/project.pbxproj") else {
            throw ProjectError("cannot read \(xcodeproj)/project.pbxproj")
        }
        var parser = Parser(data)
        let top = try parser.value()
        let objects = top["objects"]?.dict ?? [:]
        guard let rootID = top["rootObject"]?.string, let rootObject = objects[rootID] else {
            throw ProjectError("\(xcodeproj): no rootObject")
        }
        func object(_ id: Value?) -> [String: Value] { id?.string.flatMap { objects[$0]?.dict } ?? [:] }
        let projectDirectory = (xcodeproj as NSString).deletingLastPathComponent
        let root = ProjectFiles.absolute(rootObject["projectDirPath"]?.string ?? "", relativeTo: projectDirectory)
        var notes: [String] = []

        // Parent links, to resolve `<group>`-relative paths.
        var parent: [String: String] = [:]
        for (id, value) in objects {
            for child in value["children"]?.array ?? [] { if let c = child.string { parent[c] = id } }
        }
        let mainGroup = rootObject["mainGroup"]?.string
        var pathCache: [String: String?] = [:]
        func path(of id: String) -> String? {
            if let cached = pathCache[id] { return cached }
            let item = objects[id]?.dict ?? [:]
            let own = item["path"]?.string
            var result: String?
            switch item["sourceTree"]?.string ?? "<group>" {
            case "<absolute>": result = own
            case "SOURCE_ROOT": result = ProjectFiles.absolute(own ?? "", relativeTo: root)
            case "<group>":
                let base: String? = id == mainGroup ? root : parent[id].flatMap { path(of: $0) } ?? root
                result = base.map { own.map { ProjectFiles.absolute($0, relativeTo: base!) } ?? $0 }
            default: result = nil   // BUILT_PRODUCTS_DIR, SDKROOT, DEVELOPER_DIR: not source files
            }
            pathCache[id] = result
            return result
        }

        // Build settings, Debug configuration.
        func settings(_ listID: Value?) -> [String: Value] {
            let configurations = object(listID)["buildConfigurations"]?.array ?? []
            let debug = configurations.map { object($0) }.first { $0["name"]?.string == "Debug" } ?? configurations.first.map { object($0) }
            return debug?["buildSettings"]?.dict ?? [:]
        }
        let projectSettings = settings(rootObject["buildConfigurationList"])
        let developmentLanguage = rootObject["developmentRegion"]?.string

        // Packages: XCLocalSwiftPackageReference, plus folders with a Package.swift added as file references (older Xcode).
        var localPackages: [String: String] = [:]   // ref id -> directory
        var remotePackages: [String: String] = [:]  // ref id -> URL
        for (id, value) in objects {
            switch value["isa"]?.string {
            case "XCLocalSwiftPackageReference":
                if let relative = value["relativePath"]?.string { localPackages[id] = ProjectFiles.absolute(relative, relativeTo: root) }
            case "XCRemoteSwiftPackageReference":
                remotePackages[id] = value["repositoryURL"]?.string ?? "remote"
            case "PBXFileReference":
                if value["lastKnownFileType"]?.string == "wrapper" || value["lastKnownFileType"]?.string == "folder",
                   let directory = path(of: id), FileManager.default.fileExists(atPath: directory + "/Package.swift") {
                    localPackages[id] = directory
                }
            default: break
            }
        }
        var productOwners: [String: String] = [:]   // product -> package directory, for references without `package =`
        func packageDeclaring(_ product: String) -> String? {
            if let cached = productOwners[product] { return cached }
            for directory in Set(localPackages.values).sorted() {
                if let package = try? SwiftPMReader.load(directory + "/Package.swift"), package.products[product] != nil {
                    productOwners[product] = directory
                    return directory
                }
            }
            return nil
        }

        // File-system-synchronized folders: membership exceptions per target.
        struct ExceptionSet { var target: String; var files: [String] }
        func exceptions(of groupID: String) -> [ExceptionSet] {
            (objects[groupID]?["exceptions"]?.array ?? []).compactMap { id in
                let set = object(id)
                guard set["isa"]?.string == "PBXFileSystemSynchronizedBuildFileExceptionSet", let target = set["target"]?.string else { return nil }
                return ExceptionSet(target: target, files: set["membershipExceptions"]?.array.compactMap(\.string) ?? [])
            }
        }
        let synchronizedGroups = objects.filter { $0.value["isa"]?.string == "PBXFileSystemSynchronizedRootGroup" }.map(\.key)

        var targets: [ProjectTarget] = []
        let targetIDs = rootObject["targets"]?.array.compactMap(\.string) ?? []
        for targetID in targetIDs {
            let item = objects[targetID]?.dict ?? [:]
            guard let name = item["name"]?.string else { continue }
            guard item["isa"]?.string == "PBXNativeTarget" else {
                var skipped = ProjectTarget(name: name, kind: "aggregate")
                skipped.unsupportedReason = "\(item["isa"]?.string ?? "unknown") target"
                targets.append(skipped)
                continue
            }
            let productType = item["productType"]?.string ?? ""
            let kind: String
            switch productType {
            case let t where t.hasPrefix("com.apple.product-type.application"): kind = "application"
            case let t where t.contains("extension"): kind = "app-extension"
            case let t where t.hasPrefix("com.apple.product-type.framework"): kind = "framework"
            case "com.apple.product-type.library.static": kind = "static-library"
            case "com.apple.product-type.library.dynamic": kind = "dynamic-library"
            case let t where t.contains("bundle.unit-test") || t.contains("bundle.ui-testing"): kind = "test"
            default: kind = productType.replacingOccurrences(of: "com.apple.product-type.", with: "")
            }
            var target = ProjectTarget(name: name, kind: kind)
            target.developmentLanguage = developmentLanguage
            if kind == "test" { target.unsupportedReason = "test target" }

            var buildSettings = projectSettings
            buildSettings.merge(settings(item["buildConfigurationList"])) { _, new in new }
            var sdk = buildSettings["SDKROOT"]?.string ?? "iphoneos"
            if sdk == "auto" { sdk = buildSettings["SUPPORTED_PLATFORMS"]?.strings.first ?? "iphoneos" }
            target.platform = sdkPlatforms[sdk.lowercased()] ?? sdkPlatforms.first { sdk.lowercased().hasPrefix($0.key) }?.value ?? "iOS"
            let deploymentKey = ["iOS": "IPHONEOS_DEPLOYMENT_TARGET", "tvOS": "TVOS_DEPLOYMENT_TARGET", "watchOS": "WATCHOS_DEPLOYMENT_TARGET",
                                 "macOS": "MACOSX_DEPLOYMENT_TARGET", "visionOS": "XROS_DEPLOYMENT_TARGET"][target.platform!]!
            target.deploymentTarget = buildSettings[deploymentKey]?.string
            target.swiftVersion = buildSettings["SWIFT_VERSION"]?.string
            var conditions = buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]?.strings ?? ["DEBUG"]
            let flags = buildSettings["OTHER_SWIFT_FLAGS"]?.strings ?? []
            for (i, flag) in flags.enumerated() where flag == "-D" && i + 1 < flags.count { conditions.append(flags[i + 1]) }
            target.compilationConditions = conditions.filter { $0 != "$(inherited)" && !$0.isEmpty }
            let infoPlist = buildSettings["INFOPLIST_FILE"]?.string.map { ProjectFiles.absolute($0, relativeTo: root) }

            var sources: [String] = []
            var resources: [Resource] = []
            func files(of phaseID: Value) -> [String] {
                (object(phaseID)["files"]?.array ?? []).flatMap { buildFileID -> [String] in
                    guard let ref = object(buildFileID)["fileRef"]?.string else { return [] }
                    let refObject = objects[ref]?.dict ?? [:]
                    if refObject["isa"]?.string == "PBXVariantGroup" {
                        return (refObject["children"]?.array ?? []).compactMap { $0.string.flatMap(path(of:)) }
                    }
                    return path(of: ref).map { [$0] } ?? []
                }
            }
            for phaseID in item["buildPhases"]?.array ?? [] {
                switch object(phaseID)["isa"]?.string {
                case "PBXSourcesBuildPhase": sources += files(of: phaseID).filter { $0.hasSuffix(".swift") }
                case "PBXResourcesBuildPhase": resources += files(of: phaseID).map { Resource(path: $0) }
                default: break
                }
            }

            // Synchronized folders: every file in the folder, minus this target's exceptions; and files of
            // folders the target does not include but that an exception set adds to it.
            let ownGroups = Set(item["fileSystemSynchronizedGroups"]?.array.compactMap(\.string) ?? [])
            for groupID in synchronizedGroups {
                guard let directory = path(of: groupID) else { continue }
                let sets = exceptions(of: groupID).filter { $0.target == targetID }
                let listed = Set(sets.flatMap(\.files))
                let members: [String]
                if ownGroups.contains(groupID) {
                    members = ProjectFiles.walk(directory).filter { file in !listed.contains(file) && !listed.contains { file.hasPrefix($0 + "/") } }
                } else if !listed.isEmpty {
                    members = ProjectFiles.walk(directory).filter { file in listed.contains(file) || listed.contains { file.hasPrefix($0 + "/") } }
                } else { continue }
                for file in members {
                    XcodeGenReader.classify(directory + "/" + file, phase: nil, folder: false, infoPlist: infoPlist, sources: &sources, resources: &resources)
                }
            }
            target.sources = Array(Set(sources)).sorted()
            target.resources = resources

            for dependencyID in item["dependencies"]?.array ?? [] {
                let dependency = object(dependencyID)
                if let other = dependency["target"]?.string, let otherName = objects[other]?["name"]?.string {
                    target.dependencies.append(.target(otherName))
                } else if let product = dependency["productRef"]?.string, let productName = objects[product]?["productName"]?.string {
                    target.dependencies.append(.target(productName))
                }
            }
            for productID in item["packageProductDependencies"]?.array ?? [] {
                let product = object(productID)
                guard var productName = product["productName"]?.string else { continue }
                if productName.hasPrefix("plugin:") { continue }   // build tool plugins
                productName = productName.replacingOccurrences(of: "plugin:", with: "")
                if let ref = product["package"]?.string {
                    if let directory = localPackages[ref] { target.dependencies.append(.package(path: directory, product: productName)) }
                    else { target.dependencies.append(.remote(name: productName, location: remotePackages[ref] ?? "remote")) }
                } else if let directory = packageDeclaring(productName) {
                    target.dependencies.append(.package(path: directory, product: productName))
                } else {
                    target.dependencies.append(.remote(name: productName, location: "no local package declares it"))
                }
            }
            targets.append(target)
        }
        if targets.isEmpty { notes.append("no targets found") }
        return Project(format: .xcodeproj, path: xcodeproj, root: root, name: ((xcodeproj as NSString).lastPathComponent as NSString).deletingPathExtension,
                       targets: targets, developmentLanguage: developmentLanguage, notes: notes)
    }
}
