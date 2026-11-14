import SwiftUI
import WatchKit
import WidgetKit
import AppIntents
import ActivityKit

// watchOS API (vertical paging, tab view container backgrounds, TextFieldLink, WatchKit, the corner widget
// family), App Shortcuts and ActivityKit's update sequences.

struct WorkoutPages: View {
    @State private var page = 1
    @State private var reply = ""

    var body: some View {
        TabView(selection: $page) {
            VStack(spacing: 8) {
                Image(systemName: "figure.run").font(.largeTitle)
                Text("Outdoor Run").font(.headline)
            }
            .containerBackground(Color.green.gradient, for: .tabView)
            .tag(0)
            VStack(spacing: 12) {
                Text("12:41").font(.system(size: 40, weight: .semibold).monospacedDigit())
                TextFieldLink("Reply", prompt: Text("Message")) { reply = $0 }
                TextFieldLink(prompt: Text("Note")) { Label("Add note", systemImage: "square.and.pencil") } onSubmit: { _ in }
            }
            .containerBackground(Color.orange.gradient, for: .tabView)
            .tag(1)
            Text("Summary").tag(2)
        }
        .tabViewStyle(.verticalPage(transitionStyle: .blur))
        .onAppear {
            WKInterfaceDevice.current().play(.start)
            _ = WKInterfaceDevice.current().screenBounds
        }
    }
}

func cornerLabel(for family: WidgetFamily) -> String {
    switch family {
    case .accessoryCorner: return "corner"
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return "accessory"
    default: return "system"
    }
}

/// An iOS switch over every iOS family needs no corner case, as on iOS.
func iOSLabel(for family: WidgetFamily) -> String {
    switch family {
    case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return "system"
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return "accessory"
    @unknown default: return "unknown"
    }
}

struct StartRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Run"
    @Parameter(title: "Distance") var distance: Double?
    func perform() async throws -> some IntentResult { .result() }
}

struct RunShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRunIntent(), phrases: ["Start a run in \(.applicationName)", "\(.applicationName) run \(\.$distance)"],
                    shortTitle: "Start Run", systemImageName: "figure.run")
    }
    static let shortcutTileColor = ShortcutTileColor.lime
}

struct RunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var pace: Double }
    var name: String
}

@MainActor
@Observable
final class ActivityWatcher {
    var started = 0
    func watch() async {
        for await activity in Activity<RunAttributes>.activityUpdates {
            started += 1
            for await state in activity.activityStateUpdates where state == .ended { break }
            for await _ in activity.contentUpdates {}
            for await _ in activity.pushTokenUpdates {}
        }
        for await _ in Activity<RunAttributes>.pushToStartTokenUpdates {}
    }
}

#Preview("Watch pages") {
    WorkoutPages()
        .environment(\.colorScheme, .dark)
}

#Preview("Shortcuts and activities") {
    @Previewable @State var watcher = ActivityWatcher()
    VStack(spacing: 8) {
        Text("\(RunShortcuts.appShortcuts.count) shortcut, tile \(RunShortcuts.shortcutTileColor == .lime ? "lime" : "other")")
        Text("Families: \(cornerLabel(for: .systemSmall)), \(iOSLabel(for: .accessoryInline))")
        Text("Activities started elsewhere: \(watcher.started)")
    }
    .task { await watcher.watch() }
}
