// Foundation API that Apple platforms have and swift-corelibs-foundation lacks, which app code uses
// next to SwiftUI: URLCache's directory initializer, app group containers, RelativeDateTimeFormatter,
// ListFormatter, Markdown parsing into AttributedString, URLSession byte streams, iCloud key-value store.
// Apple's Foundation has every one of them, so on Darwin the whole file compiles out.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if !canImport(Darwin)

extension URLCache {
    public convenience init(memoryCapacity: Int, diskCapacity: Int, directory: URL? = nil) {
        self.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: directory?.path)
    }
}

extension FileManager {
    /// A writable directory per app group, under the temporary directory, shared by everything in this process.
    public func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swiftui-screenshot-app-groups")
            .appendingPathComponent(groupIdentifier, isDirectory: true)
        try? createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension ProcessInfo {
    public enum ThermalState: Int, Sendable { case nominal, fair, serious, critical }
    public var thermalState: ThermalState { .nominal }
    public static let thermalStateDidChangeNotification = Notification.Name("NSProcessInfoThermalStateDidChangeNotification")
    public var isLowPowerModeEnabled: Bool { false }
    public var isiOSAppOnMac: Bool { false }
    public var isMacCatalystApp: Bool { false }
}
extension Notification.Name {
    public static let NSProcessInfoPowerStateDidChange = Notification.Name("NSProcessInfoPowerStateDidChangeNotification")
}

// MARK: - RelativeDateTimeFormatter (English)

open class RelativeDateTimeFormatter: Formatter, @unchecked Sendable {
    public enum DateTimeStyle: Int, Sendable { case numeric, named }
    public enum UnitsStyle: Int, Sendable { case full, spellOut, short, abbreviated }
    public enum Context: Int, Sendable { case unknown, dynamic, standalone, listItem, beginningOfSentence, middleOfSentence }
    open var dateTimeStyle = DateTimeStyle.numeric
    open var unitsStyle = UnitsStyle.full
    open var formattingContext = Context.unknown
    open var calendar: Calendar! = .current
    open var locale: Locale! = .current

    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open func localizedString(for date: Date, relativeTo referenceDate: Date) -> String {
        localizedString(fromTimeInterval: date.timeIntervalSince(referenceDate))
    }
    open func localizedString(fromTimeInterval timeInterval: TimeInterval) -> String {
        let seconds = timeInterval
        let magnitude = abs(seconds)
        let units: [(Double, String, String)] = [(31_536_000, "year", "yr."), (2_592_000, "month", "mo."), (604_800, "week", "wk."),
                                                  (86_400, "day", "day"), (3_600, "hour", "hr."), (60, "minute", "min."), (1, "second", "sec.")]
        let (size, name, short) = units.first { magnitude >= $0.0 } ?? (1, "second", "sec.")
        let count = Int((magnitude / size).rounded(.down))
        var text: String
        if dateTimeStyle == .named {
            if magnitude < 1 { return capitalise("now") }
            if name == "day", count == 1 { return capitalise(seconds < 0 ? "yesterday" : "tomorrow") }
            if count == 1, ["week", "month", "year"].contains(name) { return capitalise(seconds < 0 ? "last \(name)" : "next \(name)") }
        }
        switch unitsStyle {
        case .full, .spellOut: text = "\(count) \(name)\(count == 1 ? "" : "s")"
        case .short: text = "\(count) \(short)"
        case .abbreviated: text = "\(count)\(short.prefix(1) == "m" && name == "minute" ? "m" : String(short.prefix(1)))"
        }
        text = seconds < 0 ? "\(text) ago" : "in \(text)"
        return capitalise(text)
    }
    private func capitalise(_ s: String) -> String {
        formattingContext == .beginningOfSentence || formattingContext == .standalone ? s.prefix(1).uppercased() + s.dropFirst() : s
    }
    open override func string(for obj: Any?) -> String? {
        (obj as? Date).map { localizedString(for: $0, relativeTo: Date()) }
    }
}

// MARK: - ListFormatter (English)

open class ListFormatter: Formatter, @unchecked Sendable {
    open var locale: Locale! = .current
    open var itemFormatter: Formatter?
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open class func localizedString(byJoining strings: [String]) -> String { ListFormatter().string(from: strings) ?? "" }
    open func string(from items: [Any]) -> String? {
        let strings = items.map { itemFormatter?.string(for: $0) ?? "\($0)" }
        switch strings.count {
        case 0: return ""
        case 1: return strings[0]
        case 2: return "\(strings[0]) and \(strings[1])"
        default: return strings.dropLast().joined(separator: ", ") + ", and " + strings.last!
        }
    }
    open override func string(for obj: Any?) -> String? { (obj as? [Any]).flatMap(string(from:)) }
}

// MARK: - Markdown

extension AttributedString {
    public struct MarkdownParsingOptions: Hashable, Sendable {
        public enum InterpretedSyntax: Hashable, Sendable { case full, inlineOnly, inlineOnlyPreservingWhitespace }
        public enum FailurePolicy: Hashable, Sendable { case throwError, returnPartiallyParsedIfPossible }
        public var allowsExtendedAttributes = false
        public var interpretedSyntax = InterpretedSyntax.full
        public var failurePolicy = FailurePolicy.throwError
        public var languageCode: String?
        public var appliesSourcePositionAttributes = false
        public init(allowsExtendedAttributes: Bool = false, interpretedSyntax: InterpretedSyntax = .full,
                    failurePolicy: FailurePolicy = .throwError, languageCode: String? = nil) {
            self.allowsExtendedAttributes = allowsExtendedAttributes
            self.interpretedSyntax = interpretedSyntax
            self.failurePolicy = failurePolicy
            self.languageCode = languageCode
        }
        public init(allowsExtendedAttributes: Bool = false, interpretedSyntax: InterpretedSyntax = .full, failurePolicy: FailurePolicy = .throwError,
                    languageCode: String? = nil, appliesSourcePositionAttributes: Bool) {
            self.init(allowsExtendedAttributes: allowsExtendedAttributes, interpretedSyntax: interpretedSyntax, failurePolicy: failurePolicy, languageCode: languageCode)
            self.appliesSourcePositionAttributes = appliesSourcePositionAttributes
        }
    }

    /// Inline Markdown: the markers of strong, emphasis, code and strikethrough are removed and their runs get an
    /// `inlinePresentationIntent` (stronglyEmphasized, emphasized, code, strikethrough), and links get their `link`
    /// attribute (with `baseURL` for relative ones). With `.full`, block markers (headings, list bullets, quotes) are
    /// removed, paragraphs joined by newlines, and each line's run gets its `presentationIntent`.
    public init(markdown: String, options: MarkdownParsingOptions = MarkdownParsingOptions(), baseURL: URL? = nil) throws {
        var source = markdown
        if options.interpretedSyntax == .full {
            source = markdown.components(separatedBy: "\n").map { line -> String in
                var l = Substring(line)
                while l.first == " " { l = l.dropFirst() }
                for marker in ["###### ", "##### ", "#### ", "### ", "## ", "# ", "> ", "- ", "* ", "+ "] where l.hasPrefix(marker) { return String(l.dropFirst(marker.count)) }
                return String(l)
            }.joined(separator: "\n")
        } else if options.interpretedSyntax == .inlineOnly {
            source = source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        self = MarkdownInline.parse(source, baseURL: baseURL)
        if options.interpretedSyntax == .full { MarkdownInline.applyBlocks(markdown, to: &self) }
    }
    public init<S: AttributeScope>(markdown: String, including scope: KeyPath<AttributeScopes, S.Type>,
                                   options: MarkdownParsingOptions = MarkdownParsingOptions(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, options: options, baseURL: baseURL)
    }
    public init<S: AttributeScope>(markdown: String, including scope: S.Type,
                                   options: MarkdownParsingOptions = MarkdownParsingOptions(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, options: options, baseURL: baseURL)
    }
    public init(markdown: Data, options: MarkdownParsingOptions = MarkdownParsingOptions(), baseURL: URL? = nil) throws {
        try self.init(markdown: String(decoding: markdown, as: UTF8.self), options: options, baseURL: baseURL)
    }
}

enum MarkdownInline {
    static func parse(_ text: String, baseURL: URL?, intent: InlinePresentationIntent = []) -> AttributedString {
        var result = AttributedString()
        func styled(_ s: String, _ intent: InlinePresentationIntent) -> AttributedString {
            var a = AttributedString(s)
            if !intent.isEmpty { a.inlinePresentationIntent = intent }
            return a
        }
        let chars = Array(text)
        var i = 0
        var plain = ""
        func flush() { if !plain.isEmpty { result += styled(plain, intent); plain = "" } }
        func find(_ marker: [Character], from start: Int) -> Int? {
            var j = start
            while j + marker.count <= chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if Array(chars[j..<(j + marker.count)]) == marker { return j }
                j += 1
            }
            return nil
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!~".contains(chars[i + 1]) {
                plain.append(chars[i + 1]); i += 2; continue
            }
            if c == "`", let end = find(["`"], from: i + 1) {
                flush()
                result += styled(String(chars[(i + 1)..<end]), intent.union(.code))
                i = end + 1; continue
            }
            if c == "[", let close = find(["]"], from: i + 1), close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find([")"], from: close + 2) {
                flush()
                var label = parse(String(chars[(i + 1)..<close]), baseURL: baseURL, intent: intent)
                let target = String(chars[(close + 2)..<paren]).trimmingCharacters(in: .whitespaces)
                label.link = URL(string: target, relativeTo: baseURL)
                result += label
                i = paren + 1; continue
            }
            var consumed = false
            // Emphasis markers are removed; the run records them as inline presentation intents.
            for marker in [["*", "*"], ["_", "_"], ["~", "~"], ["*"], ["_"], ["~"]]
            where Array(chars[i..<min(chars.count, i + marker.count)]) == marker.map(Character.init) {
                let m = marker.map(Character.init)
                let opensWord = i + m.count < chars.count && !chars[i + m.count].isWhitespace
                if opensWord, let end = find(m, from: i + m.count), end > i + m.count {
                    flush()
                    let added: InlinePresentationIntent = m[0] == "~" ? .strikethrough : m.count == 2 ? .stronglyEmphasized : .emphasized
                    result += parse(String(chars[(i + m.count)..<end]), baseURL: baseURL, intent: intent.union(added))
                    i = end + m.count
                    consumed = true
                    break
                }
            }
            if consumed { continue }
            plain.append(c)
            i += 1
        }
        flush()
        return result
    }

    /// Block intents for `.full` Markdown: the n-th line of the parsed text came from the n-th source line.
    static func applyBlocks(_ markdown: String, to result: inout AttributedString) {
        var kinds: [PresentationIntent?] = []
        var identity = 0
        var paragraph: PresentationIntent?, list: PresentationIntent?
        var ordinal = 0
        func next() -> Int { identity += 1; return identity }
        for line in markdown.components(separatedBy: "\n") {
            let l = line.drop(while: { $0 == " " })
            if l.isEmpty { paragraph = nil; list = nil; kinds.append(nil); continue }
            if let level = ["# ", "## ", "### ", "#### ", "##### ", "###### "].firstIndex(where: { l.hasPrefix($0) }) {
                kinds.append(PresentationIntent(.header(level: level + 1), identity: next()))
                paragraph = nil; list = nil
            } else if ["- ", "* ", "+ "].contains(where: { l.hasPrefix($0) }) {
                if list == nil { list = PresentationIntent(.unorderedList, identity: next()); ordinal = 0 }
                ordinal += 1
                let item = PresentationIntent(.listItem(ordinal: ordinal), identity: next(), parent: list)
                kinds.append(PresentationIntent(.paragraph, identity: next(), parent: item))
                paragraph = nil
            } else if l.hasPrefix("> ") {
                let quote = PresentationIntent(.blockQuote, identity: next())
                kinds.append(PresentationIntent(.paragraph, identity: next(), parent: quote))
                paragraph = nil; list = nil
            } else {
                if paragraph == nil { paragraph = PresentationIntent(.paragraph, identity: next()) }
                kinds.append(paragraph)
                list = nil
            }
        }
        var line = 0
        var start = result.startIndex
        var index = result.startIndex
        func apply(_ end: AttributedString.Index) {
            if line < kinds.count, let intent = kinds[line], start < end { result[start..<end].presentationIntent = intent }
        }
        while index < result.endIndex {
            let after = result.characters.index(after: index)
            if result.characters[index] == "\n" {
                apply(after)
                line += 1
                start = after
            }
            index = after
        }
        apply(result.endIndex)
    }
}

// MARK: - URLSession byte streams

#if canImport(FoundationNetworking)
extension URLSession {
    /// The response's bytes, fetched in full first (no streaming here), then iterated.
    public struct AsyncBytes: AsyncSequence, Sendable {
        public typealias Element = UInt8
        let data: Data
        public struct AsyncIterator: AsyncIteratorProtocol {
            var index: Data.Index
            let data: Data
            public mutating func next() async throws -> UInt8? {
                guard index < data.endIndex else { return nil }
                defer { index = data.index(after: index) }
                return data[index]
            }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(index: data.startIndex, data: data) }
        /// The bytes decoded as UTF-8 and split into lines.
        public var lines: AsyncLineSequence { AsyncLineSequence(text: String(decoding: data, as: UTF8.self)) }
        public var characters: AsyncStream<Character> {
            let text = String(decoding: data, as: UTF8.self)
            return AsyncStream { continuation in text.forEach { continuation.yield($0) }; continuation.finish() }
        }
    }
    public struct AsyncLineSequence: AsyncSequence, Sendable {
        public typealias Element = String
        let text: String
        public struct AsyncIterator: AsyncIteratorProtocol {
            var lines: [String]
            public mutating func next() async throws -> String? { lines.isEmpty ? nil : lines.removeFirst() }
        }
        public func makeAsyncIterator() -> AsyncIterator {
            var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            if lines.last == "" { lines.removeLast() }
            return AsyncIterator(lines: lines)
        }
    }

    public func bytes(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (AsyncBytes, URLResponse) {
        let (data, response) = try await data(from: url)
        return (AsyncBytes(data: data), response)
    }
    public func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (AsyncBytes, URLResponse) {
        let (data, response) = try await data(for: request)
        return (AsyncBytes(data: data), response)
    }
}
#endif

// MARK: - iCloud key-value store (in memory)

open class NSUbiquitousKeyValueStore: NSObject, @unchecked Sendable {
    public static let `default` = NSUbiquitousKeyValueStore()
    public static let didChangeExternallyNotification = Notification.Name("NSUbiquitousKeyValueStoreDidChangeExternallyNotification")
    public static let changeReasonKey = "NSUbiquitousKeyValueStoreChangeReasonKey"
    public static let changedKeysKey = "NSUbiquitousKeyValueStoreChangedKeysKey"
    private var values: [String: Any] = [:]
    private let lock = NSLock()
    public override init() { super.init() }
    open var dictionaryRepresentation: [String: Any] { lock.lock(); defer { lock.unlock() }; return values }
    open func object(forKey key: String) -> Any? { lock.lock(); defer { lock.unlock() }; return values[key] }
    open func set(_ value: Any?, forKey key: String) { lock.lock(); values[key] = value; lock.unlock() }
    open func removeObject(forKey key: String) { set(nil, forKey: key) }
    open func string(forKey key: String) -> String? { object(forKey: key) as? String }
    open func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    open func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    open func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    open func longLong(forKey key: String) -> Int64 { (object(forKey: key) as? NSNumber)?.int64Value ?? (object(forKey: key) as? Int64) ?? 0 }
    open func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? (object(forKey: key) as? Double) ?? 0 }
    open func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? (object(forKey: key) as? Bool) ?? false }
    open func set(_ value: Int64, forKey key: String) { set(value as Any, forKey: key) }
    open func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
    open func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
    @discardableResult open func synchronize() -> Bool { true }
}

#if canImport(FoundationNetworking)
extension URLSessionConfiguration {
    /// Background sessions do not relaunch anything here; the setting is accepted and ignored.
    public var sessionSendsLaunchEvents: Bool {
        get { false }
        set {}
    }
}
#endif
#endif
