// Focus values, keyboard and text input configuration. Nothing here changes a static frame.
// (The focus engine itself lives in Focus/.)

// MARK: - Focus

public struct FocusInteractions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let activate = FocusInteractions(rawValue: 1)
    public static let edit = FocusInteractions(rawValue: 2)
    public static let automatic: FocusInteractions = [.activate, .edit]
}

public struct DefaultFocusEvaluationPriority: Equatable, Sendable {
    let rawValue: Int
    public static let automatic = DefaultFocusEvaluationPriority(rawValue: 0)
    public static let userInitiated = DefaultFocusEvaluationPriority(rawValue: 1)
}

public protocol FocusedValueKey {
    associatedtype Value
}

public struct FocusedValues: Equatable {
    var storage: [ObjectIdentifier: Any] = [:]
    public init() {}
    public subscript<Key: FocusedValueKey>(key: Key.Type) -> Key.Value? {
        get { storage[ObjectIdentifier(key)] as? Key.Value }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
    public static func == (lhs: FocusedValues, rhs: FocusedValues) -> Bool { lhs.storage.count == rhs.storage.count }
}

/// Nothing has focus in a screenshot, so `@FocusedValue` always reads `nil`.
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    public init(_ keyPath: KeyPath<FocusedValues, Value?>) {}
    public var wrappedValue: Value? { nil }
}

@propertyWrapper
public struct FocusedBinding<Value>: DynamicProperty {
    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) {}
    public var wrappedValue: Value? {
        get { nil }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value?> { Binding(get: { nil }, set: { _ in }) }
}

// focused, focusable, focusSection, focusScope, defaultFocus... are real: see Focus/FocusModel.swift.
extension View {
    public func focusedValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value) -> some View { self }
    public func focusedValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?) -> some View { self }
    public func focusedSceneValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value) -> some View { self }
    public func focusedSceneValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?) -> some View { self }
}

// MARK: - Submit

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1)
    public static let search = SubmitTriggers(rawValue: 2)
}

public struct SubmitLabel: Hashable, Sendable {
    let id: Int
    public static let done = SubmitLabel(id: 0)
    public static let go = SubmitLabel(id: 1)
    public static let send = SubmitLabel(id: 2)
    public static let join = SubmitLabel(id: 3)
    public static let route = SubmitLabel(id: 4)
    public static let search = SubmitLabel(id: 5)
    public static let `return` = SubmitLabel(id: 6)
    public static let next = SubmitLabel(id: 7)
    public static let `continue` = SubmitLabel(id: 8)
}

extension View {
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping (() -> Void)) -> some View { self }
    public func submitLabel(_ submitLabel: SubmitLabel) -> some View { self }
    public func submitScope(_ isBlocking: Bool = true) -> some View { self }
}

// MARK: - Keyboard configuration

public struct TextInputAutocapitalization: Equatable, Sendable {
    let id: Int
    public static let never = TextInputAutocapitalization(id: 0)
    public static let words = TextInputAutocapitalization(id: 1)
    public static let sentences = TextInputAutocapitalization(id: 2)
    public static let characters = TextInputAutocapitalization(id: 3)
}

extension View {
    public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { self }
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }
    public func disableAutocorrection(_ disable: Bool?) -> some View { self }
}

// MARK: - Text selection

public protocol TextSelectability {
    static var allowsSelection: Bool { get }
}
public struct EnabledTextSelectability: TextSelectability {
    public static var allowsSelection: Bool { true }
}
public struct DisabledTextSelectability: TextSelectability {
    public static var allowsSelection: Bool { false }
}
extension TextSelectability where Self == EnabledTextSelectability {
    public static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}
extension TextSelectability where Self == DisabledTextSelectability {
    public static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}

extension View {
    public func textSelection<S: TextSelectability>(_ selectability: S) -> some View { self }
}

// MARK: - Keyboard shortcuts and key presses

public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let capsLock = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let control = EventModifiers(rawValue: 1 << 2)
    public static let option = EventModifiers(rawValue: 1 << 3)
    public static let command = EventModifiers(rawValue: 1 << 4)
    public static let numericPad = EventModifiers(rawValue: 1 << 5)
    public static let function = EventModifiers(rawValue: 1 << 6)
    public static let all: EventModifiers = [.capsLock, .shift, .control, .option, .command, .numericPad, .function]
}

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public var character: Character
    public init(_ character: Character) { self.character = character }
    public init(extendedGraphemeClusterLiteral value: Character) { character = value }
    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let delete = KeyEquivalent("\u{8}")
    public static let deleteForward = KeyEquivalent("\u{F728}")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
    public static let clear = KeyEquivalent("\u{F739}")
    public static let tab = KeyEquivalent("\t")
    public static let space = KeyEquivalent(" ")
    public static let `return` = KeyEquivalent("\r")
}

public struct KeyboardShortcut: Hashable, Sendable {
    public struct Localization: Hashable, Sendable {
        let id: Int
        public static let automatic = Localization(id: 0)
        public static let withoutMirroring = Localization(id: 1)
        public static let custom = Localization(id: 2)
    }
    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public var localization: Localization
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
        self.localization = .automatic
    }
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
    }
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])
}

public struct KeyPress: Sendable {
    public enum Phase: Hashable, Sendable { case down, `repeat`, up }
    public struct Phases: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let down = Phases(rawValue: 1)
        public static let `repeat` = Phases(rawValue: 2)
        public static let up = Phases(rawValue: 4)
        public static let all: Phases = [.down, .repeat, .up]
    }
    public enum Result: Sendable { case handled, ignored }
    public var phase: Phase
    public var key: KeyEquivalent
    public var characters: String
    public var charactersIgnoringModifiers: String
    public var modifiers: EventModifiers
}

extension View {
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View { self }
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command,
                                 localization: KeyboardShortcut.Localization) -> some View { self }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View { self }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View { self }

    public func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View { self }
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View { self }
    public func onKeyPress(_ key: KeyEquivalent, modifiers: EventModifiers,
                           phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View { self }
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View { self }
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View { self }
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View { self }
}
