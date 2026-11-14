import WidgetKit
import SwiftUI

// Lock Screen accessory widgets: a circular gauge, a rectangular summary and an inline line.

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int
    let nextEvent: String
    let nextEventTime: Date
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) { completion(.sample) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        completion(Timeline(entries: [.sample], policy: .after(.now.addingTimeInterval(900))))
    }
}

extension StepsEntry {
    static let sample = StepsEntry(date: .now, steps: 6_480, goal: 10_000, nextEvent: "Design review",
                                   nextEventTime: .now.addingTimeInterval(25 * 60))
}

struct StepsCircularView: View {
    let entry: StepsEntry
    var body: some View {
        Gauge(value: Double(entry.steps), in: 0...Double(entry.goal)) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            Text("\(entry.steps / 1000)k")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

struct StepsRectangularView: View {
    let entry: StepsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text("Next up").font(.headline)
            }
            .widgetAccentable()
            Text(entry.nextEvent)
                .font(.body)
            Text(entry.nextEventTime, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StepsInlineView: View {
    let entry: StepsEntry
    var body: some View {
        ViewThatFits {
            Text("\(Image(systemName: "figure.walk")) \(entry.steps) steps today")
            Text("\(entry.steps) steps")
        }
    }
}

struct StepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StepsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: StepsCircularView(entry: entry)
        case .accessoryRectangular: StepsRectangularView(entry: entry)
        default: StepsInlineView(entry: entry)
        }
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Steps", provider: StepsProvider()) { entry in
            StepsWidgetView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Steps")
        .description("Your steps and what is next.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// A second circular widget that draws its own backing with AccessoryWidgetBackground.
struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Battery", provider: StepsProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill").font(.title3)
                    Text("78").font(.caption.weight(.semibold))
                }
            }
        }
        .configurationDisplayName("Battery")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct LockScreenWidgets: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        BatteryWidget()
    }
}
