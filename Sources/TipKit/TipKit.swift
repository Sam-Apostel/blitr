// `import TipKit`: tips, their rules, events and parameters, and the views that show them (TipViews.swift).
// A screenshot is a fresh install whose tips are not shown: a tip displays only after
// `Tips.showAllTipsForTesting()` / `showTipsForTesting(_:)`, or when the render is run with `--show-tips`.
// Rules, events and parameters are recorded and evaluated, but do not decide whether a tip shows.
// `@Parameter` is a property wrapper here and `#Rule(...)` is rewritten to `Tips.Rule(...)` by the
// preprocessor (macros cannot be built here).
@_exported import Foundation
import SwiftUI

// MARK: - Tip

public protocol Tip: Identifiable, Sendable {
    var id: String { get }
    var title: Text { get }
    var message: Text? { get }
    var image: Image? { get }
    @Tips.ActionBuilder var actions: [Tips.Action] { get }
    @Tips.RuleBuilder var rules: [Tips.Rule] { get }
    @Tips.OptionsBuilder var options: [any TipOption] { get }
}

extension Tip {
    public typealias Rule = Tips.Rule
    public typealias Event = Tips.Event
    public typealias Action = Tips.Action
    public typealias Status = Tips.Status
    public typealias InvalidationReason = Tips.InvalidationReason
    public typealias Option = TipOption
    public typealias IgnoresDisplayFrequency = Tips.IgnoresDisplayFrequency
    public typealias MaxDisplayCount = Tips.MaxDisplayCount
    public typealias MaxDisplayDuration = Tips.MaxDisplayDuration
    public typealias Parameter<Value: Codable & Sendable> = Tips.Parameter<Value>

    public var id: String { String(describing: Self.self) }
    public var message: Text? { nil }
    public var image: Image? { nil }
    public var actions: [Tips.Action] { [] }
    public var rules: [Tips.Rule] { [] }
    public var options: [any TipOption] { [] }

    public var status: Tips.Status {
        if let reason = TipStore.shared.invalidated(id) { return .invalidated(reason) }
        return shouldDisplay ? .available : .pending
    }
    public var shouldDisplay: Bool { TipStore.shared.shouldDisplay(self) }
    public var statusUpdates: AsyncStream<Tips.Status> { TipStore.once(status) }
    public var shouldDisplayUpdates: AsyncStream<Bool> { TipStore.once(shouldDisplay) }
    public func invalidate(reason: Tips.InvalidationReason) { TipStore.shared.invalidate(id, reason) }
    public func resetEligibility() async { TipStore.shared.invalidate(id, nil) }
}

/// A type-erased tip.
public struct AnyTip: Tip {
    let base: any Tip
    public init(_ tip: any Tip) { base = (tip as? AnyTip)?.base ?? tip }
    public var id: String { base.id }
    public var title: Text { base.title }
    public var message: Text? { base.message }
    public var image: Image? { base.image }
    public var actions: [Tips.Action] { base.actions }
    public var rules: [Tips.Rule] { base.rules }
    public var options: [any TipOption] { base.options }
    public var shouldDisplay: Bool { base.shouldDisplay }
}

// MARK: - Tips

@frozen
public enum Tips {
    public enum Status: Hashable, Sendable {
        case pending, available
        case invalidated(Tips.InvalidationReason)
    }
    public enum InvalidationReason: Hashable, Sendable {
        case actionPerformed, displayCountExceeded, displayDurationExceeded, tipClosed
    }

    public struct ConfigurationOption: Sendable {
        let apply: @Sendable (inout TipStore.Configuration) -> Void
        public struct DisplayFrequency: Hashable, Sendable {
            let interval: TimeInterval
            public init(_ interval: TimeInterval) { self.interval = interval }
            public static let immediate = DisplayFrequency(0)
            public static let hourly = DisplayFrequency(3600)
            public static let daily = DisplayFrequency(86_400)
            public static let weekly = DisplayFrequency(604_800)
            public static let monthly = DisplayFrequency(2_592_000)
        }
        public struct DatastoreLocation: Sendable {
            let url: URL?
            public init(url: URL, shouldReset: Bool = false) { self.url = url }
            init(_ url: URL?) { self.url = url }
            public static let applicationDefault = DatastoreLocation(nil)
            public static func groupContainer(identifier: String) throws -> DatastoreLocation { DatastoreLocation(nil) }
            public static func url(_ url: URL, shouldReset: Bool = false) -> DatastoreLocation { DatastoreLocation(url) }
        }
        public struct CloudKitContainer: Sendable {
            public static let automatic = CloudKitContainer()
            public static func named(_ name: String) -> CloudKitContainer { CloudKitContainer() }
        }
        public static func displayFrequency(_ displayFrequency: DisplayFrequency) -> ConfigurationOption {
            ConfigurationOption { $0.frequency = displayFrequency }
        }
        public static func datastoreLocation(_ storeLocation: DatastoreLocation) -> ConfigurationOption { ConfigurationOption { _ in } }
        public static func cloudKitContainer(_ container: CloudKitContainer) -> ConfigurationOption { ConfigurationOption { _ in } }
    }

    public static func configure(_ configuration: [ConfigurationOption] = []) throws {
        TipStore.shared.configure(configuration)
    }
    public static func showAllTipsForTesting() { TipStore.shared.setForced(all: true) }
    public static func showTipsForTesting(_ tips: [any Tip.Type]) { TipStore.shared.setForced(shown: tips) }
    public static func hideAllTipsForTesting() { TipStore.shared.setForced(all: false) }
    public static func hideTipsForTesting(_ tips: [any Tip.Type]) { TipStore.shared.setForced(hidden: tips) }
    public static func resetDatastore() throws { TipStore.shared.reset() }

    // MARK: Actions

    public struct Action: Identifiable, Sendable {
        public let id: String
        public let index: Int?
        public let label: @Sendable () -> Text
        public let handler: @Sendable () -> Void

        public init(id: String? = nil, perform handler: @escaping @Sendable () -> Void = {}, _ label: @escaping @Sendable () -> Text) {
            self.id = id ?? UUID().uuidString
            self.index = nil
            self.label = label
            self.handler = handler
        }
        public init(id: String? = nil, title: some StringProtocol, perform handler: @escaping @Sendable () -> Void = {}) {
            let text = String(title)
            self.init(id: id, perform: handler) { Text(text) }
        }
        init(_ action: Action, index: Int) {
            id = action.id
            self.index = index
            label = action.label
            handler = action.handler
        }
    }

    @resultBuilder
    public struct ActionBuilder {
        public static func buildExpression(_ action: Action) -> [Action] { [action] }
        public static func buildExpression(_ actions: [Action]) -> [Action] { actions }
        public static func buildBlock(_ parts: [Action]...) -> [Action] {
            parts.flatMap { $0 }.enumerated().map { Action($0.element, index: $0.offset) }
        }
        public static func buildOptional(_ part: [Action]?) -> [Action] { part ?? [] }
        public static func buildEither(first: [Action]) -> [Action] { first }
        public static func buildEither(second: [Action]) -> [Action] { second }
        public static func buildArray(_ parts: [[Action]]) -> [Action] { parts.flatMap { $0 } }
        public static func buildLimitedAvailability(_ part: [Action]) -> [Action] { part }
    }

    // MARK: Rules

    public struct Rule: Sendable {
        public enum CompoundOperation: Sendable { case and, or }
        let isSatisfied: @Sendable () -> Bool

        public init<V>(_ parameter: Tips.Parameter<V>, _ predicate: @escaping @Sendable (V) -> Bool) {
            isSatisfied = { predicate(parameter.wrappedValue) }
        }
        public init<V1, V2>(_ p1: Tips.Parameter<V1>, _ p2: Tips.Parameter<V2>, _ predicate: @escaping @Sendable (V1, V2) -> Bool) {
            isSatisfied = { predicate(p1.wrappedValue, p2.wrappedValue) }
        }
        public init<D>(_ event: Tips.Event<D>, _ predicate: @escaping @Sendable (Tips.Event<D>) -> Bool) {
            isSatisfied = { predicate(event) }
        }
        public init(_ predicate: @escaping @Sendable () -> Bool) { isSatisfied = predicate }
    }

    @resultBuilder
    public struct RuleBuilder {
        public static func buildExpression(_ rule: Rule) -> [Rule] { [rule] }
        public static func buildExpression(_ rules: [Rule]) -> [Rule] { rules }
        public static func buildBlock(_ parts: [Rule]...) -> [Rule] { parts.flatMap { $0 } }
        public static func buildOptional(_ part: [Rule]?) -> [Rule] { part ?? [] }
        public static func buildEither(first: [Rule]) -> [Rule] { first }
        public static func buildEither(second: [Rule]) -> [Rule] { second }
        public static func buildArray(_ parts: [[Rule]]) -> [Rule] { parts.flatMap { $0 } }
        public static func buildLimitedAvailability(_ part: [Rule]) -> [Rule] { part }
    }

    // MARK: Options

    public struct IgnoresDisplayFrequency: TipOption {
        public init(_ ignoresDisplayFrequency: Bool) {}
    }
    public struct MaxDisplayCount: TipOption {
        public init(_ maxDisplayCount: Int) {}
    }
    public struct MaxDisplayDuration: TipOption {
        public init(_ maxDisplayDuration: TimeInterval) {}
    }

    @resultBuilder
    public struct OptionsBuilder {
        public static func buildExpression(_ option: any TipOption) -> [any TipOption] { [option] }
        public static func buildExpression(_ options: [any TipOption]) -> [any TipOption] { options }
        public static func buildBlock(_ parts: [any TipOption]...) -> [any TipOption] { parts.flatMap { $0 } }
        public static func buildOptional(_ part: [any TipOption]?) -> [any TipOption] { part ?? [] }
        public static func buildEither(first: [any TipOption]) -> [any TipOption] { first }
        public static func buildEither(second: [any TipOption]) -> [any TipOption] { second }
    }

    // MARK: Parameters

    public struct ParameterOption: Sendable {
        let transient: Bool
        public static let transient = ParameterOption(transient: true)
    }

    /// A value rules read. Here a property wrapper (Apple's `@Parameter` is a macro that makes one).
    @propertyWrapper
    public struct Parameter<Value: Codable & Sendable>: @unchecked Sendable {
        final class Box: @unchecked Sendable {
            var value: Value
            init(_ value: Value) { self.value = value }
        }
        let box: Box
        public let id: String

        public init(wrappedValue: Value, _ options: Tips.ParameterOption...) {
            box = Box(wrappedValue)
            id = UUID().uuidString
        }
        public init(_ owner: Any.Type, _ key: String, _ defaultValue: Value, _ options: Tips.ParameterOption...) {
            box = Box(defaultValue)
            id = "\(owner).\(key)"
        }
        public var wrappedValue: Value {
            get { box.value }
            nonmutating set { box.value = newValue }
        }
        public var projectedValue: Tips.Parameter<Value> { self }
    }

    // MARK: Events

    public struct EmptyDonation: Codable, Hashable, Sendable {
        public init() {}
    }

    public struct DonationLimit: Sendable {
        let count: Int?
        public static func max(_ count: Int) -> DonationLimit { DonationLimit(count: count) }
        public static let unlimited = DonationLimit(count: nil)
    }

    public struct DonationTimeRange: Sendable {
        let seconds: TimeInterval
        public static let minute = DonationTimeRange(seconds: 60)
        public static let hour = DonationTimeRange(seconds: 3600)
        public static let day = DonationTimeRange(seconds: 86_400)
        public static let week = DonationTimeRange(seconds: 604_800)
        public static func minutes(_ n: Int) -> DonationTimeRange { DonationTimeRange(seconds: Double(n) * 60) }
        public static func hours(_ n: Int) -> DonationTimeRange { DonationTimeRange(seconds: Double(n) * 3600) }
        public static func days(_ n: Int) -> DonationTimeRange { DonationTimeRange(seconds: Double(n) * 86_400) }
        public static func weeks(_ n: Int) -> DonationTimeRange { DonationTimeRange(seconds: Double(n) * 604_800) }
    }

    public struct Event<DonationInfo: Codable & Sendable>: Identifiable, Sendable {
        public struct Donation: Sendable {
            public let date: Date
            public let info: DonationInfo
        }
        public let id: String
        let limit: Int?

        public init(id: String) where DonationInfo == Tips.EmptyDonation { self.id = id; limit = nil }
        public init(id: String, donationLimit: Tips.DonationLimit) where DonationInfo == Tips.EmptyDonation { self.id = id; limit = donationLimit.count }
        public init(id: String) { self.id = id; limit = nil }
        public init(id: String, donationLimit: Tips.DonationLimit) { self.id = id; limit = donationLimit.count }

        public var donations: [Donation] { TipStore.shared.donations(id).compactMap { $0 as? Donation } }

        public func donate() async where DonationInfo == Tips.EmptyDonation { sendDonation() }
        public func donate(_ info: DonationInfo) async { sendDonation(info) }
        public func sendDonation(_ completion: @escaping @Sendable () -> Void = {}) where DonationInfo == Tips.EmptyDonation {
            sendDonation(Tips.EmptyDonation() as! DonationInfo, completion)
        }
        public func sendDonation(_ info: DonationInfo, _ completion: @escaping @Sendable () -> Void = {}) {
            TipStore.shared.donate(id, Donation(date: Date(), info: info), limit: limit)
            completion()
        }
        public func deleteDonations() async throws { TipStore.shared.deleteDonations(id) }
    }
}

public protocol TipOption: Sendable {}

extension Array {
    /// The donations made within the last `range`.
    public func donatedWithin<D>(_ range: Tips.DonationTimeRange) -> [Element] where Element == Tips.Event<D>.Donation {
        let start = Date().addingTimeInterval(-range.seconds)
        return filter { $0.date >= start }
    }
}

// MARK: - Store

/// Tip state for this process: configuration, testing overrides, invalidations and event donations.
final class TipStore: @unchecked Sendable {
    struct Configuration { var frequency = Tips.ConfigurationOption.DisplayFrequency.immediate }

    static let shared = TipStore()
    private let lock = NSLock()
    private var configured = false
    private var configuration = Configuration()
    private var showAll: Bool?
    private var shown: Set<String> = []
    private var hidden: Set<String> = []
    private var invalidations: [String: Tips.InvalidationReason] = [:]
    private var donationLog: [String: [Any]] = [:]

    private var render: ObjectIdentifier?

    /// Every render starts as a fresh launch: no configuration, overrides, invalidations or donations.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let current = _currentRenderID(), current != render {
            render = current
            configured = false
            configuration = Configuration()
            showAll = nil
            shown = []
            hidden = []
            invalidations = [:]
            donationLog = [:]
        }
        return body()
    }

    func configure(_ options: [Tips.ConfigurationOption]) {
        locked {
            configured = true
            for option in options { option.apply(&configuration) }
        }
    }
    func setForced(all: Bool) { locked { showAll = all; shown = []; hidden = [] } }
    func setForced(shown tips: [any Tip.Type]) { locked { shown.formUnion(tips.map { String(describing: $0) }) } }
    func setForced(hidden tips: [any Tip.Type]) { locked { hidden.formUnion(tips.map { String(describing: $0) }) } }
    func reset() { locked { invalidations = [:]; donationLog = [:] } }
    func invalidated(_ id: String) -> Tips.InvalidationReason? { locked { invalidations[id] } }
    func invalidate(_ id: String, _ reason: Tips.InvalidationReason?) { locked { invalidations[id] = reason } }
    func donations(_ id: String) -> [Any] { locked { donationLog[id] ?? [] } }
    func donate(_ id: String, _ donation: Any, limit: Int?) {
        locked {
            var log = donationLog[id] ?? []
            log.append(donation)
            if let limit, log.count > limit { log.removeFirst(log.count - limit) }
            donationLog[id] = log
        }
    }
    func deleteDonations(_ id: String) { locked { donationLog[id] = nil } }

    func shouldDisplay(_ tip: some Tip) -> Bool {
        let id = tip.id
        let typeName = String(describing: type(of: (tip as? AnyTip)?.base ?? tip))
        let (all, isShown, isHidden, invalidated) = locked {
            (showAll, shown.contains(typeName) || shown.contains(id), hidden.contains(typeName) || hidden.contains(id), invalidations[id] != nil)
        }
        if invalidated || isHidden || all == false { return false }
        if all == true || isShown { return true }
        return _currentConfiguration().showsTips
    }

    static func once<T: Sendable>(_ value: T) -> AsyncStream<T> {
        AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }
}
