internal import CSkia

// The accessibility outputs of a render: JSON tree, text outline and the tap-target overlay PNG.
// `Renderer.render` calls `AccessibilityOutputs.finish` after the screenshot is written; nothing
// here runs (or touches the canvas) unless one of the runner flags asked for it.

// MARK: - Request / result

struct AccessibilityRequest {
    var treePath: String?
    var tapTargetsPath: String?
    var wantsOutline = false
    var isActive: Bool { treePath != nil || tapTargetsPath != nil || wantsOutline }
}

struct AXIssue {
    var kind: String
    var message: String
    var frame: CGRect
    var label: String
    var identifier: String?
    var related: CGRect?
}

// MARK: - JSON

/// A tiny ordered JSON value, so the output keys come out in a stable, readable order.
indirect enum AXJSON {
    case bool(Bool), int(Int), number(Double), string(String)
    case array([AXJSON]), object([(String, AXJSON)])

    static func num(_ v: CGFloat) -> AXJSON {
        let d = (Double(v) * 100).rounded() / 100
        return d == d.rounded() && abs(d) < 1e9 ? .int(Int(d)) : .number(d)
    }
    static func rect(_ r: CGRect) -> AXJSON {
        .object([("x", num(r.minX)), ("y", num(r.minY)), ("width", num(r.width)), ("height", num(r.height))])
    }

    func render(_ indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent + 1), close = String(repeating: "  ", count: indent)
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .number(let d): return String(d)
        case .string(let s): return AXJSON.quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            if items.allSatisfy({ if case .string = $0 { return true }; return false }) {
                return "[" + items.map { $0.render() }.joined(separator: ", ") + "]"
            }
            return "[\n" + items.map { pad + $0.render(indent + 1) }.joined(separator: ",\n") + "\n" + close + "]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            // Rects and other all-scalar objects stay on one line.
            if pairs.allSatisfy({ if case .int = $0.1 { return true }; if case .number = $0.1 { return true }; return false }) {
                return "{" + pairs.map { AXJSON.quote($0.0) + ": " + $0.1.render() }.joined(separator: ", ") + "}"
            }
            return "{\n" + pairs.map { pad + AXJSON.quote($0.0) + ": " + $0.1.render(indent + 1) }.joined(separator: ",\n") + "\n" + close + "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}

// MARK: - Output

@MainActor
enum AccessibilityOutputs {
    /// Set by the runner's command line.
    static var request = AccessibilityRequest()
    /// What the runner adds to its JSON result line (paths, counts, outline text).
    static var payload: [String: Any] = [:]

    static let minimumTarget: CGFloat = 44

    static func finish(root: Node, config: RenderConfiguration, scheme: ColorScheme, canvasSize: CGSize, scale: CGFloat,
                       painter: Painter, surface: OpaquePointer) throws {
        guard request.isActive else { return }
        let extractor = AXExtractor(screen: CGRect(origin: .zero, size: canvasSize))
        let elements = extractor.extract(root)
        let flat = flatten(elements)
        let issues = findIssues(flat, truncations: extractor.truncations)
        let interactive = flat.filter { $0.element.interactive }.count

        var summary: [String: Any] = ["elements": flat.count, "interactive": interactive, "issues": issues.count]
        if let path = request.treePath {
            let doc = treeJSON(config: config, scheme: scheme, canvasSize: canvasSize, scale: scale, elements: elements, flat: flat,
                               issues: issues, extractor: extractor)
            try write(doc.render() + "\n", to: path)
            payload["accessibilityTree"] = path
        }
        if request.wantsOutline {
            payload["outline"] = outline(elements)
        }
        if let path = request.tapTargetsPath {
            drawTapTargets(flat.map(\.element), painter: painter, canvasSize: canvasSize, scale: scale, scheme: scheme)
            try writePNG(surface: surface, to: path)
            payload["tapTargets"] = path
        }
        summary["byKind"] = Dictionary(issues.map { ($0.kind, 1) }, uniquingKeysWith: +)
        payload["accessibility"] = summary
    }

    // MARK: Flattening

    struct Flat {
        var element: AXElement
        var index: Int
        var parent: Int?
    }

    static func flatten(_ elements: [AXElement]) -> [Flat] {
        var out: [Flat] = []
        func walk(_ list: [AXElement], parent: Int?) {
            for e in list {
                let index = out.count
                out.append(Flat(element: e, index: index, parent: parent))
                walk(e.children, parent: index)
            }
        }
        walk(elements, parent: nil)
        return out
    }

    // MARK: Issues

    static func fmt(_ v: CGFloat) -> String {
        let d = (Double(v) * 10).rounded() / 10
        return d == d.rounded() ? String(Int(d)) : String(d)
    }

    static func findIssues(_ flat: [Flat], truncations: [AXExtractor.Truncation]) -> [AXIssue] {
        var issues: [AXIssue] = []
        func name(_ e: AXElement) -> String { e.label.isEmpty ? "unlabeled \(e.role)" : "\"\(e.label)\"" }
        var ids: [String: [Flat]] = [:]
        for item in flat { if let id = item.element.identifier { ids[id, default: []].append(item) } }

        for item in flat {
            let e = item.element
            if e.interactive, let hit = e.hitFrame, hit.width < minimumTarget - 0.01 || hit.height < minimumTarget - 0.01 {
                issues.append(AXIssue(kind: "smallTarget",
                                      message: "\(name(e)) \(e.role) tap target is \(fmt(hit.width))x\(fmt(hit.height))pt; the minimum is 44x44pt.",
                                      frame: hit, label: e.label, identifier: e.identifier))
            }
            if e.interactive && e.label.isEmpty && e.children.isEmpty {
                issues.append(AXIssue(kind: "missingLabel",
                                      message: "Interactive \(e.role) has no accessibility label; add .accessibilityLabel(...).",
                                      frame: e.frame, label: e.label, identifier: e.identifier))
            } else if e.labelOnlyFromAssetName && e.children.isEmpty && (e.interactive || e.role == "image") {
                issues.append(AXIssue(kind: "imageMissingLabel",
                                      message: "\(e.interactive ? "Interactive image" : "Image") is labelled only by its asset name \"\(e.label)\"; add .accessibilityLabel(...) or use Image(decorative:).",
                                      frame: e.frame, label: e.label, identifier: e.identifier))
            }
            if let id = e.identifier, let group = ids[id], group.count > 1 {
                issues.append(AXIssue(kind: "duplicateIdentifier",
                                      message: "Identifier \"\(id)\" is used by \(group.count) elements.",
                                      frame: e.frame, label: e.label, identifier: id))
            }
        }

        // Overlapping tap targets (not between an element and its own container; visible ones only).
        let targets = flat.filter { $0.element.interactive && !$0.element.offscreen && $0.element.rawHitFrame != nil }
        func isAncestor(_ a: Flat, of b: Flat) -> Bool {
            var cursor = b.parent
            while let c = cursor { if c == a.index { return true }; cursor = flat[c].parent }
            return false
        }
        for (i, a) in targets.enumerated() {
            for b in targets[(i + 1)...] {
                guard let ra = a.element.rawHitFrame, let rb = b.element.rawHitFrame else { continue }
                if isAncestor(a, of: b) || isAncestor(b, of: a) { continue }
                let w = min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX), h = min(ra.maxY, rb.maxY) - max(ra.minY, rb.minY)
                guard w > 0, h > 0 else { continue }
                let area = w * h, smaller = min(ra.width * ra.height, rb.width * rb.height)
                guard area > 4, smaller > 0, area / smaller >= 0.1 else { continue }
                issues.append(AXIssue(kind: "overlappingTargets",
                                      message: "\(name(a.element)) and \(name(b.element)) tap targets overlap by \(fmt(w))x\(fmt(h))pt.",
                                      frame: ra, label: a.element.label, identifier: a.element.identifier, related: rb))
            }
        }

        var seen: Set<String> = []
        for t in truncations {
            let key = "\(t.frame)\(t.text)"
            guard seen.insert(key).inserted else { continue }
            issues.append(AXIssue(kind: "truncatedText",
                                  message: "Text \"\(t.text)\" is cut off by its line limit; allow more lines or shorten it.",
                                  frame: t.frame, label: t.text, identifier: nil))
        }
        return issues
    }

    // MARK: Tree JSON

    static func elementJSON(_ e: AXElement) -> AXJSON {
        var pairs: [(String, AXJSON)] = [("role", .string(e.role)), ("label", .string(e.label))]
        if let v = e.value { pairs.append(("value", .string(v))) }
        if let h = e.hint { pairs.append(("hint", .string(h))) }
        if let id = e.identifier { pairs.append(("identifier", .string(id))) }
        pairs.append(("traits", .array(e.traits.nameList.map { .string($0) })))
        pairs.append(("enabled", .bool(e.enabled)))
        pairs.append(("frame", .rect(e.frame)))
        pairs.append(("interactive", .bool(e.interactive)))
        if e.interactive, let hit = e.hitFrame {
            pairs.append(("hitFrame", .rect(hit)))
            pairs.append(("meetsMinimumSize", .bool(hit.width >= minimumTarget - 0.01 && hit.height >= minimumTarget - 0.01)))
        }
        if e.offscreen { pairs.append(("offscreen", .bool(true))) }
        if e.truncated { pairs.append(("truncated", .bool(true))) }
        if !e.inputLabels.isEmpty { pairs.append(("inputLabels", .array(e.inputLabels.map { .string($0) }))) }
        pairs.append(("actions", .array(e.actions.map { .string($0) })))
        pairs.append(("children", .array(e.children.map(elementJSON))))
        return .object(pairs)
    }

    static func treeJSON(config: RenderConfiguration, scheme: ColorScheme, canvasSize: CGSize, scale: CGFloat,
                         elements: [AXElement], flat: [Flat], issues: [AXIssue], extractor: AXExtractor) -> AXJSON {
        var byRole: [String: Int] = [:]
        for item in flat { byRole[item.element.role, default: 0] += 1 }
        var summary: [(String, AXJSON)] = [
            ("elementCount", .int(flat.count)),
            ("interactiveCount", .int(flat.filter { $0.element.interactive }.count)),
            ("issueCount", .int(issues.count)),
            ("byRole", .object(byRole.sorted { $0.key < $1.key }.map { ($0.key, AXJSON.int($0.value)) })),
        ]
        if !issues.isEmpty {
            var byKind: [String: Int] = [:]
            for i in issues { byKind[i.kind, default: 0] += 1 }
            summary.append(("issuesByKind", .object(byKind.sorted { $0.key < $1.key }.map { ($0.key, AXJSON.int($0.value)) })))
        }
        var doc: [(String, AXJSON)] = [
            ("version", .int(1)),
            ("device", .string(config.device.name)),
            ("size", .object([("width", .num(canvasSize.width)), ("height", .num(canvasSize.height))])),
            ("scale", .num(scale)),
            ("colorScheme", .string(scheme == .dark ? "dark" : "light")),
        ]
        if let kind = extractor.modalKind {
            doc.append(("modal", .object([("kind", .string(kind)), ("obscuredElements", .int(extractor.obscuredCount))])))
        }
        doc.append(("elements", .array(elements.map(elementJSON))))
        doc.append(("summary", .object(summary)))
        doc.append(("issues", .array(issues.map(issueJSON))))
        return .object(doc)
    }

    static func issueJSON(_ i: AXIssue) -> AXJSON {
        var pairs: [(String, AXJSON)] = [("kind", .string(i.kind)), ("message", .string(i.message)), ("frame", .rect(i.frame)),
                                         ("label", .string(i.label))]
        if let id = i.identifier { pairs.append(("identifier", .string(id))) }
        if let r = i.related { pairs.append(("related", .rect(r))) }
        return .object(pairs)
    }

    // MARK: Outline

    static func outline(_ elements: [AXElement]) -> String {
        var lines: [String] = []
        func coord(_ v: CGFloat) -> String { fmt(v) }
        func walk(_ list: [AXElement], depth: Int) {
            for e in list {
                var line = String(repeating: "  ", count: depth) + e.role
                if !e.label.isEmpty || e.children.isEmpty { line += " " + AXJSON.quote(e.label) }
                if let v = e.value { line += " value=" + AXJSON.quote(v) }
                if let id = e.identifier { line += " id=" + AXJSON.quote(id) }
                if let h = e.hint { line += " hint=" + AXJSON.quote(h) }
                if e.traits.contains(.selected) { line += " selected" }
                if e.traits.contains(.hasPopup) { line += " popup" }
                if e.traits.contains(.modal) { line += " modal" }
                if !e.enabled { line += " disabled" }
                if e.offscreen { line += " offscreen" }
                if e.truncated { line += " truncated" }
                line += " (\(coord(e.frame.minX)),\(coord(e.frame.minY)) \(coord(e.frame.width))x\(coord(e.frame.height)))"
                lines.append(line)
                walk(e.children, depth: depth + 1)
            }
        }
        walk(elements, depth: 0)
        return lines.joined(separator: "\n")
    }

    // MARK: Tap-target overlay

    static func drawTapTargets(_ elements: [AXElement], painter p: Painter, canvasSize: CGSize, scale: CGFloat, scheme: ColorScheme) {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        p.fill(Path(bounds), with: .color(RGBA(0, 0, 0, 0.5)), in: bounds)
        let green = RGBA(0.20, 0.80, 0.40, 1), red = RGBA(1.0, 0.27, 0.23, 1)
        let targets = elements.filter { $0.interactive && !$0.offscreen && $0.hitFrame != nil }
            .sorted { ($0.hitFrame!.width * $0.hitFrame!.height) > ($1.hitFrame!.width * $1.hitFrame!.height) }
        var env = EnvironmentValues()
        env.colorScheme = scheme
        env.displayScale = scale
        let ctx = PlaceContext(origin: .zero, container: bounds, safeRect: bounds, scale: scale)
        for e in targets {
            let r = e.hitFrame!
            let ok = r.width >= minimumTarget - 0.01 && r.height >= minimumTarget - 0.01
            let color = ok ? green : red
            let path = Path(roundedRect: r, cornerRadius: min(6, min(r.width, r.height) / 4), style: .continuous)
            p.fill(path, with: .color(color.opacity(0.28)), in: r)
            p.stroke(path, with: .color(color.opacity(0.95)), style: StrokeStyle(lineWidth: 1.5), in: r)
            guard !ok else { continue }
            let text = Text(verbatim: "\(Int(r.width.rounded()))x\(Int(r.height.rounded()))")
                .font(.system(size: 10, weight: .bold)).foregroundColor(.white).makeNode(env)
            let size = text.sizeThatFits(.unspecified)
            let pill = CGRect(x: min(max(2, r.minX), max(2, bounds.width - size.width - 10)),
                              y: r.minY - size.height - 3 >= 0 ? r.minY - size.height - 3 : r.maxY + 1,
                              width: size.width + 8, height: size.height + 2)
            p.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2, style: .circular), with: .color(red), in: pill)
            text.place(at: CGPoint(x: pill.minX + 4, y: pill.minY + 1), size: size, ctx)
            text.draw(p)
        }
    }

    // MARK: Files

    static func write(_ contents: String, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        do { try contents.write(toFile: path, atomically: true, encoding: .utf8) } catch {
            throw RenderError("Could not write \(path): \(error.localizedDescription)")
        }
    }

    static func writePNG(surface: OpaquePointer, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        guard let image = sk_surface_new_image_snapshot(surface) else { throw RenderError("Could not snapshot the surface") }
        defer { sk_image_unref(image) }
        let pixmap = sk_pixmap_new()
        defer { sk_pixmap_destructor(pixmap) }
        guard sk_image_peek_pixels(image, pixmap) else { throw RenderError("Could not read back pixels") }
        guard let stream = sk_filewstream_new(path), sk_filewstream_is_valid(stream) else {
            throw RenderError("Could not open \(path) for writing")
        }
        var options = sk_pngencoder_options_t(fFilterFlags: ALL_SK_PNGENCODER_FILTER_FLAGS, fZLibLevel: 6, fComments: nil, fGainmap: nil, fGainmapInfo: nil)
        let ok = sk_pngencoder_encode(stream, pixmap, &options)
        sk_filewstream_destroy(stream)
        guard ok else { throw RenderError("PNG encoding failed") }
    }
}
