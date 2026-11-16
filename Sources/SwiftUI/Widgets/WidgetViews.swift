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
        var now = Runtime.now
        if let pauseTime, pauseTime < now { now = pauseTime }
        let clamped = min(max(now, timerInterval.lowerBound), timerInterval.upperBound)
        let seconds = Int((countsDown ? timerInterval.upperBound.timeIntervalSince(clamped) : clamped.timeIntervalSince(timerInterval.lowerBound)).rounded())
        let text = showsHours && seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        self.init(storage: .verbatim(text))
    }

    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) { self.init(storage: .verbatim(resource._resolvedText)) }
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
        let elapsed = min(max(Runtime.now.timeIntervalSince(interval.lowerBound), 0), total) / total
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

// Foundation's `LocalizedStringResource` and `String(localized:)` are missing from
// swift-corelibs-foundation; they live in the BlitrFoundation module, which SwiftUI
// re-exports (Compat/Localization.swift), and resolve through the project's string table.
