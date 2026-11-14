import AppIntents
import SwiftUI
import WidgetKit

// An interactive, configurable widget: buttons and a toggle that run app intents, a
// configuration intent with an entity parameter, and a Control Center control in the bundle.

struct Habit: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let goal: Int
    var count: Int
    var remindersOn: Bool

    static let water = Habit(id: "water", name: "Water", symbol: "drop.fill", goal: 8, count: 5, remindersOn: true)
    static let stretch = Habit(id: "stretch", name: "Stretch", symbol: "figure.walk", goal: 3, count: 1, remindersOn: false)
    static let all = [water, stretch]
}

// MARK: Intents

struct HabitEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Habit" }
    static var defaultQuery = HabitQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        Habit.all.filter { identifiers.contains($0.id) }.map { HabitEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [HabitEntity] {
        Habit.all.map { HabitEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select habit"
    static var description = IntentDescription("Choose the habit to track.")

    @Parameter(title: "Habit") var habit: HabitEntity?
    @Parameter(title: "Show reminders", default: true) var showsReminders: Bool

    init() {}
}

struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log habit"
    @Parameter(title: "Habit") var habitID: String
    @Parameter(title: "Amount") var amount: Int

    init() {}
    init(habitID: String, amount: Int) {
        self.habitID = habitID
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "Habit")
        return .result()
    }
}

struct ToggleRemindersIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Reminders"
    @Parameter(title: "On") var value: Bool

    func perform() async throws -> some IntentResult { .result() }
}

// MARK: Timeline

struct HabitEntry: TimelineEntry {
    let date: Date
    let habit: Habit
    let showsReminders: Bool
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: Float(habit.goal - habit.count)) }
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, habit: .water, showsReminders: true)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectHabitIntent) -> HabitEntry {
        let habit = Habit.all.first { $0.id == configuration.habit?.id } ?? .water
        return HabitEntry(date: .now, habit: habit, showsReminders: configuration.showsReminders)
    }
}

// MARK: Views

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HabitEntry

    private var progress: Double { Double(entry.habit.count) / Double(entry.habit.goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(entry.habit.name, systemImage: entry.habit.symbol)
                    .font(.headline)
                    .foregroundStyle(.teal)
                    .widgetAccentable()
                Spacer()
                if family != .systemSmall, entry.showsReminders {
                    Toggle(isOn: entry.habit.remindersOn, intent: ToggleRemindersIntent()) {
                        Image(systemName: "bell.fill")
                    }
                    .labelsHidden()
                }
            }
            Text("\(entry.habit.count) of \(entry.habit.goal)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .invalidatableContent()
            ProgressView(value: progress)
                .tint(.teal)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: LogHabitIntent(habitID: entry.habit.id, amount: -1)) {
                    Image(systemName: "minus")
                        .frame(maxWidth: .infinity)
                }
                Button(intent: LogHabitIntent(habitID: entry.habit.id, amount: 1)) {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.teal)
            .widgetAccentable()
        }
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Habit", intent: SelectHabitIntent.self, provider: HabitProvider()) { entry in
            HabitWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "habits://\(entry.habit.id)"))
        }
        .configurationDisplayName("Habit")
        .description("Log a habit without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(true)
    }
}

// MARK: Control

struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogWater") {
            ControlWidgetButton(action: LogHabitIntent(habitID: "water", amount: 1)) {
                Label("Log water", systemImage: "drop.fill")
            }
            .tint(.teal)
        }
        .displayName("Log water")
        .description("Adds a glass of water.")
    }
}

@main
struct HabitWidgets: WidgetBundle {
    var body: some Widget {
        HabitWidget()
        if #available(iOS 18.0, *) {
            LogWaterControl()
        }
    }
}

#Preview("Small", as: .systemSmall) {
    HabitWidget()
} timeline: {
    HabitEntry(date: .now, habit: .water, showsReminders: true)
}

#Preview("Medium", as: .systemMedium) {
    HabitWidget()
} timeline: {
    HabitEntry(date: .now, habit: .water, showsReminders: true)
    HabitEntry(date: .now, habit: .stretch, showsReminders: false)
}
