
import ActivityKit
import AppIntents
import Foundation
import SwiftUI

// MARK: - Entries and timelines

public protocol TimelineEntry {
    var date: Date { get }
    var relevance: TimelineEntryRelevance? { get }
}

extension TimelineEntry {
    public var relevance: TimelineEntryRelevance? { nil }
}

/// Relevance only steers Smart Stack rotation; it has no effect here.
public struct TimelineEntryRelevance: Codable, Hashable, Sendable {
    public let score: Float
    public let duration: TimeInterval
    public init(score: Float) { self.score = score; duration = 0 }
    public init(score: Float, duration: TimeInterval) { self.score = score; self.duration = duration }
}

public struct TimelineReloadPolicy: Equatable, Sendable {
    let kind: Int
    let date: Date?
    public static let atEnd = TimelineReloadPolicy(kind: 0, date: nil)
    public static let never = TimelineReloadPolicy(kind: 1, date: nil)
    public static func after(_ date: Date) -> TimelineReloadPolicy { TimelineReloadPolicy(kind: 2, date: date) }
}

public struct Timeline<EntryType: TimelineEntry> {
    public let entries: [EntryType]
    public let policy: TimelineReloadPolicy
    public init(entries: [EntryType], policy: TimelineReloadPolicy) {
        self.entries = entries
        self.policy = policy
    }
}

public struct TimelineProviderContext {
    public let family: WidgetFamily
    public let isPreview: Bool
    public let displaySize: CGSize
    public let environmentVariants: EnvironmentVariants

    public struct EnvironmentVariants {
        public subscript<T>(keyPath: WritableKeyPath<EnvironmentValues, T>) -> [T]? { nil }
    }

    init(family: WidgetFamily, isPreview: Bool, displaySize: CGSize) {
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize
        environmentVariants = EnvironmentVariants()
    }

    @MainActor static func preview(_ family: WidgetFamily) -> TimelineProviderContext {
        TimelineProviderContext(family: family, isPreview: true, displaySize: _WidgetHost.displaySize(for: family._id))
    }
}

// MARK: - Providers

public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    typealias Context = TimelineProviderContext
    func placeholder(in context: Context) -> Entry
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void)
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void)
}

public protocol AppIntentTimelineProvider {
    associatedtype Entry: TimelineEntry
    associatedtype Intent: WidgetConfigurationIntent
    typealias Context = TimelineProviderContext
    func placeholder(in context: Context) -> Entry
    func snapshot(for configuration: Intent, in context: Context) async -> Entry
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry>
    func recommendations() -> [AppIntentRecommendation<Intent>]
}

extension AppIntentTimelineProvider {
    public func recommendations() -> [AppIntentRecommendation<Intent>] { [] }
}

public struct AppIntentRecommendation<Intent: WidgetConfigurationIntent> {
    public let intent: Intent
    public init(intent: Intent, description: Text) { self.intent = intent }
    public init(intent: Intent, description: LocalizedStringKey) { self.intent = intent }
    @_disfavoredOverload
    public init<S: StringProtocol>(intent: Intent, description: S) { self.intent = intent }
}

/// Runs a provider's callbacks or async methods to completion, spinning the main run loop
/// for at most `timeout` seconds (a provider may hop to the main actor).
@MainActor
enum _ProviderRunner {
    static let timeout: TimeInterval = 2

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        func set(_ value: T) { lock.lock(); if stored == nil { stored = value }; lock.unlock() }
        var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    static func wait<T>(_ box: Box<T>, what: String) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while box.value == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        if box.value == nil { _WidgetHost.warn("\(what) did not finish within \(Int(timeout))s") }
        return box.value
    }

    static func snapshot<P: TimelineProvider>(_ provider: P, _ context: TimelineProviderContext) -> P.Entry? {
        let box = Box<P.Entry>()
        provider.getSnapshot(in: context) { box.set($0) }
        return wait(box, what: "\(P.self).getSnapshot")
    }

    static func timeline<P: TimelineProvider>(_ provider: P, _ context: TimelineProviderContext) -> [P.Entry]? {
        let box = Box<Timeline<P.Entry>>()
        provider.getTimeline(in: context) { box.set($0) }
        return wait(box, what: "\(P.self).getTimeline")?.entries
    }

    static func snapshot<P: AppIntentTimelineProvider>(_ provider: P, _ intent: P.Intent, _ context: TimelineProviderContext) -> P.Entry? {
        let box = Box<P.Entry>()
        Task { @MainActor in box.set(await provider.snapshot(for: intent, in: context)) }
        return wait(box, what: "\(P.self).snapshot(for:in:)")
    }

    static func timeline<P: AppIntentTimelineProvider>(_ provider: P, _ intent: P.Intent, _ context: TimelineProviderContext) -> [P.Entry]? {
        let box = Box<Timeline<P.Entry>>()
        Task { @MainActor in box.set(await provider.timeline(for: intent, in: context)) }
        return wait(box, what: "\(P.self).timeline(for:in:)")?.entries
    }
}
