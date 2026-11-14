// An app's own types named like framework types (ActivityKit's Activity, MapKit's Map and Marker,
// TipKit's Tip, os's Logger, WidgetKit's Timeline). With only `import SwiftUI` none of those
// frameworks is visible, so these names are the app's own, as on iOS.
import SwiftUI

struct Activity: Identifiable {
    let id = UUID()
    var title: String
    var minutes: Int
}

struct Marker: Hashable {
    var label: String
    var color: Color
}

struct Map {
    var name: String
    var markers: [Marker]
}

struct Tip {
    var text: String
}

final class Logger {
    private(set) var lines: [String] = []
    func log(_ line: String) { lines.append(line) }
}

struct Timeline {
    var activities: [Activity]
    var totalMinutes: Int { activities.reduce(0) { $0 + $1.minutes } }
}

struct TrainingPlanView: View {
    let timeline = Timeline(activities: [
        Activity(title: "Warm-up", minutes: 10),
        Activity(title: "Intervals", minutes: 25),
        Activity(title: "Cool-down", minutes: 8),
    ])
    let map = Map(name: "Riverside loop", markers: [
        Marker(label: "Start", color: .green),
        Marker(label: "Bridge", color: .orange),
        Marker(label: "Finish", color: .red),
    ])
    let tip = Tip(text: "Keep the intervals at a pace you can talk at.")
    let logger = Logger()

    var body: some View {
        NavigationStack {
            List {
                Section("Today · \(timeline.totalMinutes) min") {
                    ForEach(timeline.activities) { activity in
                        LabeledContent(activity.title, value: "\(activity.minutes) min")
                    }
                }
                Section(map.name) {
                    ForEach(map.markers, id: \.self) { marker in
                        Label(marker.label, systemImage: "mappin.circle.fill")
                            .foregroundStyle(marker.color)
                    }
                }
                Section {
                    Label(tip.text, systemImage: "lightbulb")
                }
            }
            .navigationTitle("Training")
            .onAppear { logger.log("shown") }
        }
    }
}

#Preview {
    TrainingPlanView()
}
