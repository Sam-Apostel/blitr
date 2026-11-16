import Foundation

// Resources in project mode:
//   - a module's resources are staged (as symlinks) in a cache directory that serves as its
//     `Bundle.module` (SwiftPM targets) or sits next to the runner as `Bundle.main` (app targets);
//   - fonts among them are handed to the renderer, so `Font.custom("Name", size:)` finds them;
//   - asset catalogs are handed to the renderer, and Swift symbols are generated for their colors and
//     images (`ColorResource.name`, `Color.name`, `ImageResource.name`) as Xcode does;
//   - string catalogs (.xcstrings) and `.strings` files are flattened into one table for the chosen
//     locale, which the renderer reads (BLITR_STRINGS).

enum ProjectResources {
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    /// Files of a resource entry as they appear in a bundle (relative path -> source path).
    /// `.process` flattens directories (keeping `.lproj` folders); `.copy` keeps the structure.
    static func bundleLayout(_ resources: [Resource]) -> [String: String] {
        var layout: [String: String] = [:]
        for resource in resources {
            let name = (resource.path as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            if !ProjectFiles.isDirectory(resource.path) || resource.rule == .copy || ext == "lproj" || ext == "xcassets" {
                layout[name] = resource.path
                continue
            }
            for file in ProjectFiles.walk(resource.path) {
                let parts = file.split(separator: "/")
                if let lproj = parts.firstIndex(where: { $0.hasSuffix(".lproj") }) {
                    layout[parts[lproj...].joined(separator: "/")] = resource.path + "/" + file
                } else {
                    layout[(file as NSString).lastPathComponent] = resource.path + "/" + file
                }
            }
        }
        return layout
    }

    /// Stages a module's resources as symlinks in a directory keyed by their paths. Returns the directory.
    static func stage(_ resources: [Resource], module: String) -> String? {
        guard !resources.isEmpty else { return nil }
        let layout = bundleLayout(resources)
        let key = hash(layout.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] })
        let directory = ModuleBuilder.cacheRoot + "/resources/\(module)-\(key)"
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory + "/.complete") {
            try? fm.removeItem(atPath: directory)
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, source) in layout {
                let destination = directory + "/" + name
                try? fm.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
            }
            fm.createFile(atPath: directory + "/.complete", contents: Data())
        }
        return directory
    }

    static func containsFonts(_ resources: [Resource]) -> Bool {
        bundleLayout(resources).keys.contains { fontExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// Asset catalogs among the resources (they may also sit inside a resource folder).
    static func assetCatalogs(_ resources: [Resource]) -> [String] {
        var catalogs: [String] = []
        for resource in resources {
            if resource.path.hasSuffix(".xcassets") { catalogs.append(resource.path); continue }
            guard ProjectFiles.isDirectory(resource.path) else { continue }
            catalogs += ProjectFiles.walk(resource.path).filter { $0.hasSuffix(".xcassets") }.map { resource.path + "/" + $0 }
        }
        return catalogs
    }

    /// Loose images among the resources (outside catalogs), for `Image("name")` and `UIImage(named:)`.
    static func hasLooseImages(_ resources: [Resource]) -> Bool {
        bundleLayout(resources).keys.contains { ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(($0 as NSString).pathExtension.lowercased()) }
    }

    // MARK: Asset symbols

    struct AssetNames {
        var colors: [String] = []
        var images: [String] = []
    }

    static func assetNames(_ catalogs: [String]) -> AssetNames {
        var names = AssetNames()
        for catalog in catalogs {
            guard let walker = FileManager.default.enumerator(atPath: catalog) else { continue }
            for case let relative as String in walker {
                let last = (relative as NSString).lastPathComponent
                if last.hasSuffix(".colorset") { names.colors.append((last as NSString).deletingPathExtension) }
                if last.hasSuffix(".imageset") { names.images.append((last as NSString).deletingPathExtension) }
            }
        }
        names.colors = Array(Set(names.colors)).sorted()
        names.images = Array(Set(names.images)).sorted()
        return names
    }

    static let swiftKeywords: Set<String> = ["class", "default", "func", "import", "in", "is", "let", "var", "return", "self", "struct",
                                             "switch", "case", "enum", "extension", "for", "if", "while", "do", "init", "internal", "private",
                                             "public", "protocol", "static", "super", "true", "false", "nil", "where", "as", "try", "throw"]

    /// Xcode's symbol name for an asset: lower camel case, without a trailing "Color"/"Image".
    static func symbolName(_ asset: String, suffix: String) -> String? {
        let words = asset.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        guard !words.isEmpty else { return nil }
        var name = words.enumerated().map { i, w in
            i == 0 ? (w.prefix(while: { $0.isUppercase }).count > 1 && w.count > 1 && w.allSatisfy({ $0.isUppercase || $0.isNumber })
                      ? w.lowercased() : w.prefix(1).lowercased() + w.dropFirst())
                   : w.prefix(1).uppercased() + w.dropFirst()
        }.joined()
        if name.hasSuffix(suffix), name.count > suffix.count { name.removeLast(suffix.count) }
        if name.first?.isNumber == true { name = "_" + name }
        return swiftKeywords.contains(name) ? "`\(name)`" : name
    }

    /// `GeneratedAssetSymbols.swift` for a module: static members on ColorResource/ImageResource, plus
    /// `Color.name` / `ShapeStyle.name` shorthands, skipping names the module already declares.
    static func assetSymbols(_ catalogs: [String], bundle: String, declared: Set<String>) -> String? {
        let names = assetNames(catalogs)
        guard !names.colors.isEmpty || !names.images.isEmpty else { return nil }
        var colors: [(String, String)] = []
        var images: [(String, String)] = []
        var used: Set<String> = []
        for asset in names.colors { if let s = symbolName(asset, suffix: "Color"), used.insert("c" + s).inserted { colors.append((s, asset)) } }
        for asset in names.images { if let s = symbolName(asset, suffix: "Image"), used.insert("i" + s).inserted { images.append((s, asset)) } }
        func literal(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        var out = "// Generated by blitr from the module's asset catalogs, as Xcode does.\nimport Foundation\nimport SwiftUI\n\n"
        out += "private let __assetBundle: Bundle = \(bundle)\n\n"
        if !colors.isEmpty {
            out += "extension ColorResource {\n"
            for (s, asset) in colors { out += "    static let \(s) = ColorResource(name: \(literal(asset)), bundle: __assetBundle)\n" }
            out += "}\n\n"
            let shorthand = colors.filter { !declared.contains($0.0.trimmingCharacters(in: CharacterSet(charactersIn: "`"))) }
            if !shorthand.isEmpty {
                out += "extension Color {\n"
                for (s, _) in shorthand { out += "    static var \(s): Color { Color(ColorResource.\(s)) }\n" }
                out += "}\n\nextension ShapeStyle where Self == Color {\n"
                for (s, _) in shorthand { out += "    static var \(s): Color { Color(ColorResource.\(s)) }\n" }
                out += "}\n\n"
            }
        }
        if !images.isEmpty {
            out += "extension ImageResource {\n"
            for (s, asset) in images { out += "    static let \(s) = ImageResource(name: \(literal(asset)), bundle: __assetBundle)\n" }
            out += "}\n"
        }
        return out
    }

    static func bundleAccessor(_ directory: String) -> String {
        "// Generated by blitr, as SwiftPM does for targets with resources.\nimport Foundation\n\n"
            + "extension Foundation.Bundle {\n    static let module: Bundle = Bundle(path: \"\(directory)\") ?? Bundle.main\n}\n"
    }

    // MARK: Strings

    /// Candidate localization names for a locale identifier, most specific first ("nl-BE" -> nl-BE, nl_BE, nl).
    static func localeCandidates(_ locale: String) -> [String] {
        let normalized = locale.replacingOccurrences(of: "_", with: "-")
        var result = [normalized, normalized.replacingOccurrences(of: "-", with: "_")]
        let parts = normalized.split(separator: "-")
        if parts.count > 1 { result.append(parts.dropLast().joined(separator: "-")) }
        if let language = parts.first { result.append(String(language)) }
        var seen: Set<String> = []
        return result.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Every string catalog and `.strings` file among the resources.
    static func stringFiles(_ resources: [Resource]) -> (catalogs: [String], strings: [String]) {
        var catalogs: [String] = [], strings: [String] = []
        for resource in resources {
            let paths = ProjectFiles.isDirectory(resource.path) && !resource.path.hasSuffix(".lproj")
                ? ProjectFiles.walk(resource.path).map { resource.path + "/" + $0 } : [resource.path]
            for path in paths {
                if path.hasSuffix(".xcstrings") { catalogs.append(path) }
                else if path.hasSuffix(".lproj"), ProjectFiles.isDirectory(path) {
                    strings += ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { $0.hasSuffix(".strings") }.map { path + "/" + $0 }
                } else if path.hasSuffix(".strings"), path.contains(".lproj/") { strings.append(path) }
            }
        }
        return (catalogs, strings)
    }

    /// Languages the catalogs and `.lproj` folders provide.
    static func languages(_ resources: [Resource]) -> Set<String> {
        let (catalogs, strings) = stringFiles(resources)
        var result: Set<String> = []
        for catalog in catalogs {
            guard let data = FileManager.default.contents(atPath: catalog),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let source = json["sourceLanguage"] as? String { result.insert(source) }
            for (_, entry) in json["strings"] as? [String: Any] ?? [:] {
                for language in ((entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]).keys { result.insert(language) }
            }
        }
        for file in strings {
            if let lproj = file.split(separator: "/").last(where: { $0.hasSuffix(".lproj") }) { result.insert(String(lproj.dropLast(6))) }
        }
        return result
    }

    /// key -> localized value for `locale`. Keys without a translation fall back to the source language.
    static func table(_ resources: [Resource], locale: String) -> [String: String] {
        let candidates = localeCandidates(locale)
        var table: [String: String] = [:]
        let (catalogs, strings) = stringFiles(resources)
        // .strings: the most specific matching .lproj wins.
        for candidate in candidates.reversed() {
            for file in strings where file.contains("/\(candidate).lproj/") {
                for (key, value) in parseStrings(file) { table[key] = value }
            }
        }
        for catalog in catalogs {
            guard let data = FileManager.default.contents(atPath: catalog),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let source = json["sourceLanguage"] as? String ?? "en"
            for (key, rawEntry) in json["strings"] as? [String: Any] ?? [:] {
                let localizations = (rawEntry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
                var value: String?
                for candidate in candidates {
                    if let match = localizations.first(where: { $0.key.lowercased() == candidate.lowercased() }) { value = catalogValue(match.value); break }
                }
                var chosen: Any?
                for candidate in candidates {
                    if let match = localizations.first(where: { $0.key.lowercased() == candidate.lowercased() }) { chosen = match.value; break }
                }
                if value == nil { value = localizations[source].flatMap(catalogValue); chosen = localizations[source] }
                if let value { table[key] = value }
                // Plural variants ride along under "key<separator>category"; the renderer picks one by the number shown.
                if let plural = ((chosen as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    for (category, variant) in plural {
                        if let text = catalogValue(variant) { table[key + "\u{1}" + category] = text }
                    }
                }
            }
        }
        return table
    }

    /// The value of one localization: a plain string unit, or the "other" case of plural/device variations.
    static func catalogValue(_ localization: Any) -> String? {
        guard let dict = localization as? [String: Any] else { return nil }
        if let unit = dict["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return value }
        if let variations = dict["variations"] as? [String: Any] {
            for (_, cases) in variations {
                guard let cases = cases as? [String: Any] else { continue }
                if let other = cases["other"] ?? cases.values.first, let value = catalogValue(other) { return value }
            }
        }
        if let substitutions = dict["substitutions"] as? [String: Any], substitutions.isEmpty == false { return nil }
        return nil
    }

    /// Parses an old-style `.strings` file: `"key" = "value";` with comments.
    static func parseStrings(_ path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        var text = String(decoding: data, as: UTF8.self)
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) ?? text }
        var result: [String: String] = [:]
        let chars = Array(text)
        var i = 0
        func skip() {
            while i < chars.count {
                if chars[i].isWhitespace { i += 1; continue }
                if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2; continue
                }
                if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" { while i < chars.count, chars[i] != "\n" { i += 1 }; continue }
                break
            }
        }
        func string() -> String? {
            skip()
            guard i < chars.count else { return nil }
            if chars[i] != "\"" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "." { i += 1 }
                return i > start ? String(chars[start..<i]) : nil
            }
            i += 1
            var out = ""
            while i < chars.count, chars[i] != "\"" {
                if chars[i] == "\\", i + 1 < chars.count {
                    i += 1
                    switch chars[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "U", "u":
                        let hex = String(chars[(i + 1)..<min(i + 5, chars.count)])
                        if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) { out.append(Character(scalar)); i += 4 }
                    default: out.append(chars[i])
                    }
                } else { out.append(chars[i]) }
                i += 1
            }
            i += 1
            return out
        }
        while i < chars.count {
            guard let key = string() else { break }
            skip()
            guard i < chars.count, chars[i] == "=" else { break }
            i += 1
            guard let value = string() else { break }
            skip()
            if i < chars.count, chars[i] == ";" { i += 1 }
            result[key] = value
        }
        return result
    }
}
