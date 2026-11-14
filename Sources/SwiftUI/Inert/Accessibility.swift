// Accessibility modifiers. A screenshot has no assistive technology, so all of these accept their
// arguments and leave the view alone. (`AccessibilityHeadingLevel`, `AccessibilityTextContentType`
// and the Text-level accessibility modifiers live in Text/Text.swift.)

// MARK: - Value types

public struct AccessibilityTraits: SetAlgebra, Equatable, Sendable {
    var bits: UInt64
    init(bits: UInt64) { self.bits = bits }
    public init() { bits = 0 }
    public static let isButton = AccessibilityTraits(bits: 1 << 0)
    public static let isHeader = AccessibilityTraits(bits: 1 << 1)
    public static let isSelected = AccessibilityTraits(bits: 1 << 2)
    public static let isLink = AccessibilityTraits(bits: 1 << 3)
    public static let isSearchField = AccessibilityTraits(bits: 1 << 4)
    public static let isImage = AccessibilityTraits(bits: 1 << 5)
    public static let playsSound = AccessibilityTraits(bits: 1 << 6)
    public static let isKeyboardKey = AccessibilityTraits(bits: 1 << 7)
    public static let isStaticText = AccessibilityTraits(bits: 1 << 8)
    public static let isSummaryElement = AccessibilityTraits(bits: 1 << 9)
    public static let updatesFrequently = AccessibilityTraits(bits: 1 << 10)
    public static let startsMediaSession = AccessibilityTraits(bits: 1 << 11)
    public static let allowsDirectInteraction = AccessibilityTraits(bits: 1 << 12)
    public static let causesPageTurn = AccessibilityTraits(bits: 1 << 13)
    public static let isModal = AccessibilityTraits(bits: 1 << 14)
    public static let isToggle = AccessibilityTraits(bits: 1 << 15)

    public func union(_ other: AccessibilityTraits) -> AccessibilityTraits { AccessibilityTraits(bits: bits | other.bits) }
    public func intersection(_ other: AccessibilityTraits) -> AccessibilityTraits { AccessibilityTraits(bits: bits & other.bits) }
    public func symmetricDifference(_ other: AccessibilityTraits) -> AccessibilityTraits { AccessibilityTraits(bits: bits ^ other.bits) }
    public func contains(_ member: AccessibilityTraits) -> Bool { bits & member.bits == member.bits }
    public var isEmpty: Bool { bits == 0 }
    @discardableResult
    public mutating func insert(_ newMember: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) {
        let inserted = !contains(newMember)
        bits |= newMember.bits
        return (inserted, newMember)
    }
    @discardableResult
    public mutating func remove(_ member: AccessibilityTraits) -> AccessibilityTraits? {
        let present = contains(member)
        bits &= ~member.bits
        return present ? member : nil
    }
    @discardableResult
    public mutating func update(with newMember: AccessibilityTraits) -> AccessibilityTraits? {
        let old = contains(newMember) ? newMember : nil
        bits |= newMember.bits
        return old
    }
    public mutating func formUnion(_ other: AccessibilityTraits) { bits |= other.bits }
    public mutating func formIntersection(_ other: AccessibilityTraits) { bits &= other.bits }
    public mutating func formSymmetricDifference(_ other: AccessibilityTraits) { bits ^= other.bits }
}

public struct AccessibilityChildBehavior: Hashable, Sendable {
    let id: Int
    public static let ignore = AccessibilityChildBehavior(id: 0)
    public static let contain = AccessibilityChildBehavior(id: 1)
    public static let combine = AccessibilityChildBehavior(id: 2)
}

public struct AccessibilityActionKind: Equatable, Sendable {
    let name: String
    public static let `default` = AccessibilityActionKind(name: "default")
    public static let escape = AccessibilityActionKind(name: "escape")
    public static let magicTap = AccessibilityActionKind(name: "magicTap")
    public static let delete = AccessibilityActionKind(name: "delete")
    init(name: String) { self.name = name }
    public init(named name: Text) { self.name = "\(name)" }
}

public struct AccessibilityActionCategory: Equatable, Sendable {
    let name: String
    public static let `default` = AccessibilityActionCategory(name: "default")
    public static let edit = AccessibilityActionCategory(name: "edit")
    public static let control = AccessibilityActionCategory(name: "control")
    init(name: String) { self.name = name }
    public init(_ label: Text) { name = "\(label)" }
    public init(_ labelKey: LocalizedStringKey) { name = labelKey.plainString }
    public init<S: StringProtocol>(_ label: S) { name = String(label) }
}

public enum AccessibilityAdjustmentDirection: Sendable {
    case increment, decrement
}

public struct AccessibilityDirectTouchOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let silentOnTouch = AccessibilityDirectTouchOptions(rawValue: 1)
    public static let requiresActivation = AccessibilityDirectTouchOptions(rawValue: 2)
}

public struct AccessibilityLabeledPairRole: Hashable, Sendable {
    let id: Int
    public static let label = AccessibilityLabeledPairRole(id: 0)
    public static let content = AccessibilityLabeledPairRole(id: 1)
}

public struct AccessibilityTechnologies: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let switchControl = AccessibilityTechnologies(rawValue: 1)
    public static let voiceOver = AccessibilityTechnologies(rawValue: 2)
}

public struct AXCustomContent: Sendable {
    public enum Importance: Sendable { case `default`, high }
}

public struct AccessibilityCustomContentKey: Hashable, Sendable {
    let id: String
    public init(_ label: Text, id: String) { self.id = id }
    public init(_ labelKey: LocalizedStringKey, id: String) { self.id = id }
    public init(_ labelKey: LocalizedStringKey) { id = labelKey.plainString }
}

public struct AccessibilityNotification {
    public struct Announcement {
        public init(_ value: String) {}
        public init(_ value: AttributedString) {}
        public func post() {}
    }
    public struct LayoutChanged {
        public init(_ argument: Any? = nil) {}
        public func post() {}
    }
    public struct ScreenChanged {
        public init(_ argument: Any? = nil) {}
        public func post() {}
    }
    public struct PageScrolled {
        public init(_ value: String) {}
        public func post() {}
    }
}

// MARK: - AccessibilityFocusState

@propertyWrapper
public struct AccessibilityFocusState<Value: Hashable>: DynamicProperty, InstallableProperty {
    final class Storage { var value: Value; init(_ v: Value) { value = v } }
    final class Box { var storage: Storage; init(_ s: Storage) { storage = s } }
    let box: Box

    @propertyWrapper
    public struct Binding {
        let getter: () -> Value
        let setter: (Value) -> Void
        public var wrappedValue: Value {
            get { getter() }
            nonmutating set { setter(newValue) }
        }
        public var projectedValue: Binding { self }
    }

    public init() where Value == Bool { box = Box(Storage(false)) }
    public init(for technologies: AccessibilityTechnologies) where Value == Bool { box = Box(Storage(false)) }
    public init<T: Hashable>() where Value == T? { box = Box(Storage(nil)) }
    public init<T: Hashable>(for technologies: AccessibilityTechnologies) where Value == T? { box = Box(Storage(nil)) }
    public init(wrappedValue: Value) { box = Box(Storage(wrappedValue)) }

    public var wrappedValue: Value {
        get { box.storage.value }
        nonmutating set {
            box.storage.value = newValue
            MainActor.assumeIsolated { Runtime.current?.needsAnotherPass = true }
        }
    }
    public var projectedValue: Binding {
        let box = self.box
        return Binding(getter: { box.storage.value }, setter: { box.storage.value = $0 })
    }
    func install(_ ic: inout InstallContext) {
        let initial = box.storage
        box.storage = ic.storage { initial }
    }
}

// MARK: - Rotors

public protocol AccessibilityRotorContent {
    associatedtype Body: AccessibilityRotorContent
    @AccessibilityRotorContentBuilder var body: Self.Body { get }
}
extension AccessibilityRotorContent where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive rotor type") }
}
extension Never: AccessibilityRotorContent {}

@resultBuilder
public struct AccessibilityRotorContentBuilder {
    public static func buildExpression<C: AccessibilityRotorContent>(_ content: C) -> C { content }
    public static func buildBlock() -> _RotorGroup { _RotorGroup() }
    public static func buildPartialBlock<C: AccessibilityRotorContent>(first: C) -> _RotorGroup { _RotorGroup() }
    public static func buildPartialBlock<C: AccessibilityRotorContent>(accumulated: _RotorGroup, next: C) -> _RotorGroup { accumulated }
    public static func buildIf<C: AccessibilityRotorContent>(_ content: C?) -> _RotorGroup { _RotorGroup() }
    public static func buildEither<C: AccessibilityRotorContent>(first: C) -> _RotorGroup { _RotorGroup() }
    public static func buildEither<C: AccessibilityRotorContent>(second: C) -> _RotorGroup { _RotorGroup() }
}
public struct _RotorGroup: AccessibilityRotorContent {
    public typealias Body = Never
}

public struct AccessibilityRotorEntry<ID: Hashable>: AccessibilityRotorContent {
    public typealias Body = Never
    public init(_ label: Text, id: ID, in namespace: Namespace.ID? = nil) {}
    public init(_ labelKey: LocalizedStringKey, id: ID, in namespace: Namespace.ID? = nil) {}
    public init<S: StringProtocol>(_ label: S, id: ID, in namespace: Namespace.ID? = nil) {}
    public init(_ label: Text, textRange: Range<String.Index>) where ID == Never {}
    public init(textRange: Range<String.Index>) where ID == Never {}
}

public struct AccessibilitySystemRotor: Sendable {
    let id: Int
    public static let links = AccessibilitySystemRotor(id: 0)
    public static let visitedLinks = AccessibilitySystemRotor(id: 1)
    public static let headings = AccessibilitySystemRotor(id: 2)
    public static let boldText = AccessibilitySystemRotor(id: 3)
    public static let italicText = AccessibilitySystemRotor(id: 4)
    public static let underlineText = AccessibilitySystemRotor(id: 5)
    public static let misspelledWords = AccessibilitySystemRotor(id: 6)
    public static let images = AccessibilitySystemRotor(id: 7)
    public static let textFields = AccessibilitySystemRotor(id: 8)
    public static let tables = AccessibilitySystemRotor(id: 9)
    public static let lists = AccessibilitySystemRotor(id: 10)
    public static let landmarks = AccessibilitySystemRotor(id: 11)
}

// MARK: - Modifiers

extension View {
    // Label, hint, value
    // Text has its own Text-returning versions (Text/Text.swift); prefer those on a Text receiver.
    @_disfavoredOverload
    public func accessibilityLabel(_ label: Text) -> some View { self }
    @_disfavoredOverload
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { self }
    public func accessibilityHint(_ hint: Text) -> some View { self }
    public func accessibilityHint(_ hintKey: LocalizedStringKey) -> some View { self }
    public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { self }
    public func accessibilityValue(_ value: Text) -> some View { self }
    public func accessibilityValue(_ valueKey: LocalizedStringKey) -> some View { self }
    public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { self }
    public func accessibilityInputLabels(_ inputLabels: [Text]) -> some View { self }
    public func accessibilityInputLabels(_ inputLabelKeys: [LocalizedStringKey]) -> some View { self }
    public func accessibilityInputLabels<S: StringProtocol>(_ inputLabels: [S]) -> some View { self }

    // Visibility, identity, structure
    public func accessibilityHidden(_ hidden: Bool) -> some View { self }
    public func accessibilityIdentifier(_ identifier: String) -> some View { self }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { self }
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { self }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func accessibilitySortPriority(_ sortPriority: Double) -> some View { self }
    public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> some View { self }
    public func accessibilityTextContentType(_ textContentType: AccessibilityTextContentType) -> some View { self }
    public func accessibilityRespondsToUserInteraction(_ respondsToUserInteraction: Bool = true) -> some View { self }
    public func accessibilityIgnoresInvertColors(_ active: Bool = true) -> some View { self }
    public func accessibilityActivationPoint(_ activationPoint: CGPoint) -> some View { self }
    public func accessibilityActivationPoint(_ activationPoint: UnitPoint) -> some View { self }
    public func accessibilityDirectTouch(_ isDirectTouchArea: Bool = true, options: AccessibilityDirectTouchOptions = []) -> some View { self }
    public func accessibilityShowsLargeContentViewer() -> some View { self }
    public func accessibilityShowsLargeContentViewer<V: View>(@ViewBuilder _ label: () -> V) -> some View { self }
    public func accessibilityRepresentation<V: View>(@ViewBuilder representation: () -> V) -> some View { self }
    public func accessibilityChildren<V: View>(@ViewBuilder children: () -> V) -> some View { self }
    public func accessibilityLabeledPair<ID: Hashable>(role: AccessibilityLabeledPairRole, id: ID, in namespace: Namespace.ID) -> some View { self }
    public func accessibilityLinkedGroup<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View { self }

    // Focus
    public func accessibilityFocused(_ condition: AccessibilityFocusState<Bool>.Binding) -> some View { self }
    public func accessibilityFocused<V: Hashable>(_ binding: AccessibilityFocusState<V>.Binding, equals value: V) -> some View { self }

    // Actions
    public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> some View { self }
    public func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> some View { self }
    public func accessibilityAction(named nameKey: LocalizedStringKey, _ handler: @escaping () -> Void) -> some View { self }
    public func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping () -> Void) -> some View { self }
    public func accessibilityAction<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View { self }
    @_disfavoredOverload
    public func accessibilityAction(_ category: AccessibilityActionCategory, _ handler: @escaping () -> Void) -> some View { self }
    public func accessibilityActions<C: View>(@ViewBuilder _ content: () -> C) -> some View { self }
    public func accessibilityActions<C: View>(category: AccessibilityActionCategory, @ViewBuilder _ content: () -> C) -> some View { self }
    public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View { self }
    public func accessibilityScrollAction(_ handler: @escaping (Edge) -> Void) -> some View { self }

    // Drag and drop
    public func accessibilityDragPoint(_ point: UnitPoint, description: Text) -> some View { self }
    public func accessibilityDragPoint(_ point: UnitPoint, description: LocalizedStringKey) -> some View { self }
    public func accessibilityDragPoint<S: StringProtocol>(_ point: UnitPoint, description: S) -> some View { self }
    public func accessibilityDropPoint(_ point: UnitPoint, description: Text) -> some View { self }
    public func accessibilityDropPoint(_ point: UnitPoint, description: LocalizedStringKey) -> some View { self }
    public func accessibilityDropPoint<S: StringProtocol>(_ point: UnitPoint, description: S) -> some View { self }

    // Custom content
    public func accessibilityCustomContent(_ key: AccessibilityCustomContentKey, _ value: Text?,
                                           importance: AXCustomContent.Importance = .default) -> some View { self }
    public func accessibilityCustomContent(_ key: AccessibilityCustomContentKey, _ valueKey: LocalizedStringKey,
                                           importance: AXCustomContent.Importance = .default) -> some View { self }
    public func accessibilityCustomContent<V: StringProtocol>(_ key: AccessibilityCustomContentKey, _ value: V,
                                                              importance: AXCustomContent.Importance = .default) -> some View { self }
    public func accessibilityCustomContent(_ label: Text, _ value: Text,
                                           importance: AXCustomContent.Importance = .default) -> some View { self }
    public func accessibilityCustomContent(_ labelKey: LocalizedStringKey, _ value: Text,
                                           importance: AXCustomContent.Importance = .default) -> some View { self }
    public func accessibilityCustomContent<V: StringProtocol>(_ labelKey: LocalizedStringKey, _ value: V,
                                                              importance: AXCustomContent.Importance = .default) -> some View { self }

    // Rotors
    public func accessibilityRotor<C: AccessibilityRotorContent>(_ label: Text, @AccessibilityRotorContentBuilder entries: @escaping () -> C) -> some View { self }
    public func accessibilityRotor<C: AccessibilityRotorContent>(_ labelKey: LocalizedStringKey, @AccessibilityRotorContentBuilder entries: @escaping () -> C) -> some View { self }
    public func accessibilityRotor<L: StringProtocol, C: AccessibilityRotorContent>(_ label: L, @AccessibilityRotorContentBuilder entries: @escaping () -> C) -> some View { self }
    public func accessibilityRotor<C: AccessibilityRotorContent>(_ systemRotor: AccessibilitySystemRotor, @AccessibilityRotorContentBuilder entries: @escaping () -> C) -> some View { self }
    public func accessibilityRotor<M, ID: Hashable>(_ label: Text, entries: [M], entryID: KeyPath<M, ID>,
                                                    entryLabel: KeyPath<M, String>) -> some View { self }
    public func accessibilityRotor<M, ID: Hashable>(_ labelKey: LocalizedStringKey, entries: [M], entryID: KeyPath<M, ID>,
                                                    entryLabel: KeyPath<M, String>) -> some View { self }
    public func accessibilityRotor<L: StringProtocol, M, ID: Hashable>(_ label: L, entries: [M], entryID: KeyPath<M, ID>,
                                                                       entryLabel: KeyPath<M, String>) -> some View { self }
    public func accessibilityRotor<M: Identifiable>(_ label: Text, entries: [M], entryLabel: KeyPath<M, String>) -> some View { self }
    public func accessibilityRotor<M: Identifiable>(_ labelKey: LocalizedStringKey, entries: [M], entryLabel: KeyPath<M, String>) -> some View { self }
    public func accessibilityRotor<L: StringProtocol, M: Identifiable>(_ label: L, entries: [M], entryLabel: KeyPath<M, String>) -> some View { self }

    // Deprecated spellings
    public func accessibility(label: Text) -> some View { self }
    public func accessibility(hint: Text) -> some View { self }
    public func accessibility(value: Text) -> some View { self }
    public func accessibility(hidden: Bool) -> some View { self }
    public func accessibility(identifier: String) -> some View { self }
    public func accessibility(addTraits traits: AccessibilityTraits) -> some View { self }
    public func accessibility(removeTraits traits: AccessibilityTraits) -> some View { self }
    public func accessibility(sortPriority: Double) -> some View { self }
    public func accessibility(activationPoint: CGPoint) -> some View { self }
    public func accessibility(activationPoint: UnitPoint) -> some View { self }
    public func accessibility(inputLabels: [Text]) -> some View { self }

    // Speech
    public func speechAdjustedPitch(_ value: Double) -> some View { self }
    public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> some View { self }
    public func speechAnnouncementsQueued(_ value: Bool = true) -> some View { self }
    public func speechSpellsOutCharacters(_ value: Bool = true) -> some View { self }
}

extension Text {
    public func speechAdjustedPitch(_ value: Double) -> Text { self }
    public func speechAnnouncementsQueued(_ value: Bool = true) -> Text { self }
    public func speechSpellsOutCharacters(_ value: Bool = true) -> Text { self }
}

// MARK: - ForEach inside rotors

extension ForEach: AccessibilityRotorContent where Content: AccessibilityRotorContent {
    public var body: Never { return fatalError("ForEach is a primitive rotor type") }
}

extension ForEach where Content: AccessibilityRotorContent {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @AccessibilityRotorContentBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGetter = { $0[keyPath: id] }
    }
}
extension ForEach where ID == Data.Element.ID, Content: AccessibilityRotorContent, Data.Element: Identifiable {
    public init(_ data: Data, @AccessibilityRotorContentBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}
