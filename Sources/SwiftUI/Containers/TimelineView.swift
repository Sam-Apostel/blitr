// TimelineView: a still frame is rendered at a single moment, so the content is built once for "now".

public protocol TimelineSchedule {
    associatedtype Entries: Sequence where Entries.Element == Date
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries
}

public enum TimelineScheduleMode: Hashable, Sendable { case normal, lowFrequency }

public struct EveryMinuteTimelineSchedule: TimelineSchedule {
    public init() {}
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { [startDate] }
}
public struct PeriodicTimelineSchedule: TimelineSchedule {
    let start: Date, by: TimeInterval
    public init(from startDate: Date, by interval: TimeInterval) { start = startDate; by = interval }
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { [max(start, startDate)] }
}
public struct AnimationTimelineSchedule: TimelineSchedule {
    public init(minimumInterval: Double? = nil, paused: Bool = false) {}
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { [startDate] }
}
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule where Entries.Element == Date {
    let dates: Entries
    public init(_ dates: Entries) { self.dates = dates }
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries { dates }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    public static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: startDate, by: interval)
    }
}
extension TimelineSchedule where Self == AnimationTimelineSchedule {
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
    }
}
extension TimelineSchedule {
    public static func explicit<S: Sequence>(_ dates: S) -> Self where Self == ExplicitTimelineSchedule<S> {
        ExplicitTimelineSchedule(dates)
    }
}

public struct TimelineViewContext {
    public enum Cadence: Comparable, Hashable, Sendable { case live, seconds, minutes }
    public let date: Date
    public let cadence: Cadence
    public let isDimmedForLowFrequency: Bool
}

public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Context = TimelineViewContext
    let schedule: Schedule
    let content: (Context) -> Content

    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    public var body: some View {
        // The first scheduled entry at or after the render reference time (explicit schedules may start earlier or later).
        let now = Runtime.now
        let date = schedule.entries(from: now, mode: .normal).first(where: { _ in true }) ?? now
        return content(TimelineViewContext(date: date, cadence: .live, isDimmedForLowFrequency: false))
    }
}
