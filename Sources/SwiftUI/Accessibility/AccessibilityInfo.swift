// Accessibility information attached to nodes while a view tree is resolved.
//
// The accessibility modifiers and the built-in controls record into an `AccessibilityInfo` on the
// nodes they produce (`Node.ax`). Nothing here affects layout or pixels. After layout,
// `AXExtractor` (AccessibilityTree.swift) reads the infos and builds the tree VoiceOver would see.

// MARK: - Traits

/// Internal accessibility trait set: the public `AccessibilityTraits` plus what the built-in
/// controls need (adjustable, tab bar, disabled, pop-up).
struct AXTrait: OptionSet, Hashable, Sendable {
    let rawValue: UInt64
    static let button = AXTrait(rawValue: 1 << 0)
    static let header = AXTrait(rawValue: 1 << 1)
    static let selected = AXTrait(rawValue: 1 << 2)
    static let link = AXTrait(rawValue: 1 << 3)
    static let searchField = AXTrait(rawValue: 1 << 4)
    static let image = AXTrait(rawValue: 1 << 5)
    static let playsSound = AXTrait(rawValue: 1 << 6)
    static let keyboardKey = AXTrait(rawValue: 1 << 7)
    static let staticText = AXTrait(rawValue: 1 << 8)
    static let summaryElement = AXTrait(rawValue: 1 << 9)
    static let updatesFrequently = AXTrait(rawValue: 1 << 10)
    static let startsMediaSession = AXTrait(rawValue: 1 << 11)
    static let allowsDirectInteraction = AXTrait(rawValue: 1 << 12)
    static let causesPageTurn = AXTrait(rawValue: 1 << 13)
    static let modal = AXTrait(rawValue: 1 << 14)
    static let toggle = AXTrait(rawValue: 1 << 15)
    static let adjustable = AXTrait(rawValue: 1 << 16)
    static let tabBar = AXTrait(rawValue: 1 << 17)
    static let notEnabled = AXTrait(rawValue: 1 << 18)
    static let hasPopup = AXTrait(rawValue: 1 << 19)

    /// JSON names, in output order.
    static let names: [(AXTrait, String)] = [
        (.button, "button"), (.link, "link"), (.header, "header"), (.image, "image"), (.staticText, "staticText"),
        (.selected, "selected"), (.toggle, "toggle"), (.adjustable, "adjustable"), (.searchField, "searchField"),
        (.tabBar, "tabBar"), (.notEnabled, "notEnabled"), (.modal, "modal"), (.hasPopup, "hasPopup"),
        (.summaryElement, "summaryElement"), (.updatesFrequently, "updatesFrequently"),
        (.startsMediaSession, "startsMediaSession"), (.allowsDirectInteraction, "allowsDirectInteraction"),
        (.causesPageTurn, "causesPageTurn"), (.playsSound, "playsSound"), (.keyboardKey, "keyboardKey"),
    ]
    var nameList: [String] { AXTrait.names.filter { contains($0.0) }.map { $0.1 } }
}

extension AXTrait {
    /// The public SwiftUI traits map one-to-one onto the low bits (same order as `AccessibilityTraits`).
    init(_ traits: AccessibilityTraits) {
        var result: AXTrait = []
        let map: [(AccessibilityTraits, AXTrait)] = [
            (.isButton, .button), (.isHeader, .header), (.isSelected, .selected), (.isLink, .link),
            (.isSearchField, .searchField), (.isImage, .image), (.playsSound, .playsSound),
            (.isKeyboardKey, .keyboardKey), (.isStaticText, .staticText), (.isSummaryElement, .summaryElement),
            (.updatesFrequently, .updatesFrequently), (.startsMediaSession, .startsMediaSession),
            (.allowsDirectInteraction, .allowsDirectInteraction), (.causesPageTurn, .causesPageTurn),
            (.isModal, .modal), (.isToggle, .toggle),
        ]
        for (public_, internal_) in map where traits.contains(public_) { result.insert(internal_) }
        self = result
    }
}

enum AXChildren: Equatable {
    case ignore, contain, combine
    init(_ behavior: AccessibilityChildBehavior) {
        switch behavior {
        case .contain: self = .contain
        case .combine: self = .combine
        default: self = .ignore
        }
    }
}

// MARK: - Info

/// What a node (or a modifier on it) says about its accessibility. Optional fields mean "not set";
/// an outer modifier overrides an inner one field by field (`apply`).
struct AccessibilityInfo {
    /// The node is an accessibility element in its own right (controls, `accessibilityElement`, tap gestures).
    var isElement = false
    /// Explicit role name for the JSON (`"switch"`, `"slider"`...); derived from the traits when nil.
    var role: String?
    var label: String?
    var value: String?
    var hint: String?
    var identifier: String?
    var addTraits: AXTrait = []
    var removeTraits: AXTrait = []
    var hidden: Bool?
    var children: AXChildren?
    var sortPriority: Double?
    var actions: [String] = []
    var inputLabels: [String] = []
    /// The element's default action (the Button's closure). Internal: a later feature simulates taps with it.
    var activate: (@MainActor () -> Void)?
    /// A touch lands on this element (button, tap gesture, text field...).
    var isTapTarget = false
    /// System controls (switch, slider, stepper...) get the platform's expanded 44pt hit region.
    var systemHitSlop = false
    var isEnabled: Bool?
    /// `accessibilityRepresentation`: unplaced nodes whose semantics replace this node's.
    var representation: [Node]?

    init() {}
    init(_ configure: (inout AccessibilityInfo) -> Void) { configure(&self) }

    mutating func apply(_ outer: AccessibilityInfo) {
        isElement = isElement || outer.isElement
        role = outer.role ?? role
        label = outer.label ?? label
        value = outer.value ?? value
        hint = outer.hint ?? hint
        identifier = outer.identifier ?? identifier
        let added = addTraits.subtracting(outer.removeTraits).union(outer.addTraits)
        let removed = removeTraits.subtracting(outer.addTraits).union(outer.removeTraits)
        addTraits = added
        removeTraits = removed
        hidden = outer.hidden ?? hidden
        children = outer.children ?? children
        sortPriority = outer.sortPriority ?? sortPriority
        for action in outer.actions where !actions.contains(action) { actions.append(action) }
        if !outer.inputLabels.isEmpty { inputLabels = outer.inputLabels }
        activate = outer.activate ?? activate
        isTapTarget = isTapTarget || outer.isTapTarget
        systemHitSlop = systemHitSlop || outer.systemHitSlop
        if outer.isEnabled == false { isEnabled = false } else { isEnabled = isEnabled ?? outer.isEnabled }
        representation = outer.representation ?? representation
    }

    // MARK: Factories for the built-in controls

    static func button(enabled: Bool, activate: (@MainActor () -> Void)? = nil, popup: Bool = false) -> AccessibilityInfo {
        AccessibilityInfo {
            $0.isElement = true
            $0.addTraits = popup ? [.button, .hasPopup] : [.button]
            $0.children = .combine
            $0.isTapTarget = true
            $0.isEnabled = enabled
            $0.activate = activate
        }
    }
}

/// Shared, mutable storage so that several sibling nodes produced by one view (a Button whose label
/// has two top-level views) describe one element.
@MainActor
final class AXBox {
    var info: AccessibilityInfo
    init(_ info: AccessibilityInfo = AccessibilityInfo()) { self.info = info }
}

/// Gives `nodes` one shared box carrying `info` on top of whatever they already said.
@MainActor
func axApplyShared(_ nodes: ArraySlice<Node>, _ info: AccessibilityInfo) {
    guard !nodes.isEmpty else { return }
    let box = AXBox()
    for node in nodes {
        if let existing = node.ax, existing !== box { box.info.apply(existing.info) }
        node.ax = box
    }
    box.info.apply(info)
}

// MARK: - The modifier

struct AXModifier: ViewModifier, PrimitiveModifier {
    let shared: Bool
    let make: @MainActor (ResolveContext) -> AccessibilityInfo

    func resolve(content: ModifierContent, _ ctx: ResolveContext, into out: inout [Node]) {
        let nodes = content.nodes(ctx)
        let change = make(ctx)
        if shared && nodes.count > 1 {
            axApplyShared(nodes[...], change)
        } else {
            for node in nodes {
                let box = node.ax ?? AXBox()
                box.info.apply(change)
                node.ax = box
            }
        }
        out.append(contentsOf: nodes)
    }
}

extension View {
    /// Records accessibility info on every node this view produces.
    func axInfo(shared: Bool = false, _ configure: @escaping (inout AccessibilityInfo) -> Void) -> ModifiedContent<Self, AXModifier> {
        modifier(AXModifier(shared: shared) { _ in AccessibilityInfo(configure) })
    }
    /// Same, with access to the resolve context (environment, nested resolution).
    func axInfo(shared: Bool = false, context make: @escaping @MainActor (ResolveContext) -> AccessibilityInfo) -> ModifiedContent<Self, AXModifier> {
        modifier(AXModifier(shared: shared, make: make))
    }
}

// MARK: - Text helpers shared by the controls

extension AXTrait {
    /// The label VoiceOver reads for an unlabelled `Image(systemName:)`: Apple's own label where the system has
    /// one (`SymbolAccessibilityLabels`), else the name's words without the `fill` variant ("tortoise.fill" -> "Tortoise").
    static func humanized(symbol name: String) -> String {
        if _currentConfiguration().osVersion == 26 {
            if SymbolAccessibilityLabels.unlabelledOnIOS26.contains(name) { return name }
            if let label = SymbolAccessibilityLabels.ios26Labels[name] { return label }
        }
        if let label = SymbolAccessibilityLabels.labels[name] { return label }
        let words = name.split(separator: ".").filter { $0 != "fill" }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? name : words.joined(separator: " ")
    }
}

/// The plain string of a view that is a `Text` (labels passed as `Label` generics), else nil.
func axPlainString(_ view: Any) -> String? {
    (view as? Text)?.plainString
}
