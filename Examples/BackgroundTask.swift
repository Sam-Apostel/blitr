import SwiftUI

// A .task that does its work off the main actor and then sets state, as loaders commonly do.
// Rendered, the screen shows the loaded state.

struct Loader {
    nonisolated func load() async -> [String] {
        await Task.detached { ["Lisbon", "Porto", "Coimbra"] }.value
    }
}

final class Feed: ObservableObject {
    @Published var count = 0
    func refresh() { DispatchQueue.global().async { self.count = 3 } }
}

struct BackgroundTaskView: View {
    @State private var cities: [String] = []
    @State private var status = "Loading…"
    @StateObject private var feed = Feed()
    var body: some View {
        List {
            Section(status) { ForEach(cities, id: \.self) { Text($0) } }
            Section("Feed") { Text("\(feed.count) new posts") }
        }
        .task {
            let loaded = await Loader().load()
            cities = loaded
            status = "Loaded \(loaded.count) cities"
        }
        .task(id: "detached") {
            await Task.detached { }.value
            await MainActor.run { }
        }
        .onAppear { feed.refresh() }
    }
}

#Preview { BackgroundTaskView() }
