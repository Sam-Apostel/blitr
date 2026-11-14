// Foundation's Markdown attributes, which swift-foundation declares only on Apple platforms:
// InlinePresentationIntent, PresentationIntent and their AttributedString keys in the Foundation scope
// (`run.inlinePresentationIntent`, `a.presentationIntent`). AttributedString(markdown:) sets them.
import Foundation

/// Inline Markdown styling of a run: emphasis, strong emphasis, code, strikethrough, breaks and HTML.
public struct InlinePresentationIntent: OptionSet, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
    public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
    public static let code = InlinePresentationIntent(rawValue: 1 << 2)
    public static let strikethrough = InlinePresentationIntent(rawValue: 1 << 5)
    public static let softBreak = InlinePresentationIntent(rawValue: 1 << 6)
    public static let lineBreak = InlinePresentationIntent(rawValue: 1 << 7)
    public static let inlineHTML = InlinePresentationIntent(rawValue: 1 << 8)
    public static let blockHTML = InlinePresentationIntent(rawValue: 1 << 9)
    public var description: String {
        let names: [(InlinePresentationIntent, String)] = [(.emphasized, "emphasized"), (.stronglyEmphasized, "stronglyEmphasized"), (.code, "code"),
            (.strikethrough, "strikethrough"), (.softBreak, "softBreak"), (.lineBreak, "lineBreak"), (.inlineHTML, "inlineHTML"), (.blockHTML, "blockHTML")]
        return names.filter { contains($0.0) }.map(\.1).joined(separator: ", ")
    }
}

/// The block structure of a run (paragraph, header, list item, ...), innermost first.
public struct PresentationIntent: Hashable, Codable, Sendable, CustomDebugStringConvertible {
    public struct TableColumn: Hashable, Codable, Sendable {
        public enum Alignment: Int, Hashable, Codable, Sendable { case left, center, right }
        public var alignment: Alignment
        public init(alignment: Alignment) { self.alignment = alignment }
    }
    public enum Kind: Hashable, Codable, Sendable, CustomDebugStringConvertible {
        case paragraph
        case header(level: Int)
        case orderedList
        case unorderedList
        case listItem(ordinal: Int)
        case codeBlock(languageHint: String?)
        case blockQuote
        case thematicBreak
        case table(columns: [TableColumn])
        case tableHeaderRow
        case tableRow(rowIndex: Int)
        case tableCell(columnIndex: Int)
        public var debugDescription: String {
            switch self {
            case .paragraph: return "paragraph"
            case .header(let level): return "header \(level)"
            case .orderedList: return "orderedList"
            case .unorderedList: return "unorderedList"
            case .listItem(let ordinal): return "listItem \(ordinal)"
            case .codeBlock(let hint): return "codeBlock '\(hint ?? "")'"
            case .blockQuote: return "blockQuote"
            case .thematicBreak: return "thematicBreak"
            case .table: return "table"
            case .tableHeaderRow: return "tableHeaderRow"
            case .tableRow(let index): return "tableRow \(index)"
            case .tableCell(let index): return "tableCell \(index)"
            }
        }
    }
    public struct IntentType: Hashable, Codable, Sendable, CustomDebugStringConvertible {
        public var kind: Kind
        public var identity: Int
        public init(kind: Kind, identity: Int) { self.kind = kind; self.identity = identity }
        public var debugDescription: String { "\(kind.debugDescription) (id \(identity))" }
    }
    public var components: [IntentType]
    public init() { components = [] }
    public init(_ kind: Kind, identity: Int, parent: PresentationIntent? = nil) {
        components = [IntentType(kind: kind, identity: identity)] + (parent?.components ?? [])
    }
    public init(types: [IntentType]) { components = types }
    public var indentationLevel: Int {
        components.filter { if case .orderedList = $0.kind { return true }; if case .unorderedList = $0.kind { return true }; return false }.count
    }
    public func isEquivalent(_ other: PresentationIntent) -> Bool { components.map(\.kind) == other.components.map(\.kind) }
    public var debugDescription: String { components.map(\.debugDescription).joined(separator: ", ") }
}

extension AttributeScopes.FoundationAttributes {
    public enum InlinePresentationIntentAttribute: CodableAttributedStringKey {
        public typealias Value = InlinePresentationIntent
        public static let name = "NSInlinePresentationIntent"
    }
    public enum PresentationIntentAttribute: CodableAttributedStringKey {
        public typealias Value = PresentationIntent
        public static let name = "NSPresentationIntent"
    }
    // Key paths only: the dynamic member lookup reads the key's type, never the value.
    public var inlinePresentationIntent: InlinePresentationIntentAttribute { fatalError() }
    public var presentationIntent: PresentationIntentAttribute { fatalError() }
}
