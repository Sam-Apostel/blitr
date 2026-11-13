import SwiftUI
import Observation

// MARK: - Model

struct AgendaEvent: Identifiable {
    let id = UUID()
    let title: String
    let start: String
    let end: String
    let location: String
    let color: Color
}

struct AgendaDay: Identifiable {
    let id = UUID()
    let title: String
    let events: [AgendaEvent]
}

@Observable
final class AgendaModel {
    var days: [AgendaDay] = []

    func load() {
        days = [
            AgendaDay(title: "Today, Nov 13", events: [
                AgendaEvent(title: "Design sync", start: "09:30", end: "10:15", location: "Room 4B", color: .blue),
                AgendaEvent(title: "Lunch with Priya", start: "12:30", end: "13:30", location: "Café Nord", color: .orange),
                AgendaEvent(title: "Sprint planning", start: "15:00", end: "16:30", location: "Main Hall", color: .purple),
            ]),
            AgendaDay(title: "Tomorrow, Nov 14", events: [
                AgendaEvent(title: "Dentist", start: "08:15", end: "09:00", location: "Elm Street Clinic", color: .red),
                AgendaEvent(title: "Climbing", start: "18:00", end: "19:30", location: "Boulder Barn", color: .green),
            ]),
            AgendaDay(title: "Saturday, Nov 15", events: [
                AgendaEvent(title: "Farmers market", start: "10:00", end: "11:30", location: "Town Square", color: .mint),
            ]),
        ]
    }

    func filtered(_ query: String) -> [AgendaDay] {
        guard !query.isEmpty else { return days }
        return days.compactMap { day in
            let matches = day.events.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : AgendaDay(title: day.title, events: matches)
        }
    }
}

// MARK: - Subviews

struct AgendaRow: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(event.color)
                .frame(width: 4, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.start) – \(event.end)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(event.title).font(.headline)
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AgendaNewEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var allDay = false
    @State private var start = Date(timeIntervalSince1970: 1_763_026_800)
    @State private var end = Date(timeIntervalSince1970: 1_763_030_400)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: .constant(""))
                }
                Section {
                    Toggle("All-day", isOn: $allDay)
                    DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { dismiss() }.disabled(title.isEmpty) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Screen

struct AgendaScreen: View {
    @State private var model = AgendaModel()
    @State private var search = ""
    @State private var showNewEvent: Bool

    init(showNewEvent: Bool = false) {
        _showNewEvent = State(initialValue: showNewEvent)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.filtered(search)) { day in
                    Section(day.title) {
                        ForEach(day.events) { AgendaRow(event: $0) }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Agenda")
            .searchable(text: $search, prompt: "Search events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewEvent = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add event")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { }
                }
            }
            .sheet(isPresented: $showNewEvent) { AgendaNewEventSheet() }
            .task { model.load() }
        }
    }
}

#Preview {
    AgendaScreen()
}

#Preview("New event sheet") {
    AgendaScreen(showNewEvent: true)
}
