// SwiftUI API that widget and Live Activity code uses, and the preview-group hook the generated
// main.swift uses to expand one widget preview into several images.

// MARK: - Preview groups

/// Something the runner renders as one or more images. `_PreviewEntry` is one image; WidgetKit's
/// widget previews expand to one per family or timeline entry.
@MainActor
public protocol _PreviewEntryGroup {
    var _previewEntries: [_PreviewEntry] { get }
}

extension _PreviewEntry: _PreviewEntryGroup {
    public var _previewEntries: [_PreviewEntry] { [self] }
}

// MARK: - Timer text

extension Text {
    /// A timer counting down to (or up from) the interval's bounds, as of the render's fixed "now".
    public init(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true) {
        var now = Runtime.referenceDate
        if let pauseTime, pauseTime < now { now = pauseTime }
        let clamped = min(max(now, timerInterval.lowerBound), timerInterval.upperBound)
        let seconds = Int((countsDown ? timerInterval.upperBound.timeIntervalSince(clamped) : clamped.timeIntervalSince(timerInterval.lowerBound)).rounded())
        let text = showsHours && seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        self.init(storage: .verbatim(text))
    }

    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) { self.init(storage: .verbatim(resource.defaultValue)) }
}

// MARK: - Timer progress

/// The default current-value label of `ProgressView(timerInterval:)`: the remaining time.
public struct DefaultDateProgressLabel: View {
    let interval: ClosedRange<Date>
    let countsDown: Bool
    public var body: some View { Text(timerInterval: interval, countsDown: countsDown) }
}

extension ProgressView {
    static func timerFraction(_ interval: ClosedRange<Date>, countsDown: Bool) -> Double {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return countsDown ? 0 : 1 }
        let elapsed = min(max(Runtime.referenceDate.timeIntervalSince(interval.lowerBound), 0), total) / total
        return countsDown ? 1 - elapsed : elapsed
    }

    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label,
                @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        self.init(fraction: Self.timerFraction(timerInterval, countsDown: countsDown), label: AnyView(label()),
                  currentValueLabel: AnyView(currentValueLabel()))
    }
}

extension ProgressView where CurrentValueLabel == DefaultDateProgressLabel {
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label) {
        self.init(fraction: Self.timerFraction(timerInterval, countsDown: countsDown), label: AnyView(label()),
                  currentValueLabel: AnyView(DefaultDateProgressLabel(interval: timerInterval, countsDown: countsDown)))
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == DefaultDateProgressLabel {
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true) {
        self.init(fraction: Self.timerFraction(timerInterval, countsDown: countsDown), label: nil,
                  currentValueLabel: AnyView(DefaultDateProgressLabel(interval: timerInterval, countsDown: countsDown)))
    }
}

// MARK: - LocalizedStringResource

/// Foundation's `LocalizedStringResource` is missing from swift-corelibs-foundation; app intents
/// and widgets use it for titles. Lookups return the default value (no string tables are loaded).
public struct LocalizedStringResource: Hashable, Sendable, Codable, CustomStringConvertible,
                                       ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public var key: String
    public var defaultValue: String
    public var table: String?
    public var locale: Locale = .current

    public init(stringLiteral value: String) {
        key = value
        defaultValue = value
    }
    public init(stringInterpolation: DefaultStringInterpolation) {
        let value = String(stringInterpolation: stringInterpolation)
        key = value
        defaultValue = value
    }
    public init(_ key: StaticString, defaultValue: String? = nil, table: String? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self.key = "\(key)"
        self.defaultValue = defaultValue ?? "\(key)"
        self.table = table
        self.locale = locale
    }
    public var description: String { defaultValue }

    enum CodingKeys: String, CodingKey { case key, defaultValue, table }
}

extension String {
    public init(localized resource: LocalizedStringResource) { self = resource.defaultValue }
}
